// 產生服務小幫手辭庫的向量檔：assets/rag/service_inventory_embeddings.json
//
// 用法（在專案根目錄）：
//   flutter test tool/rag/build_embeddings_test.dart
//
// 金鑰依序取自環境變數 GEMINI_API_KEY、專案根目錄的 gemini.env.json（不會印出金鑰）。
// 何時要重跑：assets/rag/service_inventory.json 或辭庫建構規則（ServiceInventoryCorpus、
// RagDocument.embeddingText）改了之後。沒重跑的話，App 會依指紋略過過期的向量，只用 BM25 檢索那些文件。
//
// 放在 tool/ 而不是 test/：一般的 `flutter test` 不會跑它，也就不會在 CI 打外部 API。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:town_pass/page/service_assistant/rag/rag_document.dart';
import 'package:town_pass/page/service_assistant/rag/rag_vector_store.dart';
import 'package:town_pass/page/service_assistant/rag/service_inventory_corpus.dart';
import 'package:town_pass/page/service_assistant/service_search.dart';
import 'package:town_pass/service/user_traits/recommendation_embeddings.dart';
import 'package:town_pass/service/user_traits/recommendation_targets.dart';
import 'package:town_pass/service/user_traits/user_trait_recorder.dart';

/// batchEmbedContents 一次最多送幾筆。
const int _batchSize = 50;

void main() {
  test('build RAG embeddings', () async {
    final String apiKey = _apiKey();
    final Map<String, dynamic> inventory =
        jsonDecode(File(ServiceInventoryCorpus.assetPath).readAsStringSync()) as Map<String, dynamic>;
    final ServiceInventoryCorpus corpus = ServiceInventoryCorpus.fromJson(inventory, catalog: ServiceSearch.catalog);
    final List<RagDocument> documents = corpus.documents;

    final List<List<double>> vectors = [];
    for (int start = 0; start < documents.length; start += _batchSize) {
      final List<RagDocument> batch = documents.sublist(start, (start + _batchSize).clamp(0, documents.length));
      vectors.addAll(await _embed(apiKey, batch.map((d) => d.embeddingText).toList()));
    }
    expect(vectors, hasLength(documents.length));

    final Map<String, Object> output = {
      'model': RagVectorStore.embeddingModel,
      'dimensions': RagVectorStore.embeddingDimensions,
      'documentFormat': 'title: {title} | text: {body}；相關說法：{keywords}',
      'queryFormat': RagVectorStore.queryText('{query}'),
      'inventorySourceCommit': corpus.sourceCommit,
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'documents': [
        for (int i = 0; i < documents.length; i++)
          {
            'id': documents[i].id,
            'title': documents[i].title,
            'fingerprint': documents[i].fingerprint,
            // 6 位小數足夠排序用，檔案約小一半
            'vector': [for (final double value in vectors[i]) double.parse(value.toStringAsFixed(6))],
          },
      ],
    };
    // 不縮排：縮排會讓每個數字各佔一行，檔案大約變成 1.6 倍
    File(RagVectorStore.assetPath).writeAsStringSync('${jsonEncode(output)}\n');
    // ignore: avoid_print
    print('已寫入 ${RagVectorStore.assetPath}：${documents.length} 筆，'
        '${RagVectorStore.embeddingModel}／${RagVectorStore.embeddingDimensions} 維，清冊基準 ${corpus.sourceCommit}');
  }, timeout: const Timeout(Duration(minutes: 2)));

  // 推薦用：各推薦項目的向量，以及「使用者關心的服務」的向量（從上面的辭庫向量複製，同一個模型）。
  // 何時要重跑：recommendation_targets.dart 的項目、UserTraitRecorder 的服務對照表、或上面的辭庫改了之後。
  test('build recommendation embeddings', () async {
    final String apiKey = _apiKey();
    final List<String> bannerTitles = _mockTitles('assets/mock_data/home_banner.json');
    final List<String> activityTitles = _mockTitles('assets/mock_data/activity.json');

    final List<RecommendationTarget> targets = [
      for (final RecommendationSurface surface in RecommendationSurface.values) ...RecommendationTargets.of(surface),
    ];
    String textOf(RecommendationTarget target) => switch (target.surface) {
          // 活動與大圖只存標題片段，用完整標題算向量比較準
          RecommendationSurface.homeBanner =>
            bannerTitles.firstWhere((title) => title.contains(target.match), orElse: () => target.match),
          RecommendationSurface.homeActivity =>
            activityTitles.firstWhere((title) => title.contains(target.match), orElse: () => target.match),
          RecommendationSurface.subscriptionTopic => '訂閱主題：${target.match}',
          RecommendationSurface.service => '服務：${target.match}',
          RecommendationSurface.bill => '繳費項目：${target.match}',
          RecommendationSurface.assistantChip => '想問：${target.match}',
        };
    final List<String> texts = [for (final target in targets) textOf(target)];
    final List<List<double>> vectors = [];
    for (int start = 0; start < targets.length; start += _batchSize) {
      final int end = (start + _batchSize).clamp(0, targets.length);
      vectors.addAll(await _embed(apiKey, [
        for (int i = start; i < end; i++) 'title: ${targets[i].match} | text: ${texts[i]}',
      ]));
    }

    final Map<String, dynamic> corpusVectors =
        jsonDecode(File(RagVectorStore.assetPath).readAsStringSync()) as Map<String, dynamic>;
    final Map<String, List<dynamic>> byTitle = {
      for (final Map<String, dynamic> document in (corpusVectors['documents'] as List<dynamic>).cast<Map<String, dynamic>>())
        document['title'] as String: document['vector'] as List<dynamic>,
    };
    final List<String> services = UserTraitRecorder.serviceTitles.where(byTitle.containsKey).toList();
    expect(services, hasLength(UserTraitRecorder.serviceTitles.length), reason: '服務對照表裡每個服務都要在辭庫找得到');

    File(RecommendationEmbeddings.assetPath).writeAsStringSync('${jsonEncode({
          'model': RagVectorStore.embeddingModel,
          'dimensions': RagVectorStore.embeddingDimensions,
          'targetFormat': 'title: {match} | text: {完整標題或「訂閱主題：」等前綴}',
          'generatedAt': DateTime.now().toUtc().toIso8601String(),
          'targets': [
            for (int i = 0; i < targets.length; i++)
              {
                'surface': targets[i].surface.name,
                'match': targets[i].match,
                'text': texts[i],
                'vector': [for (final double value in vectors[i]) double.parse(value.toStringAsFixed(6))],
              },
          ],
          'services': [
            for (final String title in services) {'title': title, 'vector': byTitle[title]},
          ],
        })}\n');
    // ignore: avoid_print
    print('已寫入 ${RecommendationEmbeddings.assetPath}：${targets.length} 個推薦項目、${services.length} 個服務');
  }, timeout: const Timeout(Duration(minutes: 2)));
}

