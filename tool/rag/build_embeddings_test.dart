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
}

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
