import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:town_pass/page/service_assistant/gemini_service_matcher.dart';
import 'package:town_pass/page/service_assistant/rag/rag_document.dart';
import 'package:town_pass/page/service_assistant/rag/service_inventory_corpus.dart';
import 'package:town_pass/page/service_assistant/rag/service_rag.dart';
import 'package:town_pass/page/service_assistant/service_assistant_controller.dart';
import 'package:town_pass/page/service_assistant/service_search.dart';
import 'package:town_pass/service/user_traits/trait_aggregator.dart';
import 'package:town_pass/service/user_traits/user_trait.dart';
import 'package:town_pass/service/user_traits/user_trait_recorder.dart';
import 'package:town_pass/service/user_traits/user_trait_repository.dart';

final DateTime _now = DateTime(2026, 11, 7, 12);

TraitObservation _obs(
  TraitDimension dimension,
  String value,
  double confidence, {
  String evidence = 'q:1',
  TraitSource source = TraitSource.llm,
  Duration age = Duration.zero,
}) =>
    TraitObservation(
      dimension: dimension,
      value: value,
      confidence: confidence,
      source: source,
      evidenceKey: evidence,
      observedAt: _now.subtract(age),
    );

double _confidence(List<UserTrait> traits, TraitDimension dimension, String value) =>
    traits.firstWhere((t) => t.dimension == dimension && t.value == value).confidence;

/// 測試控制器用：不寫資料庫，只記下被呼叫的內容。
class _SpyRecorder extends UserTraitRecorder {
  final List<String> calls = [];

  @override
  Future<void> recordInferred(String query, List<InferredTrait> traits, {String? model}) async =>
      calls.add('inferred:$query:${traits.map((t) => '${t.dimension.name}=${t.value}').join(',')}');

  @override
  Future<void> recordKeywordMatch(String query, ServiceSearchEntry top) async => calls.add('keyword:$query:${top.title}');

  @override
  Future<void> recordOpened(String query, ServiceSearchEntry entry) async => calls.add('opened:$query:${entry.title}');
}

class _TraitGenerator implements RagGenerator {
  _TraitGenerator(this.traits);

  final List<InferredTrait> traits;

  @override
  bool get isEnabled => true;

  @override
  Future<AiMatchResult> generate(String query, List<RagHit> context) async =>
      AiMatchResult(entries: [context.first.document.action], reply: 'ok', traits: traits);

