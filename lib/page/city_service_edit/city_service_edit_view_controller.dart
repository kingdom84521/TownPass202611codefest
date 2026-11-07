import 'package:get/get.dart';
import 'package:town_pass/page/city_service/model/my_service_model.dart';
import 'package:town_pass/page/city_service/widget/pinned_service_widget_controller.dart';
import 'package:town_pass/service/user_traits/recommendation_targets.dart';
import 'package:town_pass/service/user_traits/user_trait_recorder.dart';

class CityServiceEditViewController extends GetxController {
  final Map<MyServiceCategory, List<MyServiceItemId>> categoryMap = {
    for (var category in MyServiceCategory.values)
      category: MyServiceItemId.values
          .where(
            (itemId) => itemId.item.category == category,
          )
          .toList(),
  }..removeWhere(
      (category, serviceList) => serviceList.isEmpty,
    );

  final RxBool isEditMode = RxBool(false);

  PinnedServiceWidgetController get pinnedServiceController => Get.find<PinnedServiceWidgetController>();

  List<MyServiceItemId>? _recordPinnedList;

  @override
  void onInit() {
    super.onInit();
    isEditMode.listen((isEditMode) {
      if (isEditMode) {
        _recordPinnedList = List.of(pinnedServiceController.pinnedList);
      } else if (_recordPinnedList != null) {
        // 按「完成」：比較編輯前後，加進來的算明確選擇、移除的算明確拒絕（取消編輯不算）
        _recordChanges(before: _recordPinnedList!, after: pinnedServiceController.pinnedList);
        _recordPinnedList = null;
      }
    });
  }

  void cancelEdit() {
    if (_recordPinnedList != null) {
      Get.find<PinnedServiceWidgetController>().replaceWith(_recordPinnedList!);
      _recordPinnedList = null;
    }
    isEditMode.value = false;
  }

  static void _recordChanges({required List<MyServiceItemId> before, required List<MyServiceItemId> after}) {
    final UserTraitRecorder recorder = UserTraitRecorder();
    for (final MyServiceItemId added in after.where((id) => !before.contains(id))) {
      recorder.recordChoice(RecommendationSurface.service, added.item.title, chosen: true);
    }
    for (final MyServiceItemId removed in before.where((id) => !after.contains(id))) {
      recorder.recordChoice(RecommendationSurface.service, removed.item.title, chosen: false);
    }
  }
}
