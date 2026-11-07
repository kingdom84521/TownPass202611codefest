import 'dart:async';
import 'dart:convert';

import 'package:town_pass/bean/activity.dart';
import 'package:town_pass/gen/assets.gen.dart';
import 'package:town_pass/service/recommendation_service.dart';
import 'package:town_pass/service/user_traits/recommendation_targets.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class ActivityBannerWidgetController extends GetxController {
  bool _isLoading = false;

  bool get isLoading => _isLoading;

  set isLoading(bool value) {
    _isLoading = value;
    update();
  }

  ActivityList? list;

  @override
  void onInit() {
    super.onInit();

    _isLoading = true;

    Timer.periodic(
      const Duration(seconds: 2),
      (timer) async {
        timer.cancel();
        final String activityData = await rootBundle.loadString(Assets.mockData.activity);
        final ActivityList loaded = ActivityList.fromJson(jsonDecode(activityData));
        // 依使用者特徵排序；沒有特徵時維持原順序
        final RecommendationService? recommendation = RecommendationService.maybe;
        list = recommendation == null
            ? loaded
            : ActivityList(
                data: recommendation.rank(RecommendationSurface.homeActivity, loaded.data, titleOf: (a) => a.title),
              );
        isLoading = false;
      },
    );
  }
}
