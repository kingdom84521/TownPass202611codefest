import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:town_pass/gen/assets.gen.dart';
import 'package:town_pass/page/child_mode/widget/child_mode_call_dialog.dart';
import 'package:town_pass/page/child_mode/widget/child_mode_pin_dialog.dart';
import 'package:town_pass/page/city_service/model/my_service_model.dart';
import 'package:town_pass/util/tp_app_bar.dart';
import 'package:town_pass/util/tp_colors.dart';
import 'package:town_pass/util/tp_route.dart';
import 'package:town_pass/util/tp_service_block.dart';
import 'package:town_pass/util/tp_text.dart';

class ChildModeView extends StatelessWidget {
  const ChildModeView({super.key});

  static final List<_ChildModeEntry> _entries = [
    _ChildModeEntry(
      title: '緊急求救',
      icon: Assets.svg.icon110.svg(),
      // 唯一需要語意色的項目，用紅色標題讓小孩一眼找到
      titleColor: TPColors.red600,
      onTap: ChildModeCallDialog.emergency,
    ),
    _ChildModeEntry(
      title: '1999',
      icon: Assets.svg.icon1999.svg(),
      onTap: () => ChildModeCallDialog.confirm(number: '1999'),
    ),
    _ChildModeEntry(
      title: '圖書借閱',
      icon: MyServiceItemId.library.item.icon,
      uri: MyServiceItemId.library.item.destinationUrl,
    ),
    _ChildModeEntry(
      title: '找地點',
      icon: MyServiceItemId.locationSearch.item.icon,
      uri: MyServiceItemId.locationSearch.item.destinationUrl,
    ),
    _ChildModeEntry(
      title: '愛遊動物園',
      icon: MyServiceItemId.zoo.item.icon,
      uri: MyServiceItemId.zoo.item.destinationUrl,
    ),
  ];

  Future<void> _exitChildMode() async {
    if (await ChildModePinDialog.show()) {
      Get.back();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 禁止系統返回鍵／手勢直接離開，必須通過家長 PIN 碼驗證
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitChildMode();
      },
      child: Scaffold(
        backgroundColor: TPColors.grayscale50,
        appBar: TPAppBar(
          showLogo: true,
          title: '兒童模式',
          leading: IconButton(
            icon: Semantics(
              label: '帳戶',
              child: Assets.svg.iconPerson.svg(),
            ),
            onPressed: () => Get.toNamed(TPRoute.account),
          ),
          actions: [
            TextButton(
              onPressed: _exitChildMode,
              child: const TPText(
                '離開',
                style: TPTextStyles.bodySemiBold,
                color: TPColors.primary500,
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: SafeArea(
          child: GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            padding: const EdgeInsets.all(16),
            children: [
              for (final entry in _entries)
                TPServiceBlock(
                  icon: entry.icon,
                  title: entry.title,
                  iconSize: 56,
                  titleColor: entry.titleColor,
                  onTap: entry.open,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChildModeEntry {
  const _ChildModeEntry({
    required this.title,
    required this.icon,
    this.titleColor = TPColors.grayscale800,
    this.uri,
    this.onTap,
  }) : assert(uri != null || onTap != null);

  final String title;
  final Widget? icon;
  final Color titleColor;
  final String? uri;
  final VoidCallback? onTap;

  void open() {
    if (onTap != null) {
      onTap!();
    } else {
      openServiceOrComingSoon(uri: uri!, title: title);
    }
  }
}
