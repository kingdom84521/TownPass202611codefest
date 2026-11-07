import 'package:flutter/foundation.dart';
import 'package:town_pass/page/service_assistant/gemini_service_matcher.dart';
import 'package:town_pass/page/service_assistant/rag/rag_document.dart';
import 'package:town_pass/page/service_assistant/rag/rag_retriever.dart';
import 'package:town_pass/page/service_assistant/rag/rag_vector_store.dart';
import 'package:town_pass/page/service_assistant/rag/service_inventory_corpus.dart';

/// RAG 的「生成」端：給定檢索結果產生回答，以及在檢索太弱時改寫問句。
/// 正式實作是 [GeminiServiceMatcher]；測試可換成假的。
abstract interface class RagGenerator {
  bool get isEnabled;

  /// 只根據 [context] 回答；挑出的服務必須在 [context] 內。
  Future<AiMatchResult> generate(String query, List<RagHit> context);

  /// 把問句改寫成辭庫常見的繁體中文關鍵詞。
  Future<List<String>> rewriteQuery(String query);
}

/// 把問句轉成向量，供語意檢索使用。正式實作是 [GeminiServiceMatcher]。
abstract interface class QueryEmbedder {
  bool get isEnabled;

  /// 必須與向量檔的模型相同，否則向量不能比較。
  String get embeddingModel;

  Future<List<double>> embedQuery(String query);
}

/// 檢索階段的結果。
class RagRetrieval {
  const RagRetrieval({
    required this.query,
    required this.hits,
    this.rewrittenKeywords = const [],
    this.usedVectors = false,
  });

  final String query;

  /// 依分數排序、將交給 LLM 的參考資料。
  final List<RagHit> hits;

  /// 檢索太弱時由 LLM 改寫出的關鍵詞；沒有改寫時為空。
  final List<String> rewrittenKeywords;

  /// 這次是否用到向量（語意）檢索；沒有向量檔、沒有金鑰或向量化失敗時為 false。
  final bool usedVectors;

  bool get wasRewritten => rewrittenKeywords.isNotEmpty;
}

/// 服務小幫手的 RAG 流程（混合檢索）：
///
/// 1. **檢索**，兩路並行：
///    - 關鍵字：[RagRetriever]（BM25，手機上算，不需網路）
///    - 語意：問句轉成向量（[QueryEmbedder]），在 [RagVectorStore] 預先算好的文件向量中找 cosine 最近的
///
///    兩路結果用 RRF（Reciprocal Rank Fusion）合併排序，取前 [contextSize] 筆。
/// 2. **查詢改寫**：兩路都太弱時（BM25 最高分 < [weakScore] 且 cosine 最高 < [weakCosine]），
///    請 LLM 改寫成中文關鍵詞，再跑一次 BM25 後重新合併。
/// 3. **增強生成**：只把檢索到的文件交給 LLM，LLM 只能從中挑選服務並據此回覆。
///
/// 向量路徑任何一步失敗（沒有向量檔、模型不符、API 錯誤）都只會退回純 BM25，不影響回答。
class ServiceRag {
  ServiceRag({required this.corpus, required this.generator, this.vectors, this.embedder})
      : retriever = RagRetriever(corpus.documents);

  /// 交給 LLM 的參考資料筆數上限。
  static const int contextSize = 8;

  /// 每一路先各取這麼多筆候選，再合併。
  static const int candidatePool = 20;

  /// RRF 的平滑常數（文獻常用 60）：分數 = Σ 1 /（k + 名次）。
  static const int rrfK = 60;

  /// BM25 最高分低於此值視為關鍵字檢索太弱。
  /// 參考值（2026-11-07 以辭庫實測）：名稱或同義詞直接命中約 10–30；只有零星單字重疊約 2–7。
  static const double weakScore = 8;

  /// cosine 最高值低於此值視為語意檢索太弱。
  /// 參考值（2026-11-07，gemini-embedding-2／768 維實測）：相關問句的第一名約 0.67–0.75，
  /// 與服務無關的問句（天氣、餐廳）約 0.63–0.64。
  static const double weakCosine = 0.655;

  final ServiceInventoryCorpus corpus;
  final RagGenerator generator;
  final RagVectorStore? vectors;
  final QueryEmbedder? embedder;
  final RagRetriever retriever;

  /// 向量路徑可用：有向量檔、有金鑰、模型一致。
  bool get vectorSearchEnabled =>
      vectors != null &&
      !vectors!.isEmpty &&
      embedder != null &&
      embedder!.isEnabled &&
      embedder!.embeddingModel == vectors!.model;

