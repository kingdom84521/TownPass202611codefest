import 'package:flutter/foundation.dart';
import 'package:town_pass/page/service_assistant/gemini_service_matcher.dart';
import 'package:town_pass/page/service_assistant/rag/rag_document.dart';
import 'package:town_pass/page/service_assistant/rag/rag_retriever.dart';
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

/// 檢索階段的結果。
class RagRetrieval {
  const RagRetrieval({required this.query, required this.hits, this.rewrittenKeywords = const []});

  final String query;

  /// 依分數排序、將交給 LLM 的參考資料。
  final List<RagHit> hits;

  /// 檢索太弱時由 LLM 改寫出的關鍵詞；沒有改寫時為空。
  final List<String> rewrittenKeywords;

  bool get wasRewritten => rewrittenKeywords.isNotEmpty;
}

/// 服務小幫手的 RAG 流程：
///
/// 1. **檢索**：用 [RagRetriever]（BM25）從辭庫找出最相關的 [contextSize] 筆文件。
/// 2. **查詢改寫**：最高分低於 [weakScore]（或完全找不到）時，請 LLM 把問句改寫成中文關鍵詞再檢索一次，
///    兩次結果合併（同一文件取較高分）。接住外語、口語與錯字。
/// 3. **增強生成**：只把檢索到的文件交給 LLM，LLM 只能從中挑選服務並據此回覆。
///
/// 辭庫來自 `assets/rag/service_inventory.json`，見 [ServiceInventoryCorpus]。
class ServiceRag {
  ServiceRag({required this.corpus, required this.generator}) : retriever = RagRetriever(corpus.documents);

  /// 交給 LLM 的參考資料筆數上限。
  static const int contextSize = 8;

  /// 最高分低於此值視為檢索太弱，觸發查詢改寫。
  /// 參考值（2026-11-07 以辭庫實測）：名稱或同義詞直接命中約 10–30；只有零星單字重疊約 2–7。
  static const double weakScore = 8;

  final ServiceInventoryCorpus corpus;
  final RagGenerator generator;
  final RagRetriever retriever;

  static Future<ServiceRag> load({required RagGenerator generator}) async {
    final ServiceInventoryCorpus corpus = await ServiceInventoryCorpus.load();
    debugPrint('[服務小幫手/RAG] 辭庫載入 ${corpus.documents.length} 筆，清冊基準 ${corpus.sourceCommit}');
    return ServiceRag(corpus: corpus, generator: generator);
  }

  /// 第 1、2 步：檢索，必要時改寫後再檢索。改寫失敗不影響流程，沿用原本的檢索結果。
  Future<RagRetrieval> retrieve(String query) async {
    final List<RagHit> first = retriever.retrieve(query, limit: contextSize);
    final double top = first.isEmpty ? 0 : first.first.score;
    if (top >= weakScore || !generator.isEnabled) {
      return RagRetrieval(query: query, hits: first);
    }

    List<String> keywords;
    try {
      keywords = await generator.rewriteQuery(query);
    } on AiMatchException {
      return RagRetrieval(query: query, hits: first);
    }
    if (keywords.isEmpty) {
      return RagRetrieval(query: query, hits: first);
    }

    final List<RagHit> second = retriever.retrieve(keywords.join(' '), limit: contextSize);
    return RagRetrieval(query: query, hits: merge(first, second), rewrittenKeywords: keywords);
  }

  /// 第 3 步：只根據 [retrieval] 的文件生成回答。沒有任何參考資料時不呼叫 LLM。
  Future<AiMatchResult> generate(RagRetrieval retrieval) async {
    if (retrieval.hits.isEmpty) {
      return const AiMatchResult(entries: [], reply: '');
    }
    return generator.generate(retrieval.query, retrieval.hits);
  }

  /// 合併兩次檢索：同一文件取較高分，依分數排序後取前 [contextSize] 筆。
  @visibleForTesting
  static List<RagHit> merge(List<RagHit> a, List<RagHit> b) {
    final Map<String, RagHit> best = {};
    for (final RagHit hit in [...a, ...b]) {
      final RagHit? existing = best[hit.document.id];
      if (existing == null || hit.score > existing.score) best[hit.document.id] = hit;
    }
    final List<RagHit> merged = best.values.toList()..sort((x, y) => y.score.compareTo(x.score));
    return merged.take(contextSize).toList();
  }
}
