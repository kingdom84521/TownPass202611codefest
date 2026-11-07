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
      backgroundColor: TPColors.red50,
      borderColor: TPColors.red300,
      onTap: ChildModeCallDialog.emergency,
    ),
    _ChildModeEntry(
      title: '1999',
      icon: Assets.svg.icon1999.svg(),
      backgroundColor: TPColors.primary50,
      borderColor: TPColors.primary300,
      onTap: () => ChildModeCallDialog.confirm(number: '1999'),
    ),
    _ChildModeEntry(
      title: '圖書借閱',
      icon: MyServiceItemId.library.item.icon,
      backgroundColor: TPColors.secondary50,
      borderColor: TPColors.secondary300,
      uri: MyServiceItemId.library.item.destinationUrl,
    ),
    _ChildModeEntry(
      title: '找地點',
      icon: MyServiceItemId.locationSearch.item.icon,
      backgroundColor: TPColors.orange50,
      borderColor: TPColors.orange300,
      uri: MyServiceItemId.locationSearch.item.destinationUrl,
    ),
    _ChildModeEntry(
      title: '愛遊動物園',
      icon: MyServiceItemId.zoo.item.icon,
      backgroundColor: TPColors.grayscale50,
      borderColor: TPColors.grayscale200,
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
        backgroundColor: TPColors.white,
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
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            padding: const EdgeInsets.all(20),
            children: [
              for (final entry in _entries)
                TPServiceBlock(
                  icon: entry.icon,
                  title: entry.title,
                  iconSize: 56,
                  backgroundColor: entry.backgroundColor,
                  borderColor: entry.borderColor,
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
    required this.backgroundColor,
    required this.borderColor,
    this.uri,
    this.onTap,
  }) : assert(uri != null || onTap != null);

  final String title;
  final Widget? icon;
  final Color backgroundColor;
  final Color borderColor;
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
