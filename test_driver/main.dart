import 'package:flutter_driver/driver_extension.dart';
import 'package:town_pass/main.dart' as app;

/// Entry point for Dart MCP flutter_driver: `flutter run -t test_driver/main.dart`.
///
/// 文字輸入模擬預設關閉：開著時會攔截系統鍵盤，模擬器上手動打字沒反應。
/// 需要用 flutter_driver 的 enter_text 時，先下 set_text_entry_emulation（enabled: true）臨時打開。
void main() {
  enableFlutterDriverExtension(enableTextEntryEmulation: false);
  app.main();
}
