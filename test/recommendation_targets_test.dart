import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/page/bill/bill_view.dart';
import 'package:town_pass/service/user_traits/recommendation_targets.dart';
import 'package:town_pass/service/user_traits/user_trait.dart';

UserTrait _trait(TraitDimension dimension, String value, double confidence) => UserTrait(
      dimension: dimension,
      value: value,
      confidence: confidence,
      evidenceCount: 2,
      lastObservedAt: DateTime(2026, 11, 7),
    );

List<String> _titles(String asset, String field) => [
      for (final dynamic item in (jsonDecode(File(asset).readAsStringSync()) as Map<String, dynamic>)['data'] as List)
        (item as Map<String, dynamic>)[field] as String? ?? '',
    ];

void main() {
  group('涵蓋率：7 個推薦位置的每一項都能由特徵處理', () {
    void expectCovered(List<RecommendationTarget> targets) {
      for (final RecommendationTarget target in targets) {
        expect(target.tags.isNotEmpty || target.excludedReason != null, isTrue,
            reason: '「${target.match}」沒有對應特徵，也沒有說明為何不推薦');
        for (final (TraitDimension dimension, String value) in target.tags) {
          expect(dimension.allows(value), isTrue, reason: '「${target.match}」用了不存在的特徵 ${dimension.name}=$value');
        }
      }
    }

    test('every target uses only allowed trait values', () {
      for (final RecommendationSurface surface in RecommendationSurface.values) {
        expectCovered(RecommendationTargets.of(surface));
      }
    });

    test('首頁大圖：每張都剛好對到一項', () {
      final List<String> banners = [
        for (final dynamic item
            in (jsonDecode(File('assets/mock_data/home_banner.json').readAsStringSync()) as Map)['data'] as List)
          '${(item as Map)['title'] ?? ''}${item['name'] ?? ''}',
      ];
      expect(banners, hasLength(RecommendationTargets.homeBanners.length));
      for (final String banner in banners) {
        expect(RecommendationTargets.homeBanners.where((t) => t.matches(banner)), hasLength(1), reason: banner);
      }
    });

    test('示範資料的內建插圖都存在', () {
      for (final String asset in ['assets/mock_data/home_banner.json', 'assets/mock_data/activity.json']) {
        for (final dynamic item in (jsonDecode(File(asset).readAsStringSync()) as Map)['data'] as List) {
          final String url = (item as Map)['image_url'] as String;
          if (url.startsWith('assets/')) expect(File(url).existsSync(), isTrue, reason: url);
        }
      }
    });

    test('活動訊息：每則都有對照，且都有特徵（含健康集點）', () {
      final List<String> activities = _titles('assets/mock_data/activity.json', 'title');
      expect(activities, hasLength(RecommendationTargets.homeActivities.length));
      for (final String title in activities) {
        final Iterable<RecommendationTarget> hit = RecommendationTargets.homeActivities.where((t) => t.matches(title));
        expect(hit, hasLength(1), reason: title);
        expect(hit.single.tags, isNotEmpty, reason: title);
      }
    });

    test('訂閱主題：10 個都有特徵（含體育樂園、健康報報）', () {
      expect(RecommendationTargets.subscriptionTopics, hasLength(10));
      expect(RecommendationTargets.subscriptionTopics.every((t) => t.tags.isNotEmpty), isTrue);
    });

    test('熱門繳費：9 項都有對照，只有醫療與社福身分刻意不推薦', () {
      final List<String> names = BillView.popularBillItems.map((b) => b.name).toList();
      expect(names, hasLength(9));
      for (final String name in names) {
        expect(RecommendationTargets.bills.where((t) => t.matches(name)), hasLength(1), reason: name);
      }
      expect(
        RecommendationTargets.bills.where((t) => t.excludedReason != null).map((t) => t.match),
        unorderedEquals(['國/社宅租金維管費', '聯合醫院醫療費', '平價住宅維護費']),
      );
    });

    test('服務：點得開的 6 項都有特徵', () {
      expect(RecommendationTargets.services, hasLength(6));
      expect(RecommendationTargets.services.every((t) => t.tags.isNotEmpty), isTrue);
    });
  });

  group('排序', () {
    final List<String> topics = RecommendationTargets.subscriptionTopics.map((t) => t.match).toList();

    test('no traits keeps the original order (new users see today\'s UI)', () {
      expect(RecommendationTargets.rank(RecommendationSurface.subscriptionTopic, topics, const [], titleOf: (t) => t),
          topics);
    });

    test('confident traits move matching items to the front', () {
      final List<String> ranked = RecommendationTargets.rank(
        RecommendationSurface.subscriptionTopic,
        topics,
        [
          _trait(TraitDimension.transport, 'car_scooter', 0.9),
          _trait(TraitDimension.caregiverOf, 'elder', 0.7),
        ],
        titleOf: (t) => t,
      );
      // 停車費通知只掛開車，比同時掛開車與大眾運輸（其中之一）的交通措施具體，排前面
      expect(ranked.take(3), ['停車費通知', '銀髮資訊', '交通措施']);
    });

    test('traits below the confidence threshold are ignored', () {
      final List<String> ranked = RecommendationTargets.rank(
        RecommendationSurface.subscriptionTopic,
        topics,
        [_trait(TraitDimension.interest, 'sports', 0.4)],
        titleOf: (t) => t,
      );
      expect(ranked, topics);
    });

    test('activities rank by long titles via partial match', () {
      final List<String> activities = _titles('assets/mock_data/activity.json', 'title');
      final List<String> ranked = RecommendationTargets.rank(
        RecommendationSurface.homeActivity,
        activities,
        [_trait(TraitDimension.interest, 'culture_events', 0.8)],
        titleOf: (t) => t,
      );
      expect(ranked.first, contains('士林好神'));
    });

    test('excluded bills never move', () {
      final List<String> names = BillView.popularBillItems.map((b) => b.name).toList();
      final List<String> ranked = RecommendationTargets.rank(
        RecommendationSurface.bill,
        names,
        [_trait(TraitDimension.caregiverOf, 'child', 0.9), _trait(TraitDimension.transport, 'car_scooter', 0.8)],
        titleOf: (t) => t,
      );
      expect(ranked.take(2), ['學雜費', '停車費']);
      expect(ranked.indexOf('聯合醫院醫療費'), greaterThan(1));
    });
  });
}
