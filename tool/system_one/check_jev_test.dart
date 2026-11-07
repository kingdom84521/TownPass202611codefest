// 驗證 System One（Jev）金鑰並試問一題：不印出金鑰。
//
// 用法（在專案根目錄）：
//   flutter test tool/system_one/check_jev_test.dart
//
// 金鑰依序取自環境變數 TYPESAFE_API_KEY、專案根目錄的 typesafe.env.json。
// 放在 tool/ 而不是 test/：一般的 `flutter test` 不會打外部 API。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:town_pass/service/system_one/jev_client.dart';
import 'package:town_pass/service/user_traits/jev_trait_classifier.dart';

void main() {
  test('Jev 金鑰可用，且能判斷特徵', () async {
    final String key = _apiKey();
    final http.Response models = await http.get(
      Uri.parse('https://api.typesafe.ai/v1/models'),
      headers: {'Authorization': 'Bearer $key'},
    );
    // ignore: avoid_print
    print('GET /v1/models → HTTP ${models.statusCode}');
    expect(models.statusCode, 200, reason: '金鑰無效或無法連線（401＝金鑰錯誤）');

    final JevTraitClassifier classifier = JevTraitClassifier(client: JevClient(apiKey: key));
    for (final String query in ['我想幫小孩繳學費', '附近哪裡好停車', 'Where can I see pandas?', '咳嗽發燒要去哪看醫生']) {
      // ignore: avoid_print
      print('「$query」→ ${await classifier.classify(query)}');
    }
  }, timeout: const Timeout(Duration(minutes: 1)));
}

String _apiKey() {
  final String? fromEnv = Platform.environment['TYPESAFE_API_KEY'];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  final File file = File('typesafe.env.json');
  if (file.existsSync()) {
    final String? key = (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>)['TYPESAFE_API_KEY'] as String?;
    if (key != null && key.isNotEmpty && !key.contains('貼在這')) return key;
  }
  fail('找不到 TypeSafe 金鑰：請把金鑰貼進 typesafe.env.json');
}