  @override
  Future<List<String>> rewriteQuery(String query) async => const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('TraitAggregator（可信度）', () {
    test('different questions corroborate each other (noisy-OR)', () {
      final List<UserTrait> traits = TraitAggregator.aggregate([
        _obs(TraitDimension.interest, 'reading', 0.6, evidence: 'q:1'),
        _obs(TraitDimension.interest, 'reading', 0.6, evidence: 'q:2'),
      ], now: _now);
      expect(_confidence(traits, TraitDimension.interest, 'reading'), closeTo(0.84, 1e-9));
      expect(traits.single.evidenceCount, 2);
    });

    test('asking the same question again does not inflate confidence', () {
      final List<UserTrait> traits = TraitAggregator.aggregate([
        _obs(TraitDimension.interest, 'reading', 0.6, evidence: 'q:1'),
        _obs(TraitDimension.interest, 'reading', 0.6, evidence: 'q:1'),
        _obs(TraitDimension.interest, 'reading', 0.4, evidence: 'q:1'),
      ], now: _now);
      expect(_confidence(traits, TraitDimension.interest, 'reading'), closeTo(0.6, 1e-9));
      expect(traits.single.evidenceCount, 1);
    });

    test('contradictions lower confidence in exclusive dimensions only', () {
      final List<UserTrait> traits = TraitAggregator.aggregate([
        _obs(TraitDimension.transport, 'car_scooter', 0.6, evidence: 'q:1'),
        _obs(TraitDimension.transport, 'car_scooter', 0.6, evidence: 'q:2'),
        _obs(TraitDimension.transport, 'public_transit', 0.3, evidence: 'q:3'),
        _obs(TraitDimension.caregiverOf, 'elder', 0.6, evidence: 'q:4'),
        _obs(TraitDimension.caregiverOf, 'child', 0.6, evidence: 'q:5'),
      ], now: _now);
      expect(_confidence(traits, TraitDimension.transport, 'car_scooter'), closeTo(0.84 * 0.7, 1e-9));
      // 捷運 = 0.3 × (1 − 0.84) = 0.048，被兩個問題反駁後低於門檻，視為雜訊不回傳
      expect(traits.where((t) => t.value == 'public_transit'), isEmpty);
      expect(_confidence(traits, TraitDimension.caregiverOf, 'elder'), closeTo(0.6, 1e-9), reason: '可同時照顧長輩與小孩');
      expect(_confidence(traits, TraitDimension.caregiverOf, 'child'), closeTo(0.6, 1e-9));
    });

    test('source weights and time decay apply', () {
      final List<UserTrait> traits = TraitAggregator.aggregate([
        _obs(TraitDimension.interest, 'pets', 0.8, source: TraitSource.click),
        _obs(TraitDimension.interest, 'reading', 0.5, source: TraitSource.keyword),
        _obs(TraitDimension.interest, 'city_data', 0.8, age: TraitAggregator.halfLife),
      ], now: _now);
      expect(_confidence(traits, TraitDimension.interest, 'pets'), closeTo(0.72, 1e-9));
      expect(_confidence(traits, TraitDimension.interest, 'reading'), closeTo(0.3, 1e-9));
      expect(_confidence(traits, TraitDimension.interest, 'city_data'), closeTo(0.4, 1e-6), reason: '過了一個半衰期剩一半');
      expect(traits.first.value, 'pets', reason: '依可信度排序');
    });

    test('very weak traits are dropped', () {
      expect(TraitAggregator.aggregate([_obs(TraitDimension.interest, 'pets', 0.01)], now: _now), isEmpty);
    });
  });

  group('UserTraitRepository（SQLite）', () {
    late UserTraitRepository repository;
    setUp(() async => repository = await UserTraitRepository.open(databaseFactoryFfi, inMemoryDatabasePath, now: _now));
    tearDown(() => repository.close());

    test('stores observations and aggregates them', () async {
      await repository.add([
        _obs(TraitDimension.language, 'en', 0.9, evidence: 'q:1'),
        _obs(TraitDimension.language, 'en', 0.9, evidence: 'q:2'),
        _obs(TraitDimension.interest, 'reading', 0.5, source: TraitSource.keyword),
      ]);

      final List<TraitObservation> stored = await repository.observations();
      expect(stored, hasLength(3));
      expect(stored.first.source, TraitSource.llm);

      final List<UserTrait> confident =
          await repository.traits(now: _now, minConfidence: TraitAggregator.confidentThreshold);
      expect(confident.map((t) => '${t.dimension.name}=${t.value}'), ['language=en']);
      expect(confident.single.confidence, closeTo(0.99, 1e-9));
    });

    test('old observations are pruned when the database is opened', () async {
      final String path = '${DateTime.now().microsecondsSinceEpoch}_prune.db';
      final UserTraitRepository first = await UserTraitRepository.open(databaseFactoryFfi, path, now: _now);
      await first.add([
        _obs(TraitDimension.interest, 'pets', 0.9, age: const Duration(days: 400)),
        _obs(TraitDimension.interest, 'reading', 0.9, age: const Duration(days: 10)),
      ]);
      await first.close();

      final UserTraitRepository reopened = await UserTraitRepository.open(databaseFactoryFfi, path, now: _now);
      expect((await reopened.observations()).map((o) => o.value), ['reading']);
      await reopened.clear();
      expect(await reopened.observations(), isEmpty);
      await reopened.close();
      await databaseFactoryFfi.deleteDatabase(path);
    });
  });

