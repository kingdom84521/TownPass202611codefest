import 'package:town_pass/service/system_one/jev_client.dart';
import 'package:town_pass/service/user_traits/recommendation_embeddings.dart';
import 'package:town_pass/service/user_traits/recommendation_targets.dart';
import 'package:town_pass/service/user_traits/user_trait.dart';

/// 使用者側寫：交給 System One 判斷推薦用。只有整理過的特徵與互動紀錄，不含問句原文。
class UserProfile {
  const UserProfile({
    this.traits = const [],
    this.recentItems = const [],
    this.subscribed = const [],
    this.rejected = const [],
  });

  /// 夠可信的特徵。
  final List<UserTrait> traits;

  /// 最近問過、點過、選過的服務或內容（新的在前）。
  final List<String> recentItems;

  final List<String> subscribed;

  /// 明確拒絕的項目（取消訂閱、從我的服務移除）。
  final List<String> rejected;

  bool get isEmpty => traits.isEmpty && recentItems.isEmpty && subscribed.isEmpty;

  /// 給 Jev 的 state：鍵用中文，讓模型容易讀懂。
  Map<String, Object> toState() => {
        '使用者特徵（可信度 0 到 1）': {
          for (final UserTrait trait in traits)
            TraitDimension.labels[trait.value] ?? trait.value: double.parse(trait.confidence.toStringAsFixed(2)),
        },
        '最近問過或點過的服務與內容（新的在前）': recentItems,
        '已訂閱的主題': subscribed,
        '使用者明確不要的項目': rejected,
      };

  /// 側寫有變才需要重新判斷。
  String get signature => [
        for (final UserTrait trait in traits) '${trait.dimension.name}=${trait.value}:${trait.confidence.toStringAsFixed(1)}',
        '|',
        ...recentItems,
        '|',
        ...subscribed,
        '|',
        ...rejected,
      ].join(',');
}

/// 用 System One（Jev）判斷「這個人會不會想要這個推薦項目」。
///
/// 所有可推薦的項目（輪播、活動、訂閱主題、服務、繳費、建議問法）各一道是非題，放在同一次請求；
/// 回傳每個項目的機率（key 見 [RecommendationEmbeddings.targetKey]）。
/// 這個分數是**疊加**在特徵分與語意分之上的（見 RecommendationService.scoreOf），不取代原本的算法。
class JevRecommendationRanker {
  JevRecommendationRanker({JevClient? client}) : client = client ?? JevClient();

  final JevClient client;

  bool get isEnabled => client.isEnabled;

  static const Map<RecommendationSurface, String> surfaceLabels = {
    RecommendationSurface.homeBanner: '首頁大圖',
    RecommendationSurface.homeActivity: '首頁活動訊息',
    RecommendationSurface.subscriptionTopic: '可訂閱的通知主題',
    RecommendationSurface.service: 'App 裡的服務',
    RecommendationSurface.bill: '繳費項目',
    RecommendationSurface.assistantChip: '服務小幫手的建議問法',
  };

  /// 會問的項目：刻意不推薦的（醫療、報案、社福身分）不出題。
  static List<RecommendationTarget> get targets => [
        for (final RecommendationSurface surface in RecommendationSurface.values)
          for (final RecommendationTarget target in RecommendationTargets.of(surface))
            if (target.excludedReason == null) target,
      ];

  static JevYesNo question(RecommendationTarget target, {String? text}) => JevYesNo(
        '根據使用者側寫，這位使用者會想看到這個推薦嗎？'
        '只根據側寫中的特徵與最近問過的服務判斷，沒有相關線索就回答否。'
        '項目（${surfaceLabels[target.surface]}）：${text ?? target.match}',
      );

  /// 回傳每個項目「會想要」的機率。失敗時丟出 [JevException]。
  Future<Map<String, double>> rank(UserProfile profile, {RecommendationEmbeddings? texts}) async {
    final List<RecommendationTarget> items = targets;
    final JevAnswers answers = await client.decide(
      state: profile.toState(),
      questions: {
        for (int i = 0; i < items.length; i++) 'item_$i': question(items[i], text: texts?.textOf(items[i])),
      },
    );
    return {
      for (int i = 0; i < items.length; i++)
        if (answers.yes('item_$i') case final double p)
          RecommendationEmbeddings.targetKey(items[i].surface, items[i].match): p,
    };
  }

  /// Jev 機率換成加分：0.5 以下（不確定或否）不加分，1.0 加 [weight] 分。
  /// Jev 看得到整份側寫，比人工對照表可靠，所以權重是兩個確定特徵：
  /// 實測開車族「交通措施」靠多掛一個「道路交通」特徵（0.84）會超過「停車費通知」，權重 1 時擋不住。
  static const double weight = 2.0;

  static double bonusOf(double probability) => ((probability - 0.5) * 2).clamp(0.0, 1.0) * weight;
}
