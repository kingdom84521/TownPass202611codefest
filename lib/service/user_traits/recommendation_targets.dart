import 'package:town_pass/service/user_traits/trait_aggregator.dart';
import 'package:town_pass/service/user_traits/user_trait.dart';
import 'package:town_pass/service/user_traits/user_trait_recorder.dart';

/// App 上可以放推薦的位置。
enum RecommendationSurface {
  /// 首頁頂部大圖輪播。
  homeBanner,

  /// 首頁「活動訊息」。
  homeActivity,

  /// 首頁「訂閱」：推薦訂閱主題。
  subscriptionTopic,

  /// 服務頁「我的服務」與「你可能需要」。
  service,

  /// 帳務頁「熱門繳費」排序。
  bill,

  /// 服務小幫手開場的建議問法。
  assistantChip,
}

/// 一個可以被推薦的項目，以及「哪些特徵代表這個人可能需要它」。
class RecommendationTarget {
  const RecommendationTarget(this.surface, this.match, this.tags, {this.excludedReason});

  final RecommendationSurface surface;

  /// 用來對應畫面上的項目：服務、繳費、訂閱主題、建議問法為完整名稱；
  /// 活動與大圖的標題很長，用標題中的一段文字比對（見 [matches]）。
  final String match;

  final List<(TraitDimension, String)> tags;

  /// 刻意不推薦的原因（例如醫療、社福身分）；有值時 [tags] 為空，永遠排在原本的位置。
  final String? excludedReason;

  bool matches(String title) => surface == RecommendationSurface.homeActivity || surface == RecommendationSurface.homeBanner
      ? title.contains(match)
      : title == match;
}

/// 各推薦位置的項目與特徵對照表，以及排序方法。
///
/// 排序規則：項目分數 = 符合的特徵中，可信度 ≥ [TraitAggregator.confidentThreshold] 者的可信度總和。
/// 分數相同（包括完全沒有特徵的新使用者）維持原本的順序，所以沒有資料時畫面跟現在一樣。
abstract final class RecommendationTargets {
  static const TraitDimension _i = TraitDimension.interest;
  static const TraitDimension _r = TraitDimension.relation;
  static const TraitDimension _t = TraitDimension.transport;
  static const TraitDimension _c = TraitDimension.caregiverOf;

  static const List<RecommendationTarget> homeBanners = [
    RecommendationTarget(RecommendationSurface.homeBanner, '樂運動', [(_i, 'sports'), (_i, 'nature_parks')]),
    RecommendationTarget(RecommendationSurface.homeBanner, '減碳', [(_i, 'environment')]),
    // 以下為示範資料（插圖在 assets/mock_data/images/）
    RecommendationTarget(RecommendationSurface.homeBanner, '停車費', [(_t, 'car_scooter'), (_i, 'bills_payment')]),
    RecommendationTarget(RecommendationSurface.homeBanner, '親子館', [(_i, 'family_outings'), (_c, 'child')]),
    RecommendationTarget(RecommendationSurface.homeBanner, '防災包', [(_i, 'disaster_weather'), (_r, 'resident')]),
    RecommendationTarget(RecommendationSurface.homeBanner, '閱讀馬拉松', [(_i, 'reading')]),
    RecommendationTarget(RecommendationSurface.homeBanner, '寵物友善', [(_i, 'pets'), (_i, 'nature_parks')]),
    RecommendationTarget(RecommendationSurface.homeBanner, '銀髮樂活', [(_c, 'elder')]),
  ];

