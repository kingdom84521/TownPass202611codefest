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
/// 5. **明確拒絕扣分但不歸零**（取消訂閱、從我的服務移除，[TraitSource.negative]）：
///    反向證據同樣以 noisy-OR 綜合為拒絕度 N，可信度 × (1 − [optOutPenalty] × N)。
///    例：開車 0.66，取消訂閱「交通措施」一次 → 0.66 × (1 − 0.5 × 0.8) = 0.40。
///    取消「交通措施」不代表他不開車，所以只扣一部分；之後有新的正向證據就會回來。
///
/// 可信度達到 [confidentThreshold] 才建議拿去做推薦。
abstract final class TraitAggregator {
  static const Duration halfLife = Duration(days: 90);
  static const double confidentThreshold = 0.6;

  /// 拒絕度為 1 時最多扣掉一半可信度。
  static const double optOutPenalty = 0.5;

  /// 低於此值的特徵不回傳，避免雜訊。
  static const double minConfidence = 0.05;

  static List<UserTrait> aggregate(Iterable<TraitObservation> observations, {required DateTime now}) {
    // (維度, 值) → (證據 → 最大權重)
    final Map<(TraitDimension, String), Map<String, double>> weights = {};
    final Map<(TraitDimension, String), Map<String, double>> optOuts = {};
    final Map<(TraitDimension, String), DateTime> lastSeen = {};
    for (final TraitObservation observation in observations) {
      final (TraitDimension, String) key = (observation.dimension, observation.value);
      final double weight = observation.confidence * observation.source.weight * _decay(observation.observedAt, now);
      if (observation.source.negative) {
        final Map<String, double> byEvidence = optOuts.putIfAbsent(key, () => {});
        byEvidence[observation.evidenceKey] = math.max(byEvidence[observation.evidenceKey] ?? 0, weight);
        continue;
      }
      final Map<String, double> byEvidence = weights.putIfAbsent(key, () => {});
      byEvidence[observation.evidenceKey] = math.max(byEvidence[observation.evidenceKey] ?? 0, weight);
      final DateTime? seen = lastSeen[key];
      if (seen == null || observation.observedAt.isAfter(seen)) lastSeen[key] = observation.observedAt;
    }

    double noisyOr(Iterable<double> values) => 1 - values.fold<double>(1, (product, w) => product * (1 - w));
    final Map<(TraitDimension, String), double> support = {
      for (final MapEntry<(TraitDimension, String), Map<String, double>> entry in weights.entries)
        entry.key: noisyOr(entry.value.values) * (1 - optOutPenalty * noisyOr(optOuts[entry.key]?.values ?? const [])),
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
