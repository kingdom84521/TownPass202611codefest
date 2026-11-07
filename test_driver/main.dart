import 'package:flutter_driver/driver_extension.dart';
import 'package:town_pass/main.dart' as app;

/// Entry point for Dart MCP flutter_driver: `flutter run -t test_driver/main.dart`.
void main() {
  enableFlutterDriverExtension();
  app.main();
}
