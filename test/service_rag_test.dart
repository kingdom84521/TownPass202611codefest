import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/page/service_assistant/gemini_service_matcher.dart';
import 'package:town_pass/page/service_assistant/rag/rag_document.dart';
import 'package:town_pass/page/service_assistant/rag/rag_retriever.dart';
import 'package:town_pass/page/service_assistant/rag/rag_vector_store.dart';
import 'package:town_pass/page/service_assistant/rag/service_inventory_corpus.dart';
import 'package:town_pass/page/service_assistant/rag/service_rag.dart';
import 'package:town_pass/page/service_assistant/service_assistant_controller.dart';

/// 不打網路的生成端：記錄收到的參考資料，回傳指定結果。
class _FakeGenerator implements RagGenerator {
  _FakeGenerator({
    this.enabled = true,
    this.pick = const [],
    this.reply = '',
    this.rewrite = const [],
    this.generateError,
    this.rewriteError,
  });

  final bool enabled;
  final List<String> pick;
  final String reply;
  final List<String> rewrite;
  final AiMatchException? generateError;
  final AiMatchException? rewriteError;

  int generateCalls = 0;
  int rewriteCalls = 0;
  List<RagHit> lastContext = const [];

  @override
  bool get isEnabled => enabled;

  @override
  Future<AiMatchResult> generate(String query, List<RagHit> context) async {
    generateCalls++;
    lastContext = context;
    if (generateError != null) throw generateError!;
    final List<RagDocument> documents = [
      for (final String title in pick) context.firstWhere((hit) => hit.document.title == title).document,
    ];
    return AiMatchResult(entries: documents.map((d) => d.action).toList(), reply: reply, documents: documents);
  }

  @override
  Future<List<String>> rewriteQuery(String query) async {
    rewriteCalls++;
    if (rewriteError != null) throw rewriteError!;
    return rewrite;
  }
}

/// 不打網路的問句向量化：回傳指定向量或錯誤。
class _FakeEmbedder implements QueryEmbedder {
  _FakeEmbedder({this.vector = const [], this.error, this.model = RagVectorStore.embeddingModel});

  final List<double> vector;
  final AiMatchException? error;
  final String model;
  int calls = 0;

  @override
  bool get isEnabled => true;

  @override
  String get embeddingModel => model;