  static Future<ServiceRag> load({required RagGenerator generator, QueryEmbedder? embedder}) async {
    final ServiceInventoryCorpus corpus = await ServiceInventoryCorpus.load();
    final RagVectorStore? vectors = await RagVectorStore.load(documents: corpus.documents);
    debugPrint('[服務小幫手/RAG] 辭庫載入 ${corpus.documents.length} 筆，清冊基準 ${corpus.sourceCommit}；'
        '向量 ${vectors?.size ?? 0} 筆（${vectors?.model ?? '無向量檔'}）'
        '${vectors == null || vectors.staleIds.isEmpty ? '' : '，過期 ${vectors.staleIds.length} 筆：${vectors.staleIds}'}');
    return ServiceRag(corpus: corpus, generator: generator, vectors: vectors, embedder: embedder);
  }

  /// 第 1、2 步：混合檢索，必要時改寫後再檢索。改寫或向量化失敗都不影響流程。
  Future<RagRetrieval> retrieve(String query) async {
    final List<RagHit> keyword = retriever.retrieve(query, limit: candidatePool);
    final List<RagHit> semantic = await _vectorSearch(query);
    final bool usedVectors = semantic.isNotEmpty;

    final double bm25Top = keyword.isEmpty ? 0 : keyword.first.score;
    final double cosineTop = semantic.isEmpty ? 0 : semantic.first.score;
    final bool weak = bm25Top < weakScore && (!usedVectors || cosineTop < weakCosine);
    if (!weak || !generator.isEnabled) {
      return RagRetrieval(query: query, hits: fuse(keyword, semantic), usedVectors: usedVectors);
    }

    List<String> keywords;
    try {
      keywords = await generator.rewriteQuery(query);
    } on AiMatchException {
      keywords = const [];
    }
    if (keywords.isEmpty) {
      return RagRetrieval(query: query, hits: fuse(keyword, semantic), usedVectors: usedVectors);
    }

    final List<RagHit> rewritten = retriever.retrieve(keywords.join(' '), limit: candidatePool);
    return RagRetrieval(
      query: query,
      hits: fuse(merge(keyword, rewritten, limit: candidatePool), semantic),
      rewrittenKeywords: keywords,
      usedVectors: usedVectors,
    );
  }

  Future<List<RagHit>> _vectorSearch(String query) async {
    if (!vectorSearchEnabled) return const [];
    try {
      final List<double> vector = await embedder!.embedQuery(query);
      return vectors!.search(vector, limit: candidatePool);
    } on AiMatchException {
      // 已由 GeminiServiceMatcher 記錄；退回只用 BM25
      return const [];
    }
  }

  /// 第 3 步：只根據 [retrieval] 的文件生成回答。沒有任何參考資料時不呼叫 LLM。
  Future<AiMatchResult> generate(RagRetrieval retrieval) async {
    if (retrieval.hits.isEmpty) {
      return const AiMatchResult(entries: [], reply: '');
    }
    return generator.generate(retrieval.query, retrieval.hits);
  }

  /// RRF 合併兩路排名：同一文件在兩路的名次各貢獻 1 /（[rrfK] + 名次），
  /// 兩路都排前面的文件分數最高。保留各路原始分數（bm25、cosine）供除錯與顯示。
  @visibleForTesting
  static List<RagHit> fuse(List<RagHit> keyword, List<RagHit> semantic) {
    final Map<String, double> scores = {};
    final Map<String, RagDocument> documents = {};
    final Map<String, double> bm25 = {};
    final Map<String, double> cosine = {};
    void add(List<RagHit> ranked, Map<String, double> raw) {
      for (int rank = 0; rank < ranked.length; rank++) {
        final RagHit hit = ranked[rank];
        final String id = hit.document.id;
        documents[id] = hit.document;
        scores[id] = (scores[id] ?? 0) + 1 / (rrfK + rank + 1);
        raw[id] = hit.score;
      }
    }

    add(keyword, bm25);
    add(semantic, cosine);
    final List<RagHit> fused = [
      for (final String id in scores.keys) RagHit(documents[id]!, scores[id]!, bm25: bm25[id], cosine: cosine[id]),
    ]..sort((a, b) => b.score.compareTo(a.score));
    return fused.take(contextSize).toList();
  }

  /// 合併兩次 BM25 檢索：同一文件取較高分，依分數排序後取前 [limit] 筆。
  @visibleForTesting
  static List<RagHit> merge(List<RagHit> a, List<RagHit> b, {int limit = contextSize}) {
    final Map<String, RagHit> best = {};
    for (final RagHit hit in [...a, ...b]) {
      final RagHit? existing = best[hit.document.id];
      if (existing == null || hit.score > existing.score) best[hit.document.id] = hit;
    }
    final List<RagHit> merged = best.values.toList()..sort((x, y) => y.score.compareTo(x.score));
    return merged.take(limit).toList();
  }
}
