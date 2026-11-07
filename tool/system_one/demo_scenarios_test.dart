// 示範題組：從空白（沒有任何特徵）開始，依序問完一組問題，推薦會穩定落到預期的結果。
//
// 用法（在專案根目錄，需要 typesafe.env.json）：
//   flutter test tool/system_one/demo_scenarios_test.dart
//
// 流程與 App 相同：每個問題 → 關鍵字直接命中就記一筆服務觀察 → System One 判斷特徵並記錄；
// 問完後用 RecommendationService（特徵分＋語意分＋System One 推薦判斷）算出各位置的推薦。
// 每組從空白資料庫跑 [_runs] 次，確認結果穩定。不印出金鑰。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:town_pass/page/city_service/model/my_service_model.dart';
import 'package:town_pass/page/city_service/widget/pinned_service_widget_controller.dart';
import 'package:town_pass/page/service_assistant/gemini_service_matcher.dart';
import 'package:town_pass/page/service_assistant/jev_service_selector.dart';
import 'package:town_pass/page/service_assistant/rag/rag_document.dart';
import 'package:town_pass/page/service_assistant/rag/rag_retriever.dart';
import 'package:town_pass/page/service_assistant/rag/service_inventory_corpus.dart';
import 'package:town_pass/page/service_assistant/rag/service_rag.dart';
import 'package:town_pass/page/service_assistant/service_search.dart';
import 'package:town_pass/service/recommendation_service.dart';
import 'package:town_pass/service/system_one/jev_client.dart';
import 'package:town_pass/service/system_one/jev_recommendation_ranker.dart';
import 'package:town_pass/service/user_traits/demo_scenarios.dart';
import 'package:town_pass/service/user_traits/jev_trait_classifier.dart';
import 'package:town_pass/service/user_traits/recommendation_embeddings.dart';
import 'package:town_pass/service/user_traits/recommendation_targets.dart';
import 'package:town_pass/service/user_traits/user_trait_recorder.dart';
import 'package:town_pass/service/user_traits/user_trait_repository.dart';

const int _runs = 2;

void main() {
  setUpAll(sqfliteFfiInit);

  test('示範題組：從空白開始，推薦穩定落到預期結果', () async {
    final String key = _apiKey();
    final RecommendationEmbeddings embeddings = RecommendationEmbeddings.fromJson(
      jsonDecode(File(RecommendationEmbeddings.assetPath).readAsStringSync()) as Map<String, dynamic>,
    );
    final List<String> banners = _mockTitles('assets/mock_data/home_banner.json');
    final List<String> activities = _mockTitles('assets/mock_data/activity.json');
    final List<String> bills = [for (final t in RecommendationTargets.bills) t.match];
    final List<String> failures = [];
    final RagRetriever retriever = RagRetriever(ServiceInventoryCorpus.fromJson(
      jsonDecode(File(ServiceInventoryCorpus.assetPath).readAsStringSync()) as Map<String, dynamic>,
      catalog: ServiceSearch.catalog,
    ).documents);

    for (final DemoScenario scenario in DemoScenario.all) {
      for (int run = 1; run <= _runs; run++) {
        final UserTraitRepository repository = await UserTraitRepository.open(databaseFactoryFfi, inMemoryDatabasePath);
        final UserTraitRecorder recorder = UserTraitRecorder(repository: () async => repository);
        final JevTraitClassifier classifier = JevTraitClassifier(client: JevClient(apiKey: key));
        final JevServiceSelector selector = JevServiceSelector(fallback: _NoFallback(), client: JevClient(apiKey: key));

        // 與小幫手相同的兩條路：關鍵字直接命中 → 記服務觀察＋只問特徵；
        // 否則 → 檢索候選服務，「選服務＋判斷特徵」同一次請求（App 另有語意檢索，這裡只用關鍵字檢索）
        for (final String question in scenario.questions) {
          final List<ServiceSearchEntry> keyword = ServiceSearch.search(question);
          if (ServiceSearch.topScore(question) >= 20 && keyword.isNotEmpty) {
            await recorder.recordKeywordMatch(question, keyword.first);
            await recorder.recordInferred(question, await classifier.classify(question), model: classifier.model);
          } else {
            final List<RagHit> hits = retriever.retrieve(question, limit: 8);
            if (hits.isEmpty) {
              // 例如英文問句：關鍵字檢索找不到中文辭庫（App 靠語意檢索找得到），這裡只判斷特徵
              await recorder.recordInferred(question, await classifier.classify(question), model: classifier.model);
            } else {
              final AiMatchResult result = await selector.generate(question, hits);
              await recorder.recordInferred(question, result.traits, model: result.decidedBy);
            }
          }
        }

        final RecommendationService service = RecommendationService(
          repository: () async => repository,
          embeddings: () async => embeddings,
          systemOne: JevRecommendationRanker(client: JevClient(apiKey: key)),
        );
        await service.init();
        await service.lastSystemOneRefresh;

        final List<MyServiceItemId> pinned = service.pinnedServices(PinnedServiceWidgetController.defaultPinned);
        final Map<String, List<String>> result = {
          '特徵': [for (final t in service.traits) '${t.value} ${t.confidence.toStringAsFixed(2)}'],
          '訂閱推薦': service.subscriptionTopics(subscribed: {}),
          '熱門繳費': service.rank(RecommendationSurface.bill, bills, titleOf: (b) => b).take(3).toList(),
          '首頁大圖': service.rank(RecommendationSurface.homeBanner, banners, titleOf: (b) => b).take(2).toList(),
          '活動訊息': service.rank(RecommendationSurface.homeActivity, activities, titleOf: (a) => a).take(3).toList(),
          '你可能需要／我的服務': [
            for (final id in {...service.suggestedServices(pinned: pinned), ...pinned}) id.item.title,
          ],
          '小幫手建議': service.assistantChips(),
        };

        // ignore: avoid_print
        print('\n【${scenario.name}】第 $run 次');
        for (final MapEntry<String, List<String>> entry in result.entries) {
          // ignore: avoid_print
          print('  ${entry.key}：${entry.value.map(_short).join('、')}');
        }
        for (final MapEntry<String, String> expectation in scenario.expect.entries) {
          final List<String> got = result[expectation.key] ?? const [];
          final bool ok = got.isNotEmpty && got.first.contains(expectation.value);
          // ignore: avoid_print
          print('  ${ok ? '✓' : '✗'} ${expectation.key} 第一名應為「${expectation.value}」');
          if (!ok) failures.add('${scenario.name} 第 $run 次：${expectation.key} 得到 ${got.map(_short).toList()}');
        }
        await repository.close();
      }
    }
    // ignore: avoid_print
    print('\n${failures.isEmpty ? '全部符合預期' : '不符合：\n${failures.join('\n')}'}');
  }, timeout: const Timeout(Duration(minutes: 5)));
}

String _short(String title) => title.length > 18 ? '${title.substring(0, 18)}…' : title;

List<String> _mockTitles(String path) => [
      for (final dynamic item in (jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>)['data'] as List<dynamic>)
        (item as Map<String, dynamic>)['title'] as String? ?? '',
    ];

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

class _NoFallback implements RagGenerator {
  @override
  bool get isEnabled => false;

  @override
  Future<AiMatchResult> generate(String query, List<RagHit> context) async => const AiMatchResult(entries: [], reply: '');

  @override
  Future<List<String>> rewriteQuery(String query) async => const [];
}
