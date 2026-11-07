import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:town_pass/bean/subscription.dart';
import 'package:town_pass/service/translation_service.dart';
import 'package:town_pass/util/tp_colors.dart';
import 'package:town_pass/util/tp_text.dart';

enum _TranslationState { loading, done, failed }

/// 訂閱詳情頁內容（標題、內容、日期），進入頁面即自動翻譯成帳戶中設定的「翻譯語言」，
/// 翻譯完成前先顯示原文；需要時可點「顯示原文」切回中文。
class SubscriptionTranslationWidget extends StatefulWidget {
  const SubscriptionTranslationWidget({super.key, required this.item});

  final SubscriptionItem item;

  @override
  State<SubscriptionTranslationWidget> createState() => _SubscriptionTranslationWidgetState();
}

class _SubscriptionTranslationWidgetState extends State<SubscriptionTranslationWidget> {
  TranslationService get _service => Get.find<TranslationService>();

  _TranslationState _state = _TranslationState.loading;
  bool _isDownloadingModel = false;
  bool _showOriginal = false;
  String? _title;
  String? _content;
  TranslationLanguage? _translatedLanguage;
  late final Worker _languageWorker;

  @override
  void initState() {
    super.initState();
    _translate();
    // 翻譯語言變更時自動重新翻譯
    _languageWorker = ever(_service.targetLanguage, (_) => _translate());
  }

  @override
  void dispose() {
    _languageWorker.dispose();
    super.dispose();
  }

  Future<void> _translate() async {
    final TranslationLanguage language = _service.targetLanguage.value;
    setState(() {
      _state = _TranslationState.loading;
      _isDownloadingModel = false;
    });

    try {
      final bool modelReady = await _service.isModelReady(language);
      if (!modelReady && mounted) setState(() => _isDownloadingModel = true);

      final List<String> results = await Future.wait([
        _service.translate(widget.item.title),
        _service.translate(widget.item.content),
      ]);
      // 翻譯期間語言又被切換，交給新的翻譯結果
      if (!mounted || language != _service.targetLanguage.value) return;
      setState(() {
        _title = results[0];
        _content = results[1];
        _translatedLanguage = language;
        _state = _TranslationState.done;
      });
    } catch (_) {
      if (mounted) setState(() => _state = _TranslationState.failed);
    }
  }

  bool get _showTranslation => _state == _TranslationState.done && !_showOriginal;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStatus(),
        const SizedBox(height: 12),
        TPText(
          _showTranslation ? _title : widget.item.title,
          style: TPTextStyles.titleSemiBold,
        ),
        const SizedBox(height: 12),
        TPText(
          _showTranslation ? _content : widget.item.content,
          style: TPTextStyles.bodyRegular,
        ),
        const SizedBox(height: 16),
        TPText(
          DateFormat('yyyy/MM/dd').format(widget.item.datetime),
          style: TPTextStyles.bodyRegular,
        ),
        if (_state == _TranslationState.done) ...[
          const SizedBox(height: 24),
          _showOriginal
              ? _TranslateButton(
                  text: '顯示翻譯 · Show translation',
                  icon: Icons.translate,
                  onPressed: () => setState(() => _showOriginal = false),
                )
              : _TranslateButton(
                  text: '顯示原文 · Show original',
                  icon: Icons.undo,
                  onPressed: () => setState(() => _showOriginal = true),
                ),
        ],
      ],
    );
  }

  /// 內容上方的翻譯狀態提示。
  Widget _buildStatus() {
    return switch (_state) {
      _TranslationState.loading => _StatusChip(
          leading: const SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: TPColors.primary500),
          ),
          text: _isDownloadingModel ? '首次使用，正在下載翻譯模型… Downloading model…' : '翻譯中… Translating…',
        ),
      _TranslationState.failed => GestureDetector(
          onTap: _translate,
          child: const _StatusChip(
            leading: Icon(Icons.refresh, size: 16, color: TPColors.red500),
            text: '翻譯失敗，點此重試 · Translation failed, tap to retry',
            color: TPColors.red500,
            backgroundColor: TPColors.red50,
          ),
        ),
      _TranslationState.done when _showOriginal => const _StatusChip(
          leading: Icon(Icons.article_outlined, size: 16, color: TPColors.grayscale600),
          text: '原文 · Original',
          color: TPColors.grayscale600,
          backgroundColor: TPColors.grayscale50,
        ),
      _TranslationState.done => _StatusChip(
          leading: const Icon(Icons.translate, size: 16, color: TPColors.primary600),
          text: '已翻譯為 ${_translatedLanguage!.label} · Translated',
        ),
    };
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.leading,
    required this.text,
    this.color = TPColors.primary600,
    this.backgroundColor = TPColors.primary50,
  });

  final Widget leading;
  final String text;
  final Color color;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 6),
          Flexible(child: TPText(text, style: TPTextStyles.caption, color: color)),
        ],
      ),
    );
  }
}

class _TranslateButton extends StatelessWidget {
  const _TranslateButton({
    required this.text,
    required this.icon,
    required this.onPressed,
  });

  final String text;
  final IconData icon;
  final VoidCallback onPressed;

  static const Color color = TPColors.primary500;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: color),
      label: TPText(text, style: TPTextStyles.bodySemiBold, color: color),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: const BorderSide(color: color),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
    );
  }
}
