import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/page/city_service/model/my_service_model.dart';
import 'package:town_pass/service/recommendation_service.dart';
import 'package:town_pass/service/user_traits/recommendation_embeddings.dart';
import 'package:town_pass/service/user_traits/recommendation_targets.dart';
import 'package:town_pass/service/user_traits/user_trait.dart';
import 'package:town_pass/service/user_traits/user_trait_recorder.dart';

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

  test('使用者拒絕的項目不再推薦：取消訂閱的主題、移除的服務', () {
    final RecommendationService service = RecommendationService()
      ..setTraits([
        _trait(TraitDimension.interest, 'places_travel', 0.9),
        _trait(TraitDimension.interest, 'reading', 0.9),
      ]);
    expect(service.subscriptionTopics(subscribed: {}), ['臺北旅遊網最新消息', '圖書到期通知']);
    expect(service.services(), contains(MyServiceItemId.library));

    service.setRejected([
      (RecommendationSurface.subscriptionTopic, '臺北旅遊網最新消息'),
      (RecommendationSurface.service, '圖書借閱'),
    ]);
    expect(service.subscriptionTopics(subscribed: {}), ['圖書到期通知']);
    expect(service.services(), isNot(contains(MyServiceItemId.library)));
    expect(service.suggestedServices(pinned: const []), isNot(contains(MyServiceItemId.library)));
  });

  group('語意相似度（真的向量檔）', () {
    final RecommendationEmbeddings embeddings = RecommendationEmbeddings.fromJson(
      jsonDecode(File(RecommendationEmbeddings.assetPath).readAsStringSync()) as Map<String, dynamic>,
    );

    test('向量檔涵蓋每個推薦項目與對照表的每個服務（改了清單要重跑 tool/rag/build_embeddings_test.dart）', () {
      for (final RecommendationSurface surface in RecommendationSurface.values) {
        for (final RecommendationTarget target in RecommendationTargets.of(surface)) {
          expect(embeddings.hasTarget(target), isTrue, reason: '${surface.name} ${target.match}');
        }
      }
      for (final String title in UserTraitRecorder.serviceTitles) {
        expect(embeddings.hasService(title), isTrue, reason: title);
      }
    });

    test('問過停車費：特徵同分時，停車費通知排在交通措施前面', () {
      // 實機資料：三次關鍵字命中停車費 → 開車／騎車 0.657、關心停車費 0.657
      final RecommendationService service = RecommendationService()
        ..setTraits([
          _trait(TraitDimension.interest, 'places_travel', 0.9),
          _trait(TraitDimension.transport, 'car_scooter', 0.657),
          _trait(TraitDimension.interest, 'bills_payment', 0.657),
        ])
        ..setServiceInterests({'停車費': 0.657}, embeddings: embeddings);

      expect(service.subscriptionTopics(subscribed: {}), ['停車費通知', '臺北旅遊網最新消息']);
      expect(service.rank(RecommendationSurface.bill, const ['水費', '學雜費', '停車費'], titleOf: (b) => b).first, '停車費');
      expect(service.assistantChips().first, '繳停車費');
    });

    test('沒有關心的服務時沒有語意加分；敏感項目永遠不加分', () {
      expect(embeddings.bonuses(const {}), isEmpty);
      final Map<String, double> bonuses = embeddings.bonuses({for (final title in UserTraitRecorder.serviceTitles) title: 1.0});
      for (final RecommendationSurface surface in RecommendationSurface.values) {
        for (final RecommendationTarget target in RecommendationTargets.of(surface)) {
          if (target.excludedReason != null) {
            expect(bonuses[RecommendationEmbeddings.targetKey(surface, target.match)], isNull, reason: target.match);
          }
        }
      }
    });

    test('只有點開過、關鍵字命中的服務算「關心」，而且要夠可信', () {
      final DateTime now = DateTime(2026, 11, 7);
      TraitObservation keyword(String key) => TraitObservation(
            dimension: TraitDimension.transport,
            value: 'car_scooter',
            confidence: 0.5,
            source: TraitSource.keyword,
            evidenceKey: key,
            observedAt: now,
            detail: '停車費',
          );
      expect(serviceInterestsOf([keyword('q:1')], now: now), isEmpty, reason: '問一次只有 0.3，不夠');
      expect(serviceInterestsOf([keyword('q:1'), keyword('q:2'), keyword('q:3')], now: now).keys, ['停車費']);
      expect(
        serviceInterestsOf([
          TraitObservation(
            dimension: TraitDimension.language,
            value: 'ja',
            confidence: 0.8,
            source: TraitSource.click,
            evidenceKey: 'setting:translation_language',
            observedAt: now,
            detail: '翻譯語言',
          ),
        ], now: now),
        isEmpty,
        reason: '設定不是服務',
      );
    });
  });
}
