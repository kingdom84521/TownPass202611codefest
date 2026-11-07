import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:town_pass/page/city_service/model/my_service_model.dart';
import 'package:town_pass/service/user_traits/recommendation_targets.dart';
import 'package:town_pass/service/user_traits/trait_aggregator.dart';
import 'package:town_pass/service/user_traits/user_trait.dart';
import 'package:town_pass/service/user_traits/user_trait_repository.dart';

/// 依使用者特徵做推薦，給各畫面使用。
///
/// - 啟動時從本機資料庫讀出特徵；服務小幫手每記錄一次就 [reload]，畫面透過 [traits]（Rx）自動更新。
/// - 只用可信度 ≥ [TraitAggregator.confidentThreshold] 的特徵。
/// - 沒有任何特徵時，每個推薦都回傳原本的內容與順序，畫面跟沒有推薦時一樣。
class RecommendationService extends GetxService {
  RecommendationService({Future<UserTraitRepository> Function()? repository})
      : _repository = repository ?? UserTraitRepository.shared;

  final Future<UserTraitRepository> Function() _repository;

  /// 夠可信的特徵（依可信度由高到低）。
  final RxList<UserTrait> traits = <UserTrait>[].obs;

  bool get hasTraits => traits.isNotEmpty;

  Future<RecommendationService> init() async {
    await reload();
    return this;
  }

  Future<void> reload() async {
    try {
      final List<UserTrait> loaded =
          await (await _repository()).traits(minConfidence: TraitAggregator.confidentThreshold);
      traits.assignAll(loaded);
      debugPrint('[推薦] 特徵 ${loaded.length} 筆：${loaded.map((t) => '${t.dimension.name}=${t.value}').join('、')}');
    } catch (error) {
      // 讀不到就當作沒有特徵：所有畫面維持原樣
      debugPrint('[推薦] 讀取特徵失敗：$error');
      traits.clear();
    }
  }

  /// 測試或預覽用：直接指定特徵。
  @visibleForTesting
  void setTraits(List<UserTrait> value) => traits.assignAll(value);

  /// 依特徵重新排序 [items]（分數相同維持原順序）。
  List<T> rank<T>(RecommendationSurface surface, List<T> items, {required String Function(T item) titleOf}) =>
      RecommendationTargets.rank(surface, items, traits, titleOf: titleOf);

  /// 某個位置裡和使用者特徵相關（分數 > 0）的項目，依分數由高到低。
  List<RecommendationTarget> matching(RecommendationSurface surface) {
    final List<(RecommendationTarget, double)> scored = [
      for (final RecommendationTarget target in RecommendationTargets.of(surface))
        (target, RecommendationTargets.score(target, traits)),
    ]..removeWhere((pair) => pair.$2 <= 0);
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final (RecommendationTarget target, _) in scored) target];
  }

  /// 推薦訂閱的主題（排除已訂閱的），最多 [limit] 個。
  List<String> subscriptionTopics({required Set<String> subscribed, int limit = 2}) => [
        for (final RecommendationTarget target in matching(RecommendationSurface.subscriptionTopic))
          if (!subscribed.contains(target.match)) target.match,
      ].take(limit).toList();

  /// 小幫手開場的建議問法：候選清單依特徵排序取前 [limit] 個；沒有特徵時就是原本的預設問法。
  List<String> assistantChips({int limit = 5}) => rank(
        RecommendationSurface.assistantChip,
        [for (final RecommendationTarget target in RecommendationTargets.assistantChips) target.match],
        titleOf: (chip) => chip,
      ).take(limit).toList();

  /// 推薦的服務（點得開、和特徵相關），依分數由高到低。
  List<MyServiceItemId> services() => [
        for (final RecommendationTarget target in matching(RecommendationSurface.service))
          ...MyServiceItemId.values.where((id) => id.item.title == target.match),
      ];

  /// 「我的服務」的初始清單：推薦的服務放前面，再用原本的預設補滿 [size] 個。
  List<MyServiceItemId> pinnedServices(List<MyServiceItemId> defaults, {int size = 3}) =>
      {...services(), ...defaults}.take(size).toList();

  /// 「你可能需要」：推薦但還沒放進我的服務的服務，最多 [limit] 個。
  List<MyServiceItemId> suggestedServices({required List<MyServiceItemId> pinned, int limit = 3}) =>
      services().where((id) => !pinned.contains(id)).take(limit).toList();

  /// 有註冊時回傳實例；測試或尚未初始化時回傳 null，呼叫端退回原本行為。
  static RecommendationService? get maybe =>
      Get.isRegistered<RecommendationService>() ? Get.find<RecommendationService>() : null;
}

/// 給小幫手用：特徵記錄完成後通知推薦重新讀取。
void notifyTraitsChanged() => RecommendationService.maybe?.reload();
