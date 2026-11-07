import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/page/city_service/model/my_service_model.dart';
import 'package:town_pass/service/recommendation_service.dart';
import 'package:town_pass/service/user_traits/recommendation_targets.dart';
import 'package:town_pass/service/user_traits/user_trait.dart';

UserTrait _trait(TraitDimension dimension, String value, double confidence) => UserTrait(
      dimension: dimension,
      value: value,
      confidence: confidence,
      evidenceCount: 2,
      lastObservedAt: DateTime(2026, 11, 7),
    );

const List<MyServiceItemId> _defaults = [
  MyServiceItemId.locationSearch,
  MyServiceItemId.districtOffice,
  MyServiceItemId.dashboard,
];

void main() {
  group('沒有特徵：每個位置都跟原本一樣', () {
    final RecommendationService service = RecommendationService()..setTraits(const []);

    test('小幫手建議問法 = 原本預設', () {
      expect(service.assistantChips(), ['我想借書', '附近有什麼', '要看醫生', '繳水費', '我要報案']);
    });

    test('我的服務 = 預設、沒有「你可能需要」、沒有推薦訂閱', () {
      expect(service.pinnedServices(_defaults), _defaults);
      expect(service.suggestedServices(pinned: _defaults), isEmpty);
      expect(service.subscriptionTopics(subscribed: {}), isEmpty);
    });

    test('排序維持原順序', () {
      const List<String> bills = ['停車費', '水費', '地方稅', '學雜費'];
      expect(service.rank(RecommendationSurface.bill, bills, titleOf: (b) => b), bills);
    });
  });

  group('有特徵：帶小孩出遊的觀光客、愛看書', () {
    final RecommendationService service = RecommendationService()
      ..setTraits([
        _trait(TraitDimension.caregiverOf, 'child', 0.99),
        _trait(TraitDimension.interest, 'family_outings', 0.99),
        _trait(TraitDimension.relation, 'visitor', 0.9),
        _trait(TraitDimension.interest, 'nature_parks', 0.9),
        _trait(TraitDimension.interest, 'reading', 0.8),
        _trait(TraitDimension.interest, 'sports', 0.5), // 不夠可信，不採用
      ]);

    test('小幫手建議問法依特徵排序，敏感的不會被推上來', () {
      expect(service.assistantChips(), ['動物園怎麼去', '繳學費', '附近有什麼', '附近的公園', '我想借書']);
    });

    test('熱門繳費：學雜費排第一', () {
      final List<String> ranked =
          service.rank(RecommendationSurface.bill, const ['停車費', '水費', '地方稅', '學雜費'], titleOf: (b) => b);
      expect(ranked.first, '學雜費');
    });

    test('首頁活動：觀光相關排前面', () {
      final List<String> ranked = service.rank(
        RecommendationSurface.homeActivity,
        const ['開徵稅單公告', '健康集點', '臺北好玩卡', '找樂點'],
        titleOf: (a) => a,
      );
      expect(ranked.take(2), ['臺北好玩卡', '找樂點']);
    });

    test('推薦訂閱：排除已訂閱，可信度不足的不推薦', () {
      expect(service.subscriptionTopics(subscribed: {}), ['臺北旅遊網最新消息', '圖書到期通知']);
      expect(service.subscriptionTopics(subscribed: {'臺北旅遊網最新消息'}), ['圖書到期通知']);
      expect(service.subscriptionTopics(subscribed: {}, limit: 10), isNot(contains('體育樂園')));
    });

    test('我的服務：推薦的放前面；已在我的服務就不出現在「你可能需要」', () {
      final List<MyServiceItemId> pinned = service.pinnedServices(_defaults);
      expect(pinned, [MyServiceItemId.library, MyServiceItemId.locationSearch, MyServiceItemId.districtOffice]);
      expect(service.suggestedServices(pinned: pinned), isEmpty);
      expect(service.suggestedServices(pinned: _defaults), [MyServiceItemId.library]);
    });
  });
}
