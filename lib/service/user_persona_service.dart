import 'package:get/get.dart';
import 'package:town_pass/service/shared_preferences_service.dart';

/// 使用者在「我是誰」選擇頁選的使用方式。
enum UserPersona {
  /// 一般使用，維持原本介面。
  general,

  /// 外籍人士：設定翻譯語言。
  foreign,

  /// 簡單好用：開啟簡易模式（大區塊服務）。
  simple,

  /// 兒童：每次開啟 App 都進入兒童模式。
  child,
  ;
}

class UserPersonaService extends GetxService {
  static const String _keyUserPersona = 'user_persona';

  /// 尚未選擇時為 null，開啟 App 會先進入「我是誰」選擇頁。
  final Rxn<UserPersona> persona = Rxn<UserPersona>();

  SharedPreferencesService get _preferences => Get.find<SharedPreferencesService>();

  bool get hasChosen => persona.value != null;

  Future<UserPersonaService> init() async {
    final String? saved = _preferences.instance.getString(_keyUserPersona);
    persona.value = UserPersona.values.firstWhereOrNull((value) => value.name == saved);
    return this;
  }

  Future<void> setPersona(UserPersona value) async {
    persona.value = value;
    await _preferences.instance.setString(_keyUserPersona, value.name);
  }
}