  group('UserTraitRecorder', () {
    late UserTraitRepository repository;
    late UserTraitRecorder recorder;
    ServiceSearchEntry entry(String title) => ServiceSearch.catalog.firstWhere((e) => e.title == title);

    setUp(() async {
      repository = await UserTraitRepository.open(databaseFactoryFfi, inMemoryDatabasePath, now: _now);
      recorder = UserTraitRecorder(repository: () async => repository, clock: () => _now);
    });
    tearDown(() => repository.close());

    test('evidence key ignores case and punctuation and never stores the text', () {
      expect(UserTraitRecorder.evidenceKey('我想借書！'), UserTraitRecorder.evidenceKey('我想借書'));
      expect(UserTraitRecorder.evidenceKey('Where is the ZOO?'), UserTraitRecorder.evidenceKey('where is the zoo'));
      expect(UserTraitRecorder.evidenceKey('我想借書'), isNot(contains('借書')));
    });

    test('keyword matches and clicks map services to traits', () async {
      await recorder.recordKeywordMatch('圖書借閱', entry('圖書借閱'));
      await recorder.recordOpened('我想借書', entry('圖書借閱'));
      await recorder.recordOpened('繳停車費', entry('停車費'));

      final List<TraitObservation> stored = await repository.observations();
      expect(stored.map((o) => '${o.source.name}:${o.dimension.name}=${o.value}'), [
        'keyword:interest=reading',
        'click:interest=reading',
        'click:interest=bills_payment',
        'click:transport=car_scooter',
      ]);
      expect(stored.first.detail, '圖書借閱');
      expect(stored[0].evidenceKey, isNot(stored[1].evidenceKey), reason: '點擊是獨立佐證');
    });

    test('sensitive services never produce observations', () async {
      for (final String title in ['警政服務', '緊急求救', '聯醫掛號', '疫苗預約', '聯合醫院醫療費', '國/社宅租金維管費', '平價住宅維護費']) {
        expect(UserTraitRecorder.traitsOfService(title), isEmpty, reason: title);
        await recorder.recordOpened('x', entry(title));
      }
      final ServiceInventoryCorpus corpus = await ServiceInventoryCorpus.load();
      for (final String title in ['110 緊急報案', '165 反詐騙專線', '113 婦幼保護申訴專線', '網路報案', '案件查詢']) {
        await recorder.recordOpened('x', corpus.documents.firstWhere((d) => d.title == title).action);
      }
      expect(await repository.observations(), isEmpty);
    });

    test('wellness is dropped when the question talks about illness or seeing a doctor', () async {
      const List<InferredTrait> inferred = [
        InferredTrait(TraitDimension.interest, 'wellness', 0.8),
        InferredTrait(TraitDimension.language, 'zh', 0.9),
      ];
      await recorder.recordInferred('最近一直咳嗽發燒要去哪看醫生', inferred);
      await recorder.recordInferred('想看一些健康養生的資訊', inferred);

      final String sickKey = UserTraitRecorder.evidenceKey('最近一直咳嗽發燒要去哪看醫生');
      final List<String> stored = [
        for (final TraitObservation o in await repository.observations())
          '${o.evidenceKey == sickKey ? 'sick' : 'info'}:${o.value}',
      ];
      expect(stored, ['sick:zh', 'info:wellness', 'info:zh']);
      expect(UserTraitRecorder.mentionsMedical('I have a fever'), isTrue);
      expect(UserTraitRecorder.mentionsMedical('想看健康養生的資訊'), isFalse);
    });

    test('LLM traits are stored with their own confidence and model', () async {
      await recorder.recordInferred(
        'I am visiting Taipei, where can I see pandas',
        const [
          InferredTrait(TraitDimension.language, 'en', 0.95),
          InferredTrait(TraitDimension.relation, 'visitor', 0.9),
          InferredTrait(TraitDimension.interest, 'family_outings', 0.6),
        ],
        model: 'test-model',
      );
      final List<UserTrait> traits = await recorder.traits(minConfidence: TraitAggregator.confidentThreshold);
      expect(traits.map((t) => t.value), ['en', 'visitor', 'family_outings']);
      expect((await repository.observations()).first.model, 'test-model');
    });
  });

