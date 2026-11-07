import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:town_pass/service/shared_preferences_service.dart';
import 'package:town_pass/service/subscription_service.dart';

void main() {
  setUp(() async {
    Get.reset();
    SharedPreferences.setMockInitialValues({});
    await Get.putAsync<SharedPreferencesService>(() => SharedPreferencesService().init());
  });

  test('重複訂閱同一主題不會多出訊息', () async {
    final SubscriptionService service = await SubscriptionService().init();
    service.addSubscription(title: '停車費通知');
    service.addSubscription(title: '停車費通知'); // 例如先從推薦訂閱，再到網頁訂閱一次
    expect(service.itemList, hasLength(2));
    expect(service.subscribedTitles, ['停車費通知']);
  });

  test('已訂閱的主題重開 App 後還在；取消後消失', () async {
    final SubscriptionService first = await SubscriptionService().init();
    first.addSubscription(title: '停車費通知');
    first.addSubscription(title: '交通措施');

    final SubscriptionService reopened = await SubscriptionService().init();
    expect(reopened.subscribedTitles, ['停車費通知', '交通措施']);

    reopened.removeSubscription(title: '停車費通知');
    expect((await SubscriptionService().init()).subscribedTitles, ['交通措施']);
  });

  test('網頁記錄為已訂閱的主題補進 App（不重複，格式不對就略過）', () async {
    final SubscriptionService service = await SubscriptionService().init();
    service.addSubscription(title: '停車費通知');
    service.mergeWebSubscriptions('["銀髮資訊","停車費通知"]');
    expect(service.subscribedTitles, ['停車費通知', '銀髮資訊']);
    expect(service.itemList, hasLength(4));
    service.mergeWebSubscriptions('not json');
    service.mergeWebSubscriptions(null);
    expect(service.subscribedTitles, ['停車費通知', '銀髮資訊']);
  });

  test('網頁同步腳本只補訂閱，帶入的是 App 已訂閱的主題', () {
    final String script = subscriptionWebSyncScript(['停車費通知']);
    expect(script, contains('["停車費通知"]'));
    expect(script, contains("=== '訂閱'"));
    expect(script, isNot(contains('取消訂閱')));
  });
}