  /// 對應 assets/mock_data/activity.json 的活動（原本 6 則＋示範 6 則）。
  static const List<RecommendationTarget> homeActivities = [
    RecommendationTarget(RecommendationSurface.homeActivity, '開徵稅單', [(_i, 'bills_payment'), (_r, 'resident')]),
    RecommendationTarget(RecommendationSurface.homeActivity, '好玩卡', [(_i, 'places_travel'), (_r, 'visitor'), (_t, 'public_transit')]),
    RecommendationTarget(RecommendationSurface.homeActivity, 'e化繳稅', [(_i, 'bills_payment'), (_r, 'resident')]),
    RecommendationTarget(RecommendationSurface.homeActivity, '健康集點', [(_i, 'wellness'), (_i, 'sports')]),
    RecommendationTarget(RecommendationSurface.homeActivity, '找樂點', [(_i, 'places_travel'), (_r, 'visitor')]),
    RecommendationTarget(RecommendationSurface.homeActivity, '士林好神', [(_i, 'culture_events'), (_i, 'places_travel')]),
    // 以下為示範資料（插圖在 assets/mock_data/images/）
    RecommendationTarget(RecommendationSurface.homeActivity, '轉乘優惠', [(_t, 'public_transit'), (_r, 'commuter')]),
    RecommendationTarget(RecommendationSurface.homeActivity, '藝術節', [(_i, 'culture_events')]),
    RecommendationTarget(RecommendationSurface.homeActivity, '參與式預算', [(_i, 'civic_participation'), (_i, 'city_affairs')]),
    RecommendationTarget(RecommendationSurface.homeActivity, '社區大學', [(_i, 'learning')]),
    RecommendationTarget(RecommendationSurface.homeActivity, '新住民', [(_r, 'new_resident')]),
    RecommendationTarget(
        RecommendationSurface.homeActivity, '動物園夜間', [(_i, 'family_outings'), (_r, 'visitor'), (_i, 'places_travel')]),
  ];

  /// 訂閱網頁上的 10 個主題（名稱與網頁一致）。
  static const List<RecommendationTarget> subscriptionTopics = [
    RecommendationTarget(RecommendationSurface.subscriptionTopic, '體育樂園', [(_i, 'sports')]),
    RecommendationTarget(RecommendationSurface.subscriptionTopic, '臺北旅遊網最新消息', [(_i, 'places_travel'), (_r, 'visitor')]),
    RecommendationTarget(RecommendationSurface.subscriptionTopic, '交通措施',
        [(_i, 'roads_traffic'), (_r, 'commuter'), (_t, 'car_scooter'), (_t, 'public_transit')]),
    RecommendationTarget(RecommendationSurface.subscriptionTopic, '銀髮資訊', [(_c, 'elder')]),
    RecommendationTarget(RecommendationSurface.subscriptionTopic, '圖書到期通知', [(_i, 'reading')]),
    RecommendationTarget(RecommendationSurface.subscriptionTopic, '新住民心服務', [(_r, 'new_resident')]),
    RecommendationTarget(RecommendationSurface.subscriptionTopic, '健康報報', [(_i, 'wellness')]),
    RecommendationTarget(RecommendationSurface.subscriptionTopic, '停車費通知', [(_t, 'car_scooter')]),
    RecommendationTarget(RecommendationSurface.subscriptionTopic, '空品資訊', [(_i, 'environment'), (_t, 'walk_bike')]),
    RecommendationTarget(RecommendationSurface.subscriptionTopic, '防汛資訊', [(_i, 'disaster_weather'), (_r, 'resident')]),
  ];

  /// 帳務「熱門繳費」9 項（名稱與 BillView.popularBillItems 一致）。
  static const List<RecommendationTarget> bills = [
    RecommendationTarget(RecommendationSurface.bill, '停車費', [(_t, 'car_scooter')]),
    RecommendationTarget(RecommendationSurface.bill, '水費', [(_r, 'resident')]),
    RecommendationTarget(RecommendationSurface.bill, '地方稅', [(_r, 'resident')]),
    RecommendationTarget(RecommendationSurface.bill, '學雜費', [(_c, 'child')]),
    RecommendationTarget(RecommendationSurface.bill, '國/社宅租金維管費', [], excludedReason: '社福身分'),
    RecommendationTarget(RecommendationSurface.bill, '聯合醫院醫療費', [], excludedReason: '醫療'),
    RecommendationTarget(RecommendationSurface.bill, '平價住宅維護費', [], excludedReason: '社福身分'),
    RecommendationTarget(RecommendationSurface.bill, '公訓處自費課程', [(_i, 'learning')]),
    RecommendationTarget(RecommendationSurface.bill, '其他', [(_i, 'bills_payment')]),
  ];

  /// 可以推薦的服務：點得開的服務，特徵沿用 [UserTraitRecorder] 的服務對照。
  static final List<RecommendationTarget> services = [
    for (final String title in const ['申辦服務', '有話要說', '臨櫃叫號', '災情通報', '圖書借閱', '找地點'])
      RecommendationTarget(RecommendationSurface.service, title, UserTraitRecorder.traitsOfService(title)),
  ];

