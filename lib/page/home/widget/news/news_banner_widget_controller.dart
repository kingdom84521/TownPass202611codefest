import 'dart:async';
import 'dart:convert';

import 'package:carousel_slider/carousel_controller.dart';
import 'package:town_pass/bean/home_banner.dart';
import 'package:town_pass/gen/assets.gen.dart';
import 'package:town_pass/service/recommendation_service.dart';
import 'package:town_pass/service/user_traits/recommendation_targets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class NewsBannerWidgetController extends GetxController {
  final CarouselSliderController controller = CarouselSliderController();

  int _carouselIndex = 0;

  int get carouselIndex => _carouselIndex;

  set carouselIndex(int index) {
    _carouselIndex = index;
    update();
  }

  bool _isLoading = true;

  bool get isLoading => _isLoading;

  set isLoading(bool value) {
    _isLoading = value;
    update();
  }

  HomeBannerList? list;

  /// 原始順序的資料；推薦依據有變時從這裡重新排序。
  HomeBannerList? _loaded;
  Worker? _rankingWorker;

  @override
  void onInit() {
    super.onInit();
    _rankingWorker = RecommendationService.maybe?.listenRankingChanges(_rank);

    Timer.periodic(
      const Duration(seconds: 3),
      (timer) async {
        timer.cancel();
        final String banners = await rootBundle.loadString(Assets.mockData.homeBanner);
        _loaded = HomeBannerList.fromJson(jsonDecode(banners));
        _rank();
        isLoading = false;
      },
    );
  }

  /// 依使用者特徵排序；沒有特徵時維持原順序。重排後回到第一張，讓最相關的先出現。
  void _rank() {
    final HomeBannerList? loaded = _loaded;
    if (loaded == null) return;
    final RecommendationService? recommendation = RecommendationService.maybe;
    final HomeBannerList ranked = recommendation == null
        ? loaded
        : HomeBannerList(
            data: recommendation.rank(RecommendationSurface.homeBanner, loaded.data, titleOf: (b) => b.title),
          );
    final bool changed = list == null ||
        !listEquals(list!.data.map((b) => b.title).toList(), ranked.data.map((b) => b.title).toList());
    list = ranked;
    if (!changed) return;
    _carouselIndex = 0;
    if (!_isLoading) {
      try {
        controller.jumpToPage(0);
      } catch (_) {
        // 輪播還沒掛上畫面
      }
    }
    update();
  }

  @override
  void onClose() {
    _rankingWorker?.dispose();
    super.onClose();
  }
}
