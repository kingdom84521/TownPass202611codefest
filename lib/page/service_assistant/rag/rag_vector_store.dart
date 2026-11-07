import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:town_pass/page/service_assistant/rag/rag_document.dart';

/// 辭庫的向量索引：開發時預先算好每份文件的向量（`assets/rag/service_inventory_embeddings.json`），
/// 執行時只需要把使用者的問句轉成向量，在記憶體內算 cosine 相似度。
///
/// 辭庫只有幾十筆，線性掃描就夠快，不需要額外的向量資料庫。
/// 向量檔用 `flutter test tool/rag/build_embeddings_test.dart` 產生。
class RagVectorStore {
  RagVectorStore._(this.model, this.dimensions, this._vectors, this._documents, this.staleIds);

  static const String assetPath = 'assets/rag/service_inventory_embeddings.json';

  /// 產生向量檔與轉換問句都要用同一個模型與維度，否則向量不能互相比較。
  static const String embeddingModel = 'gemini-embedding-2';
  static const int embeddingDimensions = 768;

  /// `gemini-embedding-2` 不支援 task_type，改用文字前綴指定任務（問句與文件的格式不同）。
  static String queryText(String query) => 'task: search result | query: $query';

  final String model;
  final int dimensions;
  final Map<String, Float32List> _vectors;
  final Map<String, RagDocument> _documents;

  /// 辭庫內容已改、向量檔卻沒重新產生的文件；這些文件只能靠 BM25 檢索。
  final List<String> staleIds;

  int get size => _vectors.length;
  bool get isEmpty => _vectors.isEmpty;

  /// 某份文件的向量（已正規化）；測試用來模擬「語意上很接近這份文件」的問句。
  @visibleForTesting
  List<double>? vectorOf(String id) => _vectors[id]?.toList();

  /// 讀取向量檔；檔案不存在或格式錯誤時回傳 null（小幫手退回只用 BM25）。
  static Future<RagVectorStore?> load({required List<RagDocument> documents, AssetBundle? bundle}) async {
    try {
      final String text = await (bundle ?? rootBundle).loadString(assetPath);
      return RagVectorStore.fromJson(jsonDecode(text) as Map<String, dynamic>, documents: documents);
    } catch (error) {
      debugPrint('[服務小幫手/RAG] 向量檔無法載入，只用 BM25：$error');
      return null;
    }
  }

  factory RagVectorStore.fromJson(Map<String, dynamic> json, {required List<RagDocument> documents}) {
    final Map<String, RagDocument> byId = {for (final document in documents) document.id: document};
    final int dimensions = json['dimensions'] as int;
    final Map<String, Float32List> vectors = {};
    final List<String> stale = [];
    for (final Map<String, dynamic> item in (json['documents'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      final String id = item['id'] as String;
      final RagDocument? document = byId[id];
      if (document == null || document.fingerprint != item['fingerprint']) {
        stale.add(id);
        continue;
      }
      final List<dynamic> values = item['vector'] as List<dynamic>;
      if (values.length != dimensions) {
        stale.add(id);
        continue;
      }
      vectors[id] = _normalize(Float32List.fromList([for (final value in values) (value as num).toDouble()]));
    }
    // 辭庫有、向量檔沒有的文件也算過期
    stale.addAll(byId.keys.where((id) => !vectors.containsKey(id) && !stale.contains(id)));
    return RagVectorStore._(json['model'] as String, dimensions, vectors, byId, List.unmodifiable(stale));
  }

  /// 以 cosine 相似度由高到低回傳最多 [limit] 筆。
  List<RagHit> search(List<double> query, {int limit = 8}) {
    if (query.length != dimensions || _vectors.isEmpty) return const [];
    final Float32List normalizedQuery = _normalize(Float32List.fromList(query));
    final List<RagHit> hits = [
      for (final MapEntry<String, Float32List> entry in _vectors.entries)
        () {
          final double cosine = _dot(normalizedQuery, entry.value);
          return RagHit(_documents[entry.key]!, cosine, cosine: cosine);
        }(),
    ]..sort((a, b) => b.score.compareTo(a.score));
    return hits.take(limit).toList();
  }

  static double _dot(Float32List a, Float32List b) {
    double sum = 0;
    for (int i = 0; i < a.length; i++) {
      sum += a[i] * b[i];
    }
    return sum;
  }

  static Float32List _normalize(Float32List vector) {
    double sum = 0;
    for (final double value in vector) {
      sum += value * value;
    }
    final double norm = math.sqrt(sum);
    if (norm == 0) return vector;
    for (int i = 0; i < vector.length; i++) {
      vector[i] = vector[i] / norm;
    }
    return vector;
  }
}