  /// 小幫手的候選建議問法（都能在小幫手找到對應服務）。
  /// 前 5 個就是原本的預設問法：沒有特徵時排序不變，畫面跟原本一樣。
  static const List<RecommendationTarget> assistantChips = [
    RecommendationTarget(RecommendationSurface.assistantChip, '我想借書', [(_i, 'reading')]),
    RecommendationTarget(RecommendationSurface.assistantChip, '附近有什麼', [(_i, 'places_travel'), (_r, 'visitor')]),
    RecommendationTarget(RecommendationSurface.assistantChip, '要看醫生', [], excludedReason: '醫療，不依特徵推薦，維持預設位置'),
    RecommendationTarget(RecommendationSurface.assistantChip, '繳水費', [(_r, 'resident'), (_i, 'bills_payment')]),
    RecommendationTarget(RecommendationSurface.assistantChip, '我要報案', [], excludedReason: '報案屬敏感，不依特徵推薦，維持預設位置'),
    RecommendationTarget(RecommendationSurface.assistantChip, '繳停車費', [(_t, 'car_scooter')]),
    RecommendationTarget(RecommendationSurface.assistantChip, '繳學費', [(_c, 'child')]),
    RecommendationTarget(RecommendationSurface.assistantChip, '路上有坑洞', [(_i, 'civic_participation'), (_i, 'roads_traffic')]),
    RecommendationTarget(RecommendationSurface.assistantChip, '颱風淹水通報', [(_i, 'disaster_weather')]),
    RecommendationTarget(RecommendationSurface.assistantChip, '臨櫃要排隊嗎', [(_i, 'city_affairs')]),
    RecommendationTarget(RecommendationSurface.assistantChip, '動物園怎麼去', [(_i, 'family_outings'), (_r, 'visitor')]),
    RecommendationTarget(RecommendationSurface.assistantChip, '附近的公園', [(_i, 'nature_parks'), (_i, 'pets')]),
  ];

  static List<RecommendationTarget> of(RecommendationSurface surface) => switch (surface) {
        RecommendationSurface.homeBanner => homeBanners,
        RecommendationSurface.homeActivity => homeActivities,
        RecommendationSurface.subscriptionTopic => subscriptionTopics,
        RecommendationSurface.service => services,
        RecommendationSurface.bill => bills,
        RecommendationSurface.assistantChip => assistantChips,
      };

  /// 項目對這位使用者的分數：符合且夠可信的特徵，可信度加總，再加上語意加分 [bonus]
  /// （使用者關心的服務和這個項目有多接近，見 RecommendationEmbeddings）。刻意不推薦的項目不加分。
  static double score(RecommendationTarget target, List<UserTrait> traits, {double Function(RecommendationTarget)? bonus}) {
    double total = target.excludedReason == null ? (bonus?.call(target) ?? 0) : 0;
    for (final UserTrait trait in traits) {
      if (trait.confidence < TraitAggregator.confidentThreshold) continue;
      if (target.tags.contains((trait.dimension, trait.value))) total += trait.confidence;
    }
    return total;
  }

  /// 依分數由高到低排序 [items]（畫面上原本的順序），分數相同維持原順序。
  /// [titleOf] 取出項目的標題，用來對應對照表；對不到的項目分數為 0。
  static List<T> rank<T>(
    RecommendationSurface surface,
    List<T> items,
    List<UserTrait> traits, {
    required String Function(T item) titleOf,
    double Function(RecommendationTarget)? bonus,
    double Function(RecommendationTarget)? scoreOf,
  }) {
    final List<RecommendationTarget> targets = of(surface);
    final List<(int, T, double)> scored = [
      for (int i = 0; i < items.length; i++)
        (
          i,
          items[i],
          targets
              .where((t) => t.matches(titleOf(items[i])))
              .map((t) => scoreOf?.call(t) ?? score(t, traits, bonus: bonus))
              .fold(0.0, (a, b) => a + b),
        ),
    ]..sort((a, b) {
        final int byScore = b.$3.compareTo(a.$3);
        return byScore != 0 ? byScore : a.$1.compareTo(b.$1);
      });
    return [for (final (_, T item, _) in scored) item];
  }
}
