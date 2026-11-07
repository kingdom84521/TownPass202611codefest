import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:town_pass/page/service_assistant/gemini_service_matcher.dart';
import 'package:town_pass/page/service_assistant/jev_service_selector.dart';
import 'package:town_pass/page/service_assistant/rag/rag_document.dart';
import 'package:town_pass/page/service_assistant/rag/service_inventory_corpus.dart';
import 'package:town_pass/page/service_assistant/rag/service_rag.dart';
import 'package:town_pass/page/service_assistant/service_search.dart';
import 'package:town_pass/service/system_one/jev_client.dart';
import 'package:town_pass/service/user_traits/jev_trait_classifier.dart';
import 'package:town_pass/service/user_traits/user_trait.dart';

Map<String, dynamic> _choice(String choice, double p) => {
      'type': 'choice',
      'choice': choice,
      'confidence': p,
      'probabilities': {choice: p},
    };

Map<String, dynamic> _yes(double p) => {'type': 'noul', 'noul': p};

void main() {
  serviceSelectorTests();
  relativeCutoffTests();

  group('JevClient', () {
    test('送出 Bearer 金鑰、固定版本與題目；解析答案', () async {
      late http.Request sent;
      final JevClient client = JevClient(
        apiKey: 'test-key',
        client: MockClient((request) async {
          sent = request;
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'model': 'jev-1.14.0',
              'answers': {'lang': _choice('zh', 0.97), 'kid': _yes(0.81)},
              'usage': {'input_tokens': 40, 'output_tokens': 4},
            })),
            200,
          );
        }),
      );
      final JevAnswers answers = await client.decide(
        state: '繳學費',
        questions: {'lang': const JevChoice('語言？', {'zh': '中文'}), 'kid': const JevYesNo('照顧小孩？')},
      );
      expect(sent.url, JevClient.endpoint);
      expect(sent.headers['Authorization'], 'Bearer test-key');
      final Map<String, dynamic> body = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(body['model'], JevClient.defaultModel);
      expect(body['state'], '繳學費');
      expect((body['questions'] as Map)['kid'], {'type': 'noul', 'instructions': '照顧小孩？'});
      expect(answers.choice('lang'), ('zh', 0.97));
      expect(answers.yes('kid'), 0.81);
    });

    test('沒有金鑰或還是範本文字時不啟用；HTTP 錯誤丟出 JevException', () async {
      expect(JevClient(apiKey: '').isEnabled, isFalse);
      expect(JevClient(apiKey: '把金鑰貼在這對引號中間，取代這段文字').isEnabled, isFalse);
      final JevClient client = JevClient(apiKey: 'bad', client: MockClient((_) async => http.Response('{"detail":"x"}', 401)));
      expect(client.decide(state: 'x', questions: {'q': const JevYesNo('?')}), throwsA(isA<JevException>()));
    });
  });

  group('JevTraitClassifier', () {
    test('題目涵蓋所有非敏感特徵，不出敏感題', () {
      final Iterable<String> keys = JevTraitClassifier.questions.keys;
      expect(keys, containsAll(['language', 'relation', 'transport', 'caregiver_child', 'caregiver_elder', 'medical']));
      for (final String value in TraitDimension.interest.allowedValues) {
        expect(keys, contains('interest_$value'));
      }
      expect(keys.length, 5 + TraitDimension.interest.allowedValues.length + 1);
    });

    test('機率就是可信度；看不出來、機率太低的不記', () {
      final List<InferredTrait> traits = JevTraitClassifier.parse(JevAnswers(model: 'jev-1.14.0', answers: {
        'language': _choice('zh', 0.98),
        'relation': _choice('unknown', 0.7),
        'transport': _choice('car_scooter', 0.42),
        'caregiver_child': _yes(0.86),
        'caregiver_elder': _yes(0.1),
        'interest_bills_payment': _yes(0.93),
        'interest_reading': _yes(0.2),
        'medical': _yes(0.03),
      }));
      expect(traits, [
        const InferredTrait(TraitDimension.language, 'zh', 0.98),
        const InferredTrait(TraitDimension.caregiverOf, 'child', 0.86),
        const InferredTrait(TraitDimension.interest, 'bills_payment', 0.93),
      ]);
    });

    test('提到病況或就醫時不記 wellness', () {
      List<InferredTrait> run(double medical) => JevTraitClassifier.parse(JevAnswers(model: 'm', answers: {
            'interest_wellness': _yes(0.9),
            'medical': _yes(medical),
          }));
      expect(run(0.95), isEmpty);
      expect(run(0.05), [const InferredTrait(TraitDimension.interest, 'wellness', 0.9)]);
    });
  });
}