  group('GeminiServiceMatcher.parseTraits', () {
    test('keeps valid traits and drops unknown values, bad shapes and low confidence', () {
      final List<InferredTrait> traits = GeminiServiceMatcher.parseTraits({
        'language': {'value': 'en', 'confidence': 0.95},
        'relation': {'value': 'tourist', 'confidence': 0.9}, // 不在清單
        'transport': {'value': 'public_transit', 'confidence': 0.2}, // 太低
        'caregiverOf': [
          {'value': 'elder', 'confidence': 0.7},
          'child',
        ],
        'interests': [
          {'value': 'pets', 'confidence': 1.4},
          {'value': 'health', 'confidence': 0.9}, // 敏感類別本來就不在清單
        ],
      });
      expect(traits, const [
        InferredTrait(TraitDimension.language, 'en', 0.95),
        InferredTrait(TraitDimension.caregiverOf, 'elder', 0.7),
        InferredTrait(TraitDimension.interest, 'pets', 1.0),
      ]);
      expect(GeminiServiceMatcher.parseTraits(null), isEmpty);
      expect(GeminiServiceMatcher.parseTraits('oops'), isEmpty);
    });

    test('every allowed value has a Chinese label for the prompt', () {
      for (final TraitDimension dimension in TraitDimension.values) {
        for (final String value in dimension.allowedValues) {
          expect(TraitDimension.labels[value], isNotNull, reason: value);
        }
      }
      expect(TraitDimension.interest.allowedValues,
          containsAll(['sports', 'culture_events', 'environment', 'wellness', 'learning']));
    });

    test('allowed values contain no sensitive categories', () {
      final Set<String> all = {for (final d in TraitDimension.values) ...d.allowedValues};
      for (final String banned in ['health', 'disease', 'fraud', 'victim', 'crime', 'religion', 'politics', 'income', 'gender', 'age']) {
        expect(all.any((value) => value.contains(banned)), isFalse, reason: banned);
      }
    });
  });

  group('ServiceAssistantController records traits', () {
    late ServiceInventoryCorpus corpus;
    setUpAll(() async => corpus = await ServiceInventoryCorpus.load());

    test('keyword path records the top match', () async {
      final _SpyRecorder spy = _SpyRecorder();
      final ServiceAssistantController controller = ServiceAssistantController(
        rag: ServiceRag(corpus: corpus, generator: _TraitGenerator(const [])),
        traits: spy,
      );

      await controller.send('圖書借閱');
      await controller.lastTraitRecord;

      expect(spy.calls, ['keyword:圖書借閱:圖書借閱']);
      expect(controller.messages.last.query, '圖書借閱');
    });

    test('RAG path records LLM traits, and opening a result records a click', () async {
      final _SpyRecorder spy = _SpyRecorder();
      final ServiceAssistantController controller = ServiceAssistantController(
        rag: ServiceRag(
          corpus: corpus,
          generator: _TraitGenerator(const [InferredTrait(TraitDimension.relation, 'commuter', 0.8)]),
        ),
        traits: spy,
      );

      await controller.send('隔壁工地一大早就在施工好吵');
      await controller.lastTraitRecord;
      expect(spy.calls.single, 'inferred:隔壁工地一大早就在施工好吵:relation=commuter');

      final ChatMessage answer = controller.messages.last;
      controller.openResult(answer, ServiceSearchEntry(title: '圖書借閱', description: '', icon: const SizedBox(), keywords: const [], onOpen: () {}));
      await controller.lastTraitRecord;
      expect(spy.calls.last, 'opened:隔壁工地一大早就在施工好吵:圖書借閱');
    });
  });
}