List<String> _mockTitles(String path) => [
      for (final dynamic item in (jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>)['data'] as List<dynamic>)
        (item as Map<String, dynamic>)['title'] as String? ?? '',
    ];

Future<List<List<double>>> _embed(String apiKey, List<String> texts) async {
  final Uri uri = Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models/${RagVectorStore.embeddingModel}:batchEmbedContents',
  );
  final http.Response response = await http.post(
    uri,
    headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
    body: jsonEncode({
      'requests': [
        for (final String text in texts)
          {
            'model': 'models/${RagVectorStore.embeddingModel}',
            'content': {
              'parts': [
                {'text': text},
              ],
            },
            'output_dimensionality': RagVectorStore.embeddingDimensions,
          },
      ],
    }),
  );
  final String body = utf8.decode(response.bodyBytes);
  if (response.statusCode != 200) {
    fail('Embedding API HTTP ${response.statusCode}: ${body.length > 300 ? body.substring(0, 300) : body}');
  }
  final List<dynamic> embeddings = (jsonDecode(body) as Map<String, dynamic>)['embeddings'] as List<dynamic>;
  return [
    for (final dynamic embedding in embeddings)
      [for (final dynamic value in (embedding as Map<String, dynamic>)['values'] as List<dynamic>) (value as num).toDouble()],
  ];
}

String _apiKey() {
  final String? fromEnv = Platform.environment['GEMINI_API_KEY'];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  final File envFile = File('gemini.env.json');
  if (envFile.existsSync()) {
    final String? key = (jsonDecode(envFile.readAsStringSync()) as Map<String, dynamic>)['GEMINI_API_KEY'] as String?;
    if (key != null && key.isNotEmpty) return key;
  }
  fail('找不到 Gemini 金鑰：請設定環境變數 GEMINI_API_KEY 或建立 gemini.env.json');
}
