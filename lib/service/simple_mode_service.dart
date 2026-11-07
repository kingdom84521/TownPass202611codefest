import 'package:get/get.dart';
import 'package:town_pass/service/shared_preferences_service.dart';

/// 簡易模式：保留所有內容，只把功能服務改成大區塊（2x2 或條列）的易讀版面。
class SimpleModeService extends GetxService {
  static const String _keySimpleMode = 'simple_mode';

  final RxBool isEnabled = false.obs;

  SharedPreferencesService get _preferences => Get.find<SharedPreferencesService>();

  Future<SimpleModeService> init() async {
    isEnabled.value = _preferences.instance.getBool(_keySimpleMode) ?? false;
    return this;
  }

  Future<void> setEnabled(bool enabled) async {
    isEnabled.value = enabled;
    await _preferences.instance.setBool(_keySimpleMode, enabled);
  }
}
