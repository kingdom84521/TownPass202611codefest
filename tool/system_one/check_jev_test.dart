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
import 'package:town_pass/page/service_assistant/gemini_service_matcher.dart';
import 'package:town_pass/page/service_assistant/jev_service_selector.dart';
import 'package:town_pass/page/service_assistant/rag/rag_document.dart';
import 'package:town_pass/page/service_assistant/rag/rag_retriever.dart';
import 'package:town_pass/page/service_assistant/rag/service_inventory_corpus.dart';
import 'package:town_pass/page/service_assistant/rag/service_rag.dart';
import 'package:town_pass/page/service_assistant/service_search.dart';
import 'package:town_pass/service/system_one/jev_client.dart';
import 'package:town_pass/service/system_one/jev_recommendation_ranker.dart';
import 'package:town_pass/service/user_traits/jev_trait_classifier.dart';
import 'package:town_pass/service/user_traits/recommendation_embeddings.dart';
import 'package:town_pass/service/user_traits/user_trait.dart';

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

  test('Jev 從檢索結果挑出使用者要的服務', () async {
    final ServiceInventoryCorpus corpus = ServiceInventoryCorpus.fromJson(
      jsonDecode(File(ServiceInventoryCorpus.assetPath).readAsStringSync()) as Map<String, dynamic>,
      catalog: ServiceSearch.catalog,
    );
    final RagRetriever retriever = RagRetriever(corpus.documents);
    final JevServiceSelector selector =
        JevServiceSelector(fallback: _NoFallback(), client: JevClient(apiKey: _apiKey()));
    for (final String query in [
      '我想借書',
      '路燈壞了要找誰',
      '颱風天家裡淹水',
      '接到可疑電話說我中獎',
      '想帶小孩去放電',
      '停車場阿伯沒有穿內褲怎麼半',
    ]) {
      final List<RagHit> hits = retriever.retrieve(query, limit: 8);
      final AiMatchResult result = await selector.generate(query, hits);
      // ignore: avoid_print
      print('「$query」候選 ${hits.length} 筆 → ${result.documents.map((d) => d.title).toList()}｜${result.reply}');
    }
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('Jev 依使用者側寫判斷推薦（問過停車費的人）', () async {
    final RecommendationEmbeddings texts = RecommendationEmbeddings.fromJson(
      jsonDecode(File(RecommendationEmbeddings.assetPath).readAsStringSync()) as Map<String, dynamic>,
    );
    UserTrait t(TraitDimension d, String v, double c) =>
        UserTrait(dimension: d, value: v, confidence: c, evidenceCount: 1, lastObservedAt: DateTime.now());
    final Map<String, double> scores = await JevRecommendationRanker(client: JevClient(apiKey: _apiKey())).rank(
      UserProfile(
        traits: [
          t(TraitDimension.language, 'zh', 1.0),
          t(TraitDimension.transport, 'car_scooter', 0.95),
          t(TraitDimension.interest, 'bills_payment', 0.97),
          t(TraitDimension.interest, 'reading', 0.97),
        ],
        recentItems: const ['停車費'],
      ),
      texts: texts,
    );
    final List<MapEntry<String, double>> sorted = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    for (final MapEntry<String, double> e in sorted.take(14)) {
      // ignore: avoid_print
      print('RANK ${e.key} ${e.value.toStringAsFixed(2)}');
    }
    // ignore: avoid_print
    print('PARK 停車費通知=${scores['subscriptionTopic|停車費通知']} 交通措施=${scores['subscriptionTopic|交通措施']}');
  }, timeout: const Timeout(Duration(minutes: 1)));
}

class _NoFallback implements RagGenerator {
  @override
  bool get isEnabled => false;

  @override
  Future<AiMatchResult> generate(String query, List<RagHit> context) async =>
      const AiMatchResult(entries: [], reply: '（Jev 失敗，退回 fallback）');

  @override
  Future<List<String>> rewriteQuery(String query) async => const [];
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