  @override
  Future<List<double>> embedQuery(String query) async {
    calls++;
    if (error != null) throw error!;
    return vector;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ServiceInventoryCorpus corpus;
  late RagRetriever retriever;

  setUpAll(() async {
    corpus = await ServiceInventoryCorpus.load();
    retriever = RagRetriever(corpus.documents);
  });

  RagDocument doc(String title) => corpus.documents.firstWhere((d) => d.title == title);

  group('ServiceInventoryCorpus（辭庫）', () {
    test('loads every service from the inventory asset', () {
      expect(corpus.sourceCommit, 'e65b586');
      final Iterable<RagDocument> services = corpus.documents.where((d) => d.id.startsWith('service:'));
      expect(services, hasLength(21));
      expect(services.every((d) => d.source == RagSource.inventory), isTrue);
    });

    test('titles are unique (the LLM answers by title)', () {
      final List<String> titles = corpus.documents.map((d) => d.title).toList();
      expect(titles.toSet().length, titles.length);
    });

    test('entry labels pointing at a service become aliases, not duplicates', () {
      expect(doc('警政服務').aliases, contains('警政報案'));
      expect(corpus.documents.where((d) => d.title == '警政報案'), isEmpty);
      expect(doc('警政服務').action.uri, 'local://online_police', reason: '沿用小幫手可開啟的警政報案頁');
    });

    test('developer notes from the inventory are not exposed to the LLM', () {
      expect(doc('警政服務').body, isNot(contains('local://')));
      expect(corpus.documents.every((d) => !d.body.contains('卡片 B')), isTrue);
    });

    test('subpage items become documents with readable titles and actions', () {
      final RagDocument fraud = doc('165 反詐騙專線');
      expect(fraud.id, 'subpage:online_police:165');
      expect(fraud.body, contains('警政報案系統'));
      expect(fraud.action.onOpen, isNotNull, reason: '撥號前要先確認');
      expect(doc('110 緊急報案').action.title, '緊急求救', reason: '110、119 沿用緊急求救對話框');
      expect(doc('網路報案').action.uri, 'https://taipei-pass-service.vercel.app/police-report');
    });

    test('items outside the inventory scope are still searchable', () {
      expect(doc('停車費').source, RagSource.catalog);
      expect(doc('緊急求救').source, RagSource.catalog);
      expect(doc('翻譯語言').source, RagSource.catalog);
    });

    test('services without a URL are marked as not yet open', () {
      expect(doc('聯醫掛號').isComingSoon, isTrue);
      expect(doc('聯醫掛號').toContextLine(), endsWith('（尚未開放）'));
      expect(doc('圖書借閱').isComingSoon, isFalse);
    });
  });

  group('RagRetriever（BM25 檢索）', () {
    String top(String query) => retriever.retrieve(query).first.document.title;

    test('ranks the most specific document first', () {
      expect(top('我想借書'), '圖書借閱');
      expect(top('我被詐騙了'), '165 反詐騙專線');
      expect(top('查一下我的報案進度'), '案件查詢');
      expect(top('颱風淹水'), '災情通報');
      expect(top('幫我繳停車費'), '停車費');
      expect(top('要看醫生'), '聯醫掛號');
    });

    test('aliases are searchable', () {
      expect(top('警政報案'), '警政服務');
    });

    test('returns nothing when there is no shared term', () {
      expect(retriever.retrieve('my wallet was stolen'), isEmpty);
      expect(retriever.retrieve('今天天氣如何'), isEmpty);
      expect(retriever.retrieve(''), isEmpty);
    });

    test('respects the limit and sorts by score', () {
      final List<RagHit> hits = retriever.retrieve('繳費', limit: 3);
      expect(hits, hasLength(3));
      expect(hits[0].score >= hits[1].score && hits[1].score >= hits[2].score, isTrue);
    });

    test('tokenizes Chinese into unigrams + bigrams and keeps latin words whole', () {
      expect(RagRetriever.tokenize('借書'), ['借', '書', '借書']);
      expect(RagRetriever.tokenize('Covid-19 疫苗'), ['covid19', '疫', '苗', '疫苗']);
    });
  });

  group('ServiceRag（RAG 流程）', () {
    test('strong retrieval goes straight to generation without rewriting', () async {
      final _FakeGenerator generator = _FakeGenerator(pick: ['165 反詐騙專線']);
      final ServiceRag rag = ServiceRag(corpus: corpus, generator: generator);

      final RagRetrieval retrieval = await rag.retrieve('我被詐騙了');
      final AiMatchResult result = await rag.generate(retrieval);

      expect(generator.rewriteCalls, 0);
      expect(retrieval.wasRewritten, isFalse);
      expect(generator.lastContext.length, lessThanOrEqualTo(ServiceRag.contextSize));
      expect(generator.lastContext.first.document.title, '165 反詐騙專線');
      expect(result.entries.single.title, '165 反詐騙專線');
    });

    test('weak retrieval is rewritten by the LLM and retrieved again', () async {
      final _FakeGenerator generator = _FakeGenerator(rewrite: ['遺失', '報案']);
      final ServiceRag rag = ServiceRag(corpus: corpus, generator: generator);

      final RagRetrieval retrieval = await rag.retrieve('my wallet was stolen');

      expect(generator.rewriteCalls, 1);
      expect(retrieval.rewrittenKeywords, ['遺失', '報案']);
      expect(retrieval.hits.map((h) => h.document.title), contains('警政服務'));
    });

    test('a failed rewrite keeps the original retrieval', () async {
      final _FakeGenerator generator =
          _FakeGenerator(rewriteError: const AiMatchException('AI 回應逾時', 'timeout'));
      final ServiceRag rag = ServiceRag(corpus: corpus, generator: generator);

      final RagRetrieval retrieval = await rag.retrieve('樓上很吵');

      expect(retrieval.wasRewritten, isFalse);
      expect(retrieval.hits.first.document.title, '有話要說');
    });

    test('no context means no LLM call and an empty answer', () async {
      final _FakeGenerator generator = _FakeGenerator();
      final ServiceRag rag = ServiceRag(corpus: corpus, generator: generator);

      final AiMatchResult result = await rag.generate(const RagRetrieval(query: '今天天氣如何', hits: []));

      expect(generator.generateCalls, 0);
      expect(result.entries, isEmpty);
    });

    test('merge keeps the higher score per document and the size limit', () {
      final RagDocument library = doc('圖書借閱');
      final List<RagHit> merged = ServiceRag.merge(
        [RagHit(library, 3), RagHit(doc('找地點'), 5)],
        [RagHit(library, 9)],
      );
      expect(merged.first.document, library);
      expect(merged.first.score, 9);
      expect(merged, hasLength(2));
    });
  });

  group('RagVectorStore（向量檔）', () {
    late RagVectorStore store;
    setUpAll(() async => store = (await RagVectorStore.load(documents: corpus.documents))!);

    test('has a fresh vector for every document', () {
      expect(store.model, RagVectorStore.embeddingModel);
      expect(store.dimensions, RagVectorStore.embeddingDimensions);
      expect(store.size, corpus.documents.length);
      expect(store.staleIds, isEmpty, reason: '辭庫改了要重跑 tool/rag/build_embeddings_test.dart');
    });

    test('a document vector finds itself first with cosine ≈ 1', () {
      final List<RagHit> hits = store.search(store.vectorOf('service:library')!, limit: 3);
      expect(hits.first.document.title, '圖書借閱');
      expect(hits.first.cosine, closeTo(1, 1e-3));
      expect(hits.first.score >= hits[1].score, isTrue);
    });

    test('wrong dimensions return nothing', () {
      expect(store.search([1, 0, 0]), isEmpty);
    });

    test('changed documents are detected as stale and skipped', () {
      final Map<String, Object> json = {
        'model': RagVectorStore.embeddingModel,
        'dimensions': 2,
        'documents': [
          {'id': 'service:library', 'fingerprint': doc('圖書借閱').fingerprint, 'vector': [1.0, 0.0]},
          {'id': 'service:zoo', 'fingerprint': 'deadbeef', 'vector': [0.0, 1.0]},
        ],
      };
      final RagVectorStore small = RagVectorStore.fromJson(json, documents: corpus.documents);
      expect(small.size, 1);
      expect(small.staleIds, contains('service:zoo'));
      expect(small.staleIds, contains('service:police'), reason: '沒有向量的文件也算過期');
      expect(small.search([0.0, 1.0]).single.document.title, '圖書借閱');
    });
  });

  group('ServiceRag 混合檢索（BM25＋向量，RRF）', () {
    late RagVectorStore store;
    setUpAll(() async => store = (await RagVectorStore.load(documents: corpus.documents))!);

    test('RRF ranks documents found by both paths first and keeps raw scores', () {
      final List<RagHit> fused = ServiceRag.fuse(
        [RagHit(doc('找地點'), 16, bm25: 16), RagHit(doc('親子館'), 5, bm25: 5)],
        [RagHit(doc('親子館'), 0.71, cosine: 0.71), RagHit(doc('愛遊動物園'), 0.66, cosine: 0.66)],
      );
      expect(fused.first.document.title, '親子館', reason: '兩路都有命中');
      expect(fused.first.bm25, 5);
      expect(fused.first.cosine, 0.71);
      expect(fused.map((h) => h.document.title), ['親子館', '找地點', '愛遊動物園']);
    });

    test('vector path finds what keywords cannot, without rewriting', () async {
      final _FakeGenerator generator = _FakeGenerator(rewrite: ['不該被呼叫']);
      final _FakeEmbedder embedder = _FakeEmbedder(vector: store.vectorOf('service:zoo')!);
      final ServiceRag rag = ServiceRag(corpus: corpus, generator: generator, vectors: store, embedder: embedder);

      final RagRetrieval retrieval = await rag.retrieve('where can I see pandas');

      expect(embedder.calls, 1);
      expect(retrieval.usedVectors, isTrue);
      expect(retrieval.hits.first.document.title, '愛遊動物園');
      expect(generator.rewriteCalls, 0, reason: '語意檢索夠強就不改寫');
    });

    test('embedding failure falls back to BM25 only', () async {
      final _FakeEmbedder embedder = _FakeEmbedder(error: const AiMatchException('AI 回應逾時', 'timeout'));
      final ServiceRag rag =
          ServiceRag(corpus: corpus, generator: _FakeGenerator(), vectors: store, embedder: embedder);

      final RagRetrieval retrieval = await rag.retrieve('我被詐騙了');

      expect(retrieval.usedVectors, isFalse);
      expect(retrieval.hits.first.document.title, '165 反詐騙專線');
    });

    test('a different embedding model disables the vector path', () async {
      final _FakeEmbedder embedder = _FakeEmbedder(vector: store.vectorOf('service:zoo')!, model: 'other-model');
      final ServiceRag rag =
          ServiceRag(corpus: corpus, generator: _FakeGenerator(), vectors: store, embedder: embedder);

      expect(rag.vectorSearchEnabled, isFalse);
      await rag.retrieve('我被詐騙了');
      expect(embedder.calls, 0);
    });

    test('rewrite only happens when both paths are weak', () async {
      // 與所有文件幾乎正交的向量：cosine 很低
      final List<double> unrelated = List<double>.filled(RagVectorStore.embeddingDimensions, 0)..[0] = 1;
      final _FakeGenerator generator = _FakeGenerator(rewrite: ['天氣']);
      final ServiceRag rag = ServiceRag(
        corpus: corpus,
        generator: generator,
        vectors: store,
        embedder: _FakeEmbedder(vector: unrelated),
      );

      final RagRetrieval retrieval = await rag.retrieve('今天天氣如何');

      expect(retrieval.hits.first.cosine ?? 0, lessThan(ServiceRag.weakCosine));
      expect(generator.rewriteCalls, 1);
    });

    test('controller grounding note mentions semantic retrieval', () async {
      final _FakeGenerator generator = _FakeGenerator(pick: ['愛遊動物園'], reply: '可以去動物園');
      final ServiceAssistantController controller = ServiceAssistantController(
        rag: ServiceRag(
          corpus: corpus,
          generator: generator,
          vectors: store,
          embedder: _FakeEmbedder(vector: store.vectorOf('service:zoo')!),
        ),
      );

      await controller.send('where can I see pandas');

      expect(controller.messages.last.results.single.title, '愛遊動物園');
      expect(controller.messages.last.groundingNote, contains('keyword + semantic search'), reason: '英文問句用英文說明');
    });
  });

  group('ServiceAssistantController with RAG', () {
    ServiceAssistantController controllerWith(_FakeGenerator generator) =>
        ServiceAssistantController(rag: ServiceRag(corpus: corpus, generator: generator));

    test('confident keyword match does not call the LLM', () async {
      final _FakeGenerator generator = _FakeGenerator();
      final ServiceAssistantController controller = controllerWith(generator);

      await controller.send('圖書借閱');

      expect(generator.generateCalls, 0);
      expect(controller.messages.last.results.first.title, '圖書借閱');
      expect(controller.messages.last.groundingNote, isNull);
    });

    test('weak keyword match runs RAG and shows what the answer is based on', () async {
      final _FakeGenerator generator = _FakeGenerator(pick: ['有話要說'], reply: '可以向市府陳情');
      final ServiceAssistantController controller = controllerWith(generator);

      await controller.send('隔壁工地一大早就在施工好吵');

      expect(generator.generateCalls, 1);
      expect(generator.lastContext.map((h) => h.document.title), containsAll(['施工資訊', '有話要說']));
      expect(controller.messages.last.text, '可以向市府陳情');
      expect(controller.messages.last.results.map((e) => e.title), ['有話要說']);
      expect(controller.messages.last.groundingNote, startsWith('依據服務清冊'));
      expect(controller.messages.where((m) => m.text.contains('讓我想想')), isEmpty, reason: '等待訊息要移除');
      expect(controller.isThinking.value, isFalse);
    });

    test('a rewritten query is shown in the grounding note', () async {
      final _FakeGenerator generator = _FakeGenerator(rewrite: ['詐騙'], pick: ['165 反詐騙專線']);
      final ServiceAssistantController controller = controllerWith(generator);

      await controller.send('Someone scammed me on the phone');

      expect(controller.messages.last.results.single.title, '165 反詐騙專線');
      expect(controller.messages.last.groundingNote, contains('rewritten as "詐騙"'), reason: '英文問句用英文說明');
      expect(controller.messages.last.groundingNote, contains('(keyword search'), reason: '沒有向量時只標關鍵字');
    });

    test('LLM failure falls back to keyword results with a note', () async {
      final _FakeGenerator generator =
          _FakeGenerator(generateError: const AiMatchException('AI 回應逾時', 'timeout'));
      final ServiceAssistantController controller = controllerWith(generator);

      await controller.send('樓上很吵');

      expect(controller.messages.last.text, contains('AI 回應逾時'));
      expect(controller.messages.last.results.first.title, '有話要說');
      expect(controller.isThinking.value, isFalse);
    });

    test('works without an AI key (keyword only, no corpus needed)', () async {
      final _FakeGenerator generator = _FakeGenerator(enabled: false);
      final ServiceAssistantController controller = controllerWith(generator);

      await controller.send('樓上很吵');

      expect(generator.generateCalls, 0);
      expect(controller.messages.last.results.first.title, '有話要說');
    });
  });
}
