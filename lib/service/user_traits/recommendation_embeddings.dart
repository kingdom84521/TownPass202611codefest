import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:town_pass/service/user_traits/recommendation_targets.dart';
import 'package:town_pass/service/user_traits/trait_aggregator.dart';
import 'package:town_pass/service/user_traits/user_trait.dart';

/// 推薦用的語意相似度：使用者實際問到、點開的服務，和各推薦項目在向量空間有多接近。
///
/// 特徵只記得「這個人開車」，相似度補上「他關心的是停車費」：
/// 問過停車費的人，「停車費通知」會比「交通措施」更前面。
///
/// - 向量預先算好（`assets/rag/recommendation_embeddings.json`，與小幫手辭庫同一個模型），
///   App 執行時不呼叫 API，也不需要保存問句原文。
/// - 用 `flutter test tool/rag/build_embeddings_test.dart` 產生。
class RecommendationEmbeddings {
  RecommendationEmbeddings(this._targets, this._services, {Map<String, String> texts = const {}}) : _texts = texts;

  /// 每個推薦項目的說明文字（活動、大圖為完整標題；其他為「訂閱主題：…」等），key 見 [targetKey]。
  /// System One 判斷推薦時拿來出題。
  final Map<String, String> _texts;

  String? textOf(RecommendationTarget target) => _texts[targetKey(target.surface, target.match)];

  static const String assetPath = 'assets/rag/recommendation_embeddings.json';

  /// 某服務對同一位置所有項目的相似度，高出平均多少才算相關；高出 [margin] 以上算完全相關。
  /// gemini-embedding-2 的 cosine 多半集中在 0.6–0.8，只看絕對值分不出差別，所以看「比平均高多少」。
  static const double margin = 0.1;

  /// 相關程度低於這個值當作雜訊，不加分（否則每個項目都會沾到一點分數，被當成推薦）。
  static const double minRelevance = 0.3;

  final Map<String, Float32List> _targets;
  final Map<String, Float32List> _services;

  static String targetKey(RecommendationSurface surface, String match) => '${surface.name}|$match';

  bool hasTarget(RecommendationTarget target) => _targets.containsKey(targetKey(target.surface, target.match));
  bool hasService(String title) => _services.containsKey(title);

  /// 讀取向量檔；不存在或格式錯誤時回傳 null（推薦只看特徵）。
  static Future<RecommendationEmbeddings?> load({AssetBundle? bundle}) async {
    try {
      final String text = await (bundle ?? rootBundle).loadString(assetPath);
      return RecommendationEmbeddings.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } catch (error) {
      debugPrint('[推薦] 相似度向量無法載入，只用特徵：$error');
      return null;
    }
  }

  factory RecommendationEmbeddings.fromJson(Map<String, dynamic> json) {
    Float32List vector(Map<String, dynamic> item) =>
        _normalize(Float32List.fromList([for (final dynamic value in item['vector'] as List<dynamic>) (value as num).toDouble()]));
    final Map<String, Float32List> targets = {};
    final Map<String, String> texts = {};
    for (final Map<String, dynamic> item in (json['targets'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      final RecommendationSurface? surface =
          RecommendationSurface.values.where((s) => s.name == item['surface']).firstOrNull;
      if (surface == null) continue;
      final String key = targetKey(surface, item['match'] as String);
      targets[key] = vector(item);
      if (item['text'] case final String text) texts[key] = text;
    }
    final Map<String, Float32List> services = {
      for (final Map<String, dynamic> item in (json['services'] as List<dynamic>).cast<Map<String, dynamic>>())
        item['title'] as String: vector(item),
    };
    return RecommendationEmbeddings(targets, services, texts: texts);
  }

  /// 每個推薦項目的語意加分：Σ 服務興趣 × 相關程度（0–1）。刻意不推薦的項目（醫療、報案等）一律 0。
  /// 回傳的 key 是 [targetKey]。
  Map<String, double> bonuses(Map<String, double> serviceInterests) {
    final Map<String, double> result = {};
    for (final RecommendationSurface surface in RecommendationSurface.values) {
      final List<(RecommendationTarget, Float32List)> targets = [
        for (final RecommendationTarget target in RecommendationTargets.of(surface))
          if (_targets[targetKey(surface, target.match)] case final Float32List vector) (target, vector),
      ];
      if (targets.length < 2) continue;
      for (final MapEntry<String, double> interest in serviceInterests.entries) {
        final Float32List? service = _services[interest.key];
        if (service == null) continue;
        final List<double> similarities = [for (final (_, Float32List vector) in targets) _dot(service, vector)];
        final double mean = similarities.reduce((a, b) => a + b) / similarities.length;
        for (int i = 0; i < targets.length; i++) {
          final RecommendationTarget target = targets[i].$1;
          if (target.excludedReason != null) continue;
          final double relevance = ((similarities[i] - mean) / margin).clamp(0.0, 1.0);
          if (relevance < minRelevance) continue;
          final String key = targetKey(surface, target.match);
          result[key] = (result[key] ?? 0) + interest.value * relevance;
        }
      }
    }
    return result;
  }

  static double _dot(Float32List a, Float32List b) {
    double sum = 0;
    for (int i = 0; i < a.length && i < b.length; i++) {
      sum += a[i] * b[i];
    }
    return sum;
  }

  static Float32List _normalize(Float32List vector) {
    double norm = 0;
    for (final double value in vector) {
      norm += value * value;
    }
    norm = math.sqrt(norm);
    if (norm == 0) return vector;
    return Float32List.fromList([for (final double value in vector) value / norm]);
  }
}

/// 使用者關心哪些服務：關鍵字直接命中、點開過的服務（觀察的 detail），
/// 用與特徵相同的方式綜合（來源權重、時間衰減、不同問題互相佐證），只回傳 ≥ [TraitAggregator.confidentThreshold] 的。
/// 對照表本來就不收敏感服務，所以這裡也不會出現。
Map<String, double> serviceInterestsOf(Iterable<TraitObservation> observations, {required DateTime now}) {
  final Map<String, Map<String, double>> byService = {};
  for (final TraitObservation observation in observations) {
    final String? title = observation.detail;
    // 只看服務：LLM 推論沒有對應服務，設定類（例如翻譯語言）也不是服務
    if (title == null ||
        observation.source == TraitSource.llm ||
        observation.source.negative ||
        observation.evidenceKey.startsWith('setting:')) {
      continue;
    }
    final double ageDays = math.max(0, now.difference(observation.observedAt).inMinutes / (60 * 24));
    final double weight = observation.confidence *
        observation.source.weight *
        math.pow(0.5, ageDays / TraitAggregator.halfLife.inDays).toDouble();
    final Map<String, double> byEvidence = byService.putIfAbsent(title, () => {});
    byEvidence[observation.evidenceKey] = math.max(byEvidence[observation.evidenceKey] ?? 0, weight);
  }
  return {
    for (final MapEntry<String, Map<String, double>> entry in byService.entries)
      if (1 - entry.value.values.fold<double>(1, (product, w) => product * (1 - w)) case final double support
          when support >= TraitAggregator.confidentThreshold)
        entry.key: support,
  };
}
