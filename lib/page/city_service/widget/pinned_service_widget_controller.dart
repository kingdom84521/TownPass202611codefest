import 'package:get/get.dart';
import 'package:town_pass/page/city_service/model/my_service_model.dart';
import 'package:town_pass/service/recommendation_service.dart';

class PinnedServiceWidgetController extends GetxController {
  static const List<MyServiceItemId> defaultPinned = [
    MyServiceItemId.locationSearch,
    MyServiceItemId.districtOffice,
    MyServiceItemId.dashboard,
  ];

  // 初始清單：依使用者特徵推薦的服務放前面，再用預設補滿；沒有特徵時就是預設。
  // 建立後不再自動變動，避免使用者自己排好的順序被打亂。
  final RxList<MyServiceItemId> _pinnedList = RxList(
    RecommendationService.maybe?.pinnedServices(defaultPinned) ?? List.of(defaultPinned),
  );

  RxList<MyServiceItemId> get pinnedList => _pinnedList;

  bool remove(MyServiceItemId itemId) {
    return _pinnedList.remove(itemId);
  }

  bool replaceWith(List<MyServiceItemId> list) {
    if (list.isNotEmpty) {
      _pinnedList.value = list;
      return true;
    }
    return false;
  }

  bool push(MyServiceItemId itemId) {
    if (_pinnedList.length < 12) {
      _pinnedList.add(itemId);
      return true;
    }
    return false;
  }
}
