import 'dart:convert';

import 'package:get/get.dart';
import 'package:town_pass/bean/subscription.dart';
import 'package:town_pass/service/shared_preferences_service.dart';

/// 訂閱主題與首頁的訂閱訊息（訊息內容是模擬資料）。
///
/// 已訂閱的主題存在手機上：重開 App 不會消失，同一主題重複訂閱也不會重複出現訊息。
/// 訂閱網頁（taipei-pass-service）另外用自己的 localStorage 記錄，開啟網頁時由
/// [subscriptionWebSyncScript] 把 App 這邊有、網頁沒有的主題補上。
class SubscriptionService extends GetxService {
  static const String _keySubscribedTitles = 'subscribed_titles';

  final RxList<SubscriptionItem> itemList = RxList();

  SharedPreferencesService? get _preferences =>
      Get.isRegistered<SharedPreferencesService>() ? Get.find<SharedPreferencesService>() : null;

  /// 已訂閱的主題（依訂閱順序）。
  List<String> get subscribedTitles => {for (final SubscriptionItem item in itemList) item.title}.toList();

  bool isSubscribed(String title) => itemList.any((item) => item.title == title);

  Future<SubscriptionService> init() async {
    final String? saved = _preferences?.instance.getString(_keySubscribedTitles);
    if (saved != null) {
      for (final dynamic title in jsonDecode(saved) as List<dynamic>) {
        if (title is String) itemList.addAll(_mockItems(title));
      }
    }
    return this;
  }

  /// 新增訂閱項目（已訂閱就不動作），預設產生兩筆測試用的模擬資料。
  void addSubscription({required String title}) {
    if (isSubscribed(title)) return;
    itemList.addAll(_mockItems(title));
    _save();
  }

  void removeSubscription({required String title}) {
    itemList.removeWhere((item) => item.title == title);
    _save();
  }

  List<SubscriptionItem> _mockItems(String title) {
    final now = DateTime.now();
    return [
      SubscriptionItem(
        title: title,
        content: '$title內容 ' * 20,
        datetime: now,
      ),
      SubscriptionItem(
        title: title,
        content: '$title內容2 ' * 20,
        datetime: now,
      ),
    ];
  }

  /// 把網頁記錄為已訂閱、App 還沒有的主題補進來（[subscriptionWebSyncScript] 的回傳值）。
  void mergeWebSubscriptions(Object? scriptResult) {
    if (scriptResult is! String) return;
    try {
      for (final dynamic title in jsonDecode(scriptResult) as List<dynamic>) {
        if (title is String && title.isNotEmpty) addSubscription(title: title);
      }
    } catch (_) {
      // 網頁格式不符就不同步
    }
  }

  void _save() => _preferences?.instance.setString(_keySubscribedTitles, jsonEncode(subscribedTitles));
}

/// 訂閱設定網頁與 App 雙向補齊（只補訂閱、不取消，取消一律由使用者在網頁上按）：
///
/// - App 有、網頁沒有：按下網頁自己的「訂閱」按鈕，讓網頁的紀錄與通知流程照常運作。
///   網頁是單頁應用，換頁後元件才出現，所以最多等 3 秒。
/// - 網頁有、App 沒有：腳本回傳網頁記錄的已訂閱主題（JSON 字串），由 [mergeWebSubscriptions] 補進 App。
String subscriptionWebSyncScript(List<String> titles) => '''
(function (titles) {
  var webSubscribed = [];
  try {
    JSON.parse(localStorage.getItem('subscriptionList') || '[]').forEach(function (item) {
      if (item && item.is_subscribed && typeof item.name === 'string') webSubscribed.push(item.name);
    });
  } catch (e) {}
  if (!titles.length) return JSON.stringify(webSubscribed);
  var tries = 0;
  (function run() {
    var wrappers = Array.prototype.slice.call(document.querySelectorAll('.subscription-wrapper'));
    if (!wrappers.length) { if (++tries < 30) setTimeout(run, 100); return; }
    wrappers.forEach(function (wrapper) {
      var header = wrapper.querySelector('.card-header span');
      var name = header ? header.textContent.trim() : '';
      if (titles.indexOf(name) < 0 || wrapper.classList.contains('active')) return;
      var button = Array.prototype.slice.call(wrapper.querySelectorAll('.card-button'))
        .filter(function (b) { return b.textContent.trim() === '訂閱'; })[0];
      if (button) button.click();
    });
  })();
  return JSON.stringify(webSubscribed);
})(${jsonEncode(titles)});
''';
