import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
