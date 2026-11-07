import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:town_pass/gen/assets.gen.dart';
import 'package:town_pass/util/tp_button.dart';
import 'package:town_pass/util/tp_colors.dart';
import 'package:town_pass/util/tp_text.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// 兒童模式的撥號相關對話框，避免小孩誤觸直接撥出電話。
abstract final class ChildModeCallDialog {
  /// 撥打前先確認，例如 1999。
  static Future<void> confirm({required String number}) async {
    final bool? confirmed = await Get.dialog<bool>(
      _DialogFrame(
        title: '要打電話嗎？',
        subtitle: '確定要打電話給 $number 嗎？',
        children: [
          Row(
            children: [
              Expanded(
                child: TPButton.secondary(
                  text: '不要',
                  onPressed: () => Get.back(result: false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TPButton.primary(
                  text: '打電話',
                  onPressed: () => Get.back(result: true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await launchUrlString('tel://$number');
    }
  }

  /// 緊急求救：110 / 119 兩顆大按鈕，點了直接撥出。
  static Future<void> emergency() {
    return Get.dialog(
      _DialogFrame(
        title: '緊急求救',
        subtitle: '遇到危險時，請選擇要打給誰',
        children: [
          _EmergencyButton(
            icon: Assets.svg.icon110.svg(),
            number: '110',
            label: '警察',
            color: TPColors.primary500,
          ),
          const SizedBox(height: 12),
          _EmergencyButton(
            icon: Assets.svg.icon119.svg(),
            number: '119',
            label: '消防、救護車',
            color: TPColors.red500,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: TPButton.secondary(
              text: '取消',
              onPressed: () => Get.back(),
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogFrame extends StatelessWidget {
  const _DialogFrame({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: TPColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TPText(title, style: TPTextStyles.h2SemiBold, color: TPColors.grayscale950),
            const SizedBox(height: 8),
            TPText(
              subtitle,
              style: TPTextStyles.bodyRegular,
              color: TPColors.grayscale700,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _EmergencyButton extends StatelessWidget {
  const _EmergencyButton({
    required this.icon,
    required this.number,
    required this.label,
    required this.color,
  });

  final Widget icon;
  final String number;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '撥打 $number $label',
      excludeSemantics: true,
      child: Material(
        color: color,
        // 與 TPButton 相同的圓角
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Get.back();
            launchUrlString('tel://$number');
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(color: TPColors.white, shape: BoxShape.circle),
                  child: SizedBox.square(dimension: 32, child: icon),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TPText(number, style: TPTextStyles.h1SemiBold, color: TPColors.white),
                      TPText(label, style: TPTextStyles.bodySemiBold, color: TPColors.white),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