class _FakeGemini implements RagGenerator {
  int generated = 0;

  @override
  bool get isEnabled => true;

  @override
  Future<AiMatchResult> generate(String query, List<RagHit> context) async {
    generated++;
    return const AiMatchResult(entries: [], reply: 'gemini');
  }

  @override
  Future<List<String>> rewriteQuery(String query) async => const ['改寫'];
}

void serviceSelectorTests() {
  group('JevServiceSelector（小幫手選服務）', () {
    late List<RagHit> hits;

    setUpAll(() async {
      final ServiceInventoryCorpus corpus = ServiceInventoryCorpus.fromJson(
        jsonDecode(File(ServiceInventoryCorpus.assetPath).readAsStringSync()) as Map<String, dynamic>,
        catalog: ServiceSearch.catalog,
      );
      RagHit hit(String title) => RagHit(corpus.documents.firstWhere((d) => d.title == title), 1);
      hits = [hit('災情通報'), hit('用水服務'), hit('有話要說'), hit('意見回饋')];
    });

    JevServiceSelector selector(Map<String, dynamic> answers, {int status = 200, _FakeGemini? fallback}) =>
        JevServiceSelector(
          fallback: fallback ?? _FakeGemini(),
          client: JevClient(
            apiKey: 'k',
            client: MockClient((_) async => http.Response.bytes(
                  utf8.encode(jsonEncode({'model': 'jev-1.14.0', 'answers': answers, 'usage': {}})),
                  status,
                )),
          ),
        );

    test('依機率挑出服務（≥ 0.4，最多 3 個，由高到低），特徵同一次請求一起回來', () async {
      final AiMatchResult result = await selector({
        'service_0': _yes(0.6),
        'service_1': _yes(0.1),
        'service_2': _yes(0.8),
        'service_3': _yes(0.39),
        'language': _choice('zh', 0.99),
        'medical': _yes(0.0),
      }).generate('颱風天家裡淹水', hits);
      expect(result.documents.map((d) => d.title), ['有話要說', '災情通報']);
      expect(result.reply, '推薦你使用「有話要說」、「災情通報」，點一下就能開始：');
      expect(result.traits, [const InferredTrait(TraitDimension.language, 'zh', 0.99)]);
      expect(result.decidedBy, 'jev:jev-1.14.0');
    });

    test('都不夠相關時不選、回覆留空（小幫手會顯示找不到或相關結果）', () async {
      final AiMatchResult result = await selector({'service_0': _yes(0.2)}).generate('?', hits);
      expect(result.entries, isEmpty);
      expect(result.reply, isEmpty);
    });

    test('Jev 失敗時退回 Gemini；改寫問句一律交給 Gemini', () async {
      final _FakeGemini gemini = _FakeGemini();
      final JevServiceSelector failing = selector({}, status: 500, fallback: gemini);
      final AiMatchResult result = await failing.generate('q', hits);
      expect(result.reply, 'gemini');
      expect(gemini.generated, 1);
      expect(await failing.rewriteQuery('q'), ['改寫']);
    });
  });
}

void relativeCutoffTests() {
  test('第二名以後要 ≥ 第一名的 0.7 倍才列出（路燈：有話要說、意見回饋要，災情通報不要）', () {
    final ServiceInventoryCorpus corpus = ServiceInventoryCorpus.fromJson(
      jsonDecode(File(ServiceInventoryCorpus.assetPath).readAsStringSync()) as Map<String, dynamic>,
      catalog: ServiceSearch.catalog,
    );
    RagHit hit(String title) => RagHit(corpus.documents.firstWhere((d) => d.title == title), 1);
    final List<RagHit> hits = [hit('有話要說'), hit('意見回饋'), hit('災情通報')];
    final List<RagDocument> picked = JevServiceSelector.pick(
      JevAnswers(model: 'm', answers: {'service_0': _yes(0.75), 'service_1': _yes(0.56), 'service_2': _yes(0.44)}),
      hits,
    );
    expect(picked.map((d) => d.title), ['有話要說', '意見回饋']);
  });
}
