import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:town_pass/util/tp_button.dart';
import 'package:town_pass/util/tp_colors.dart';
import 'package:town_pass/util/tp_text.dart';

/// 家長 PIN 碼驗證對話框（進入／離開兒童模式）。
/// 驗證成功回傳 `true`，取消或關閉回傳 `null`。
class ChildModePinDialog extends StatefulWidget {
  const ChildModePinDialog({super.key, this.message = defaultMessage});

  static const String defaultMessage = '請輸入 PIN 碼以離開兒童模式';

  final String message;

  // TODO: 之後改為家長可自行設定的 PIN 碼
  static const String _parentPin = '0000';
  static const int _pinLength = 4;

  static Future<bool> show({String message = defaultMessage}) async {
    final bool? verified = await Get.dialog<bool>(
      ChildModePinDialog(message: message),
      barrierDismissible: false,
    );
    return verified ?? false;
  }

  @override
  State<ChildModePinDialog> createState() => _ChildModePinDialogState();
}

class _ChildModePinDialogState extends State<ChildModePinDialog> {
  final TextEditingController _pinController = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_pinController.text == ChildModePinDialog._parentPin) {
      Get.back(result: true);
      return;
    }
    setState(() => _errorText = 'PIN 碼錯誤，請再試一次');
    _pinController.clear();
  }

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
            const TPText(
              '家長驗證',
              style: TPTextStyles.h2SemiBold,
              color: TPColors.grayscale950,
            ),
            const SizedBox(height: 8),
            TPText(
              widget.message,
              style: TPTextStyles.bodyRegular,
              color: TPColors.grayscale700,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _pinController,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: ChildModePinDialog._pinLength,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: TPTextStyles.h2SemiBold.copyWith(letterSpacing: 16),
              decoration: InputDecoration(
                counterText: '',
                errorText: _errorText,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: TPColors.primary500, width: 2),
                ),
              ),
              onChanged: (value) {
                if (_errorText != null) setState(() => _errorText = null);
                if (value.length == ChildModePinDialog._pinLength) _submit();
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TPButton.secondary(
                    text: '取消',
                    onPressed: () => Get.back(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TPButton.primary(
                    text: '確認',
                    onPressed: _submit,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
