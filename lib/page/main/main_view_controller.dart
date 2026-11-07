import 'package:get/get.dart';
import 'package:town_pass/service/shared_preferences_service.dart';
import 'package:flutter/widgets.dart';
import 'package:town_pass/page/home/tour/home_tour.dart';
import 'package:town_pass/util/tp_bottom_navigation_factory.dart';

class MainViewController extends GetxController {
  final RxInt currentIndex = RxInt(
    switch (SharedPreferencesService().instance.getInt(SharedPreferencesService.keyHomeIndex)) {
      int sharedPreferencesIndex => sharedPreferencesIndex,
      null => TPBottomNavigationFactory.defaultIndex,
    },
  );

  @override
  void onReady() {
    super.onReady();
    if (!HomeTour.isDone) {
      showHomeTour();
    }
  }

  /// 切到首頁分頁後顯示首頁導覽。
  void showHomeTour() {
    currentIndex.value = TPBottomNavigationFactory.defaultIndex;
    // 等首頁版面完成後再顯示，才能取得按鈕位置
    WidgetsBinding.instance.addPostFrameCallback((_) => HomeTour.show());
  }
}
