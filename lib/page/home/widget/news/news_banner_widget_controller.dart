import 'dart:async';
import 'dart:convert';

import 'package:carousel_slider/carousel_controller.dart';
import 'package:town_pass/bean/home_banner.dart';
import 'package:town_pass/gen/assets.gen.dart';
import 'package:town_pass/service/recommendation_service.dart';
import 'package:town_pass/service/user_traits/recommendation_targets.dart';
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

  @override
  void onInit() {
    super.onInit();

    Timer.periodic(
      const Duration(seconds: 3),
      (timer) async {
        timer.cancel();
        final String banners = await rootBundle.loadString(Assets.mockData.homeBanner);
        final HomeBannerList loaded = HomeBannerList.fromJson(jsonDecode(banners));
        // 依使用者特徵排序；沒有特徵時維持原順序
        final RecommendationService? recommendation = RecommendationService.maybe;
        list = recommendation == null
            ? loaded
            : HomeBannerList(
                data: recommendation.rank(RecommendationSurface.homeBanner, loaded.data, titleOf: (b) => b.title),
              );
        isLoading = false;
      },
    );
  }
}
