import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:town_pass/page/city_service/model/my_service_model.dart';
import 'package:town_pass/service/subscription_service.dart';
import 'package:town_pass/service/system_one/jev_recommendation_ranker.dart';
import 'package:town_pass/service/user_traits/recommendation_embeddings.dart';
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
  RecommendationService({
    Future<UserTraitRepository> Function()? repository,
    Future<RecommendationEmbeddings?> Function()? embeddings,
    JevRecommendationRanker? systemOne,
  })  : _repository = repository ?? UserTraitRepository.shared,
        _loadEmbeddings = embeddings ?? RecommendationEmbeddings.load,
        _systemOne = systemOne ?? JevRecommendationRanker();

  final Future<UserTraitRepository> Function() _repository;
  final Future<RecommendationEmbeddings?> Function() _loadEmbeddings;
  final JevRecommendationRanker _systemOne;
  RecommendationEmbeddings? _embeddings;

  /// System One 判斷「這個人會想要這個項目」的機率（key 見 [RecommendationEmbeddings.targetKey]）。
  /// 疊加在特徵分與語意分之上；沒有金鑰或還沒算完時為空，推薦照原本的算法。
  final RxMap<String, double> systemOneScores = <String, double>{}.obs;

  String? _lastProfileSignature;
  int _systemOneRequest = 0;

  /// 最近一次 System One 重新判斷；測試或模擬腳本可以 await 它等結果回來。
  Future<void> lastSystemOneRefresh = Future.value();

  /// 夠可信的特徵（依可信度由高到低）。
  final RxList<UserTrait> traits = <UserTrait>[].obs;

  /// 使用者關心的服務（問到、點開過，夠可信的）→ 興趣強度。
  final RxMap<String, double> serviceInterests = <String, double>{}.obs;

  /// 各推薦項目的語意加分（key 見 [RecommendationEmbeddings.targetKey]），由 [serviceInterests] 算出。
  final RxMap<String, double> semanticBonuses = <String, double>{}.obs;

  /// 使用者明確拒絕的項目（取消訂閱、從我的服務移除），key 見 [RecommendationEmbeddings.targetKey]。
  /// 這些項目不再推薦：分數一律為 0。
  final RxSet<String> rejected = <String>{}.obs;

  bool get hasTraits => traits.isNotEmpty;

  Future<RecommendationService> init() async {
    _embeddings = await _loadEmbeddings();
    await reload();
    return this;
  }

  Future<void> reload() async {
    try {
      final DateTime now = DateTime.now();
      final UserTraitRepository repository = await _repository();
      final List<TraitObservation> observations = await repository.observations();
      rejected.assignAll({for (final (String surface, String item) in await repository.rejectedItems()) '$surface|$item'});
      _setServiceInterests(serviceInterestsOf(observations, now: now));
      traits.assignAll(TraitAggregator.aggregate(observations, now: now)
          .where((trait) => trait.confidence >= TraitAggregator.confidentThreshold));
      debugPrint('[推薦] 特徵 ${traits.length} 筆：${traits.map((t) => '${t.dimension.name}=${t.value}').join('、')}；'
          '關心的服務：${serviceInterests.entries.map((e) => '${e.key} ${e.value.toStringAsFixed(2)}').join('、')}');
      _refreshSystemOne(UserProfile(
        traits: traits.toList(),
        recentItems: recentItemsOf(observations),
        subscribed: Get.isRegistered<SubscriptionService>() ? Get.find<SubscriptionService>().subscribedTitles : const [],
        rejected: [for (final String key in rejected) key.split('|').last],
      ));
    } catch (error) {
      // 讀不到就當作沒有特徵：所有畫面維持原樣
      debugPrint('[推薦] 讀取特徵失敗：$error');
      traits.clear();
      rejected.clear();
      _setServiceInterests(const {});
    }
  }

  /// 最近問過、點過、選過的服務或內容（新的在前，最多 [limit] 個）；不含 LLM 推論、設定與拒絕。
  static List<String> recentItemsOf(List<TraitObservation> observations, {int limit = 10}) {
    final List<TraitObservation> sorted = [
      for (final TraitObservation o in observations)
        if (o.detail != null &&
            o.source != TraitSource.llm &&
            !o.source.negative &&
            !o.evidenceKey.startsWith('setting:'))
          o,
    ]..sort((a, b) => b.observedAt.compareTo(a.observedAt));
    final Set<String> seen = {};
    return [
      for (final TraitObservation o in sorted)
        if (seen.add(o.detail!)) o.detail!,
    ].take(limit).toList();
  }

  /// 側寫有變才請 System One 重新判斷（背景執行，不阻擋畫面；完成後畫面自動重排）。
  void _refreshSystemOne(UserProfile profile) {
    if (!_systemOne.isEnabled) return;
    if (profile.isEmpty) {
      _lastProfileSignature = null;
      systemOneScores.clear();
      return;
    }
    final String signature = profile.signature;
    if (signature == _lastProfileSignature) return;
    _lastProfileSignature = signature;
    final int request = ++_systemOneRequest;
    lastSystemOneRefresh = _systemOne.rank(profile, texts: _embeddings).then((scores) {
      if (request != _systemOneRequest) return; // 已有更新的側寫
      systemOneScores.assignAll(scores);
      final List<MapEntry<String, double>> top = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      debugPrint('[推薦/System One] ${top.take(6).map((e) => '${e.key.split('|').last} ${e.value.toStringAsFixed(2)}').join('、')}');
    }).catchError((Object error) {
      if (request == _systemOneRequest) _lastProfileSignature = null; // 下次再試
      debugPrint('[推薦/System One] 失敗，只用特徵與語意：$error');
    });
  }

  /// 測試或預覽用：直接指定 System One 的機率。
  @visibleForTesting
  void setSystemOneScores(Map<(RecommendationSurface, String), double> scores) => systemOneScores.assignAll({
        for (final MapEntry<(RecommendationSurface, String), double> e in scores.entries)
          RecommendationEmbeddings.targetKey(e.key.$1, e.key.$2): e.value,
      });

  /// 測試或預覽用：直接指定被拒絕的項目。
  @visibleForTesting
  void setRejected(Iterable<(RecommendationSurface, String)> items) =>
      rejected.assignAll({for (final (RecommendationSurface surface, String item) in items) '${surface.name}|$item'});

  bool isRejected(RecommendationTarget target) =>
      rejected.contains(RecommendationEmbeddings.targetKey(target.surface, target.match));

  /// 項目分數：特徵＋語意＋System One；被拒絕的項目為 0（維持原本位置，不會被推上來）。
  double scoreOf(RecommendationTarget target) =>
      isRejected(target) ? 0 : RecommendationTargets.score(target, traits, bonus: _bonus);

  /// 測試或預覽用：直接指定特徵。
  @visibleForTesting
  void setTraits(List<UserTrait> value) => traits.assignAll(value);

  /// 測試或預覽用：直接指定關心的服務與向量。
  @visibleForTesting
  void setServiceInterests(Map<String, double> value, {RecommendationEmbeddings? embeddings}) {
    if (embeddings != null) _embeddings = embeddings;
    _setServiceInterests(value);
  }

  void _setServiceInterests(Map<String, double> value) {
    serviceInterests.assignAll(value);
    semanticBonuses.assignAll(_embeddings?.bonuses(value) ?? const {});
  }

  /// 加分 = 語意相似度 + System One（兩者都只在有資料時加）。
  double _bonus(RecommendationTarget target) {
    final String key = RecommendationEmbeddings.targetKey(target.surface, target.match);
    final double? systemOne = systemOneScores[key];
    return (semanticBonuses[key] ?? 0) + (systemOne == null ? 0 : JevRecommendationRanker.bonusOf(systemOne));
  }

  /// 排序依據（特徵、語意、System One、拒絕）有變時呼叫 [onChange]；短時間內多次變動只呼叫一次。
  /// 不是用 Obx 的畫面（例如先載入資料再排序的首頁大圖、活動）用這個重排。記得在 onClose 呼叫 dispose。
  Worker listenRankingChanges(VoidCallback onChange) => debounce<int>(
        _rankingVersion,
        (_) => onChange(),
        time: const Duration(milliseconds: 100),
      );

  late final RxInt _rankingVersion = () {
    final RxInt version = 0.obs;
    everAll([traits, semanticBonuses, systemOneScores, rejected], (_) => version.value++);
    return version;
  }();

  /// 依特徵與語意相似度重新排序 [items]（分數相同維持原順序）。
  List<T> rank<T>(RecommendationSurface surface, List<T> items, {required String Function(T item) titleOf}) =>
      RecommendationTargets.rank(surface, items, traits, titleOf: titleOf, scoreOf: scoreOf);

  /// 某個位置裡和使用者相關（分數 > 0）的項目，依分數由高到低。
  List<RecommendationTarget> matching(RecommendationSurface surface) {
    final List<(RecommendationTarget, double)> scored = [
      for (final RecommendationTarget target in RecommendationTargets.of(surface)) (target, scoreOf(target)),
    ]..removeWhere((pair) => pair.$2 <= 0);
    // 分數相同維持對照表原本的順序
    final List<RecommendationTarget> order = RecommendationTargets.of(surface);
    scored.sort((a, b) {
      final int byScore = b.$2.compareTo(a.$2);
      return byScore != 0 ? byScore : order.indexOf(a.$1).compareTo(order.indexOf(b.$1));
    });
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
