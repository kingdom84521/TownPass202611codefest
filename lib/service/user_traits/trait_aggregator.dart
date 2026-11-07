import 'dart:math' as math;

import 'package:town_pass/service/user_traits/user_trait.dart';

/// 把多筆觀察綜合成每個特徵的可信度。
///
/// 1. **單筆權重** w = 觀察可信度 × 來源權重（[TraitSource.weight]）× 時間衰減（半衰期 [halfLife]）。
/// 2. **同一個證據只算一次**：同一個問題（[TraitObservation.evidenceKey] 相同）對同一特徵的多筆觀察取最大值，
///    重複問同一句話不會灌高可信度。
/// 3. **多個問題互相佐證**（noisy-OR）：支持度 = 1 − Π(1 − wᵢ)。
///    例：兩個不同問題各 0.6 → 0.84；三個 → 0.94。單一問題再確定也只到它自己的 w。
/// 4. **互斥維度扣掉矛盾**（語言、與台北的關係、交通方式）：
///    可信度 = 自己的支持度 × Π(1 − 其他值的支持度)。
///    例：交通「開車」0.84、「捷運」0.3 → 開車 0.59、捷運 0.05。
///
/// 可信度達到 [confidentThreshold] 才建議拿去做推薦。
abstract final class TraitAggregator {
  static const Duration halfLife = Duration(days: 90);
  static const double confidentThreshold = 0.6;

  /// 低於此值的特徵不回傳，避免雜訊。
  static const double minConfidence = 0.05;

  static List<UserTrait> aggregate(Iterable<TraitObservation> observations, {required DateTime now}) {
    // (維度, 值) → (證據 → 最大權重)
    final Map<(TraitDimension, String), Map<String, double>> weights = {};
    final Map<(TraitDimension, String), DateTime> lastSeen = {};
    for (final TraitObservation observation in observations) {
      final (TraitDimension, String) key = (observation.dimension, observation.value);
      final double weight = observation.confidence * observation.source.weight * _decay(observation.observedAt, now);
      final Map<String, double> byEvidence = weights.putIfAbsent(key, () => {});
      byEvidence[observation.evidenceKey] = math.max(byEvidence[observation.evidenceKey] ?? 0, weight);
      final DateTime? seen = lastSeen[key];
      if (seen == null || observation.observedAt.isAfter(seen)) lastSeen[key] = observation.observedAt;
    }

    final Map<(TraitDimension, String), double> support = {
      for (final MapEntry<(TraitDimension, String), Map<String, double>> entry in weights.entries)
        entry.key: 1 - entry.value.values.fold<double>(1, (product, w) => product * (1 - w)),
    };

    final List<UserTrait> traits = [];
    for (final MapEntry<(TraitDimension, String), double> entry in support.entries) {
      final (TraitDimension dimension, String value) = entry.key;
      double confidence = entry.value;
      if (dimension.exclusive) {
        for (final MapEntry<(TraitDimension, String), double> other in support.entries) {
          if (other.key.$1 == dimension && other.key.$2 != value) confidence *= 1 - other.value;
        }
      }
      if (confidence < minConfidence) continue;
      traits.add(UserTrait(
        dimension: dimension,
        value: value,
        confidence: confidence,
        evidenceCount: weights[entry.key]!.length,
        lastObservedAt: lastSeen[entry.key]!,
      ));
    }
    traits.sort((a, b) => b.confidence.compareTo(a.confidence));
    return traits;
  }

  static double _decay(DateTime observedAt, DateTime now) {
    final double ageDays = math.max(0, now.difference(observedAt).inMinutes / (60 * 24));
    return math.pow(0.5, ageDays / halfLife.inDays).toDouble();
  }
}
