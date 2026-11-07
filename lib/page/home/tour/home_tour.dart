import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:town_pass/gen/assets.gen.dart';
import 'package:town_pass/service/shared_preferences_service.dart';
import 'package:town_pass/service/translation_service.dart';
import 'package:town_pass/service/user_persona_service.dart';
import 'package:town_pass/util/tp_button.dart';
import 'package:town_pass/util/tp_colors.dart';
import 'package:town_pass/util/tp_text.dart';

/// 首頁導覽要指向的元件。
abstract final class HomeTourKeys {
  static final GlobalKey assistantButton = GlobalKey(debugLabel: 'tour_assistant');
  static final GlobalKey accountButton = GlobalKey(debugLabel: 'tour_account');

  /// 底部導覽列；「服務」分頁是其中最左邊的 1/4。
  static final GlobalKey bottomNavigation = GlobalKey(debugLabel: 'tour_bottom_navigation');
}

enum _TourLanguage { zh, en, ja, vi }

class _TourStep {
  const _TourStep({required this.icon, required this.text, required this.targetRect});

  final SvgGenImage icon;
  final Map<_TourLanguage, String> text;

  /// 目標在螢幕上的位置；找不到（元件未顯示）時回傳 null，該步驟會略過。
  final Rect? Function() targetRect;
}

/// 首頁導覽：第一次進入首頁時，以聚光燈依序指出重要按鈕，文字依使用者選的語言顯示。
abstract final class HomeTour {
  static const String _keyDone = 'home_tour_done';

  static OverlayEntry? _entry;

  static SharedPreferencesService get _preferences => Get.find<SharedPreferencesService>();

  static bool get isDone => _preferences.instance.getBool(_keyDone) ?? false;

  /// 重新選擇使用方式後再看一次（可能換了語言）。
  static Future<void> reset() => _preferences.instance.setBool(_keyDone, false);

  /// 尚未看過導覽時顯示。
  static void showIfNeeded() {
    if (isDone) return;
    show();
  }

  static void show() {
    if (_entry != null) return;
    final OverlayState? overlay = Get.key.currentState?.overlay;
    if (overlay == null) return;

    final List<_TourStep> steps = _steps().where((step) => step.targetRect() != null).toList();
    if (steps.isEmpty) return;

    _entry = OverlayEntry(
      builder: (_) => _TourOverlay(
        steps: steps,
        language: _language,
        onFinish: _finish,
      ),
    );
    overlay.insert(_entry!);
  }

  static void _finish() {
    _entry?.remove();
    _entry = null;
    _preferences.instance.setBool(_keyDone, true);
  }

  static _TourLanguage get _language {
    if (Get.find<UserPersonaService>().persona.value != UserPersona.foreign) {
      return _TourLanguage.zh;
    }
    return switch (Get.find<TranslationService>().targetLanguage.value) {
      TranslationLanguage.english => _TourLanguage.en,
      TranslationLanguage.japanese => _TourLanguage.ja,
      TranslationLanguage.vietnamese => _TourLanguage.vi,
    };
  }

  static List<_TourStep> _steps() {
    final UserPersona? persona = Get.find<UserPersonaService>().persona.value;
    return [
      // 「找服務」目前只能比對中文，外籍人士先不介紹
      if (persona != UserPersona.foreign)
        _TourStep(
          icon: Assets.svg.iconTalk,
          text: const {_TourLanguage.zh: '不知道去哪找？\n點這裡，打字說出你想做的事，就能找到服務。'},
          targetRect: () => _rectOf(HomeTourKeys.assistantButton),
        ),
      if (persona == UserPersona.simple)
        _TourStep(
          icon: Assets.svg.iconTabbarServiceSelect,
          text: const {_TourLanguage.zh: '所有服務都在「服務」這裡，\n已經換成大按鈕，比較好找。'},
          targetRect: () {
            final Rect? bar = _rectOf(HomeTourKeys.bottomNavigation);
            return bar == null ? null : Rect.fromLTWH(bar.left, bar.top, bar.width / 4, bar.height);
          },
        ),
      _TourStep(
        icon: Assets.svg.iconPerson,
        text: const {
          _TourLanguage.zh: '帳戶：可以開關簡易模式、\n改翻譯語言，或重新選擇使用方式。',
          _TourLanguage.en: 'Account: messages are translated automatically.\nChange the language or how you use the app here.',
          _TourLanguage.ja: 'アカウント：メッセージは自動で翻訳されます。\nここで言語や使い方を変更できます。',
          _TourLanguage.vi: 'Tài khoản: tin nhắn được dịch tự động.\nĐổi ngôn ngữ hoặc cách sử dụng tại đây.',
        },
        targetRect: () => _rectOf(HomeTourKeys.accountButton),
      ),
    ];
  }

  static Rect? _rectOf(GlobalKey key) {
    final RenderObject? renderObject = key.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize || !renderObject.attached) {
      return null;
    }
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }
}

const Map<_TourLanguage, ({String next, String done, String skip})> _buttonText = {
  _TourLanguage.zh: (next: '下一步', done: '開始使用', skip: '略過'),
  _TourLanguage.en: (next: 'Next', done: 'Got it', skip: 'Skip'),
  _TourLanguage.ja: (next: '次へ', done: 'はじめる', skip: 'スキップ'),
  _TourLanguage.vi: (next: 'Tiếp', done: 'Bắt đầu', skip: 'Bỏ qua'),
};

class _TourOverlay extends StatefulWidget {
  const _TourOverlay({required this.steps, required this.language, required this.onFinish});

  final List<_TourStep> steps;
  final _TourLanguage language;
  final VoidCallback onFinish;

  @override
  State<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<_TourOverlay> {
  int _index = 0;

  bool get _isLast => _index == widget.steps.length - 1;

  void _next() {
    if (_isLast) {
      widget.onFinish();
    } else {
      setState(() => _index++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final _TourStep step = widget.steps[_index];
    final Rect? target = step.targetRect()?.inflate(6);
    if (target == null) {
      // 目標在導覽期間消失（例如切換畫面），直接略過這一步
      WidgetsBinding.instance.addPostFrameCallback((_) => _next());
      return const SizedBox.shrink();
    }

    final Size screen = MediaQuery.sizeOf(context);
    final EdgeInsets safeArea = MediaQuery.paddingOf(context);
    // 目標在畫面下半部時，說明框放在目標上方
    final bool bubbleAbove = target.center.dy > screen.height / 2;
    final ({String next, String done, String skip}) buttons = _buttonText[widget.language]!;
    final String text = step.text[widget.language] ?? step.text[_TourLanguage.zh]!;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // 遮罩：擋住底下的操作，只留目標發亮
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: CustomPaint(painter: _SpotlightPainter(target)),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: bubbleAbove ? null : math.min(target.bottom + 12, screen.height - 260),
            bottom: bubbleAbove ? math.max(screen.height - target.top + 12, safeArea.bottom + 16) : null,
            child: _Bubble(
              icon: step.icon,
              text: text,
              current: _index,
              total: widget.steps.length,
              nextText: _isLast ? buttons.done : buttons.next,
              skipText: buttons.skip,
              onNext: _next,
              onSkip: widget.onFinish,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter(this.target);

  final Rect target;

  static const Radius _radius = Radius.circular(10);

  @override
  void paint(Canvas canvas, Size size) {
    final Path path = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(RRect.fromRectAndRadius(target, _radius)),
    );
    canvas.drawPath(path, Paint()..color = TPColors.grayscale950.withValues(alpha: 0.7));
    canvas.drawRRect(
      RRect.fromRectAndRadius(target, _radius),
      Paint()
        ..color = TPColors.secondary500
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) => oldDelegate.target != target;
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.icon,
    required this.text,
    required this.current,
    required this.total,
    required this.nextText,
    required this.skipText,
    required this.onNext,
    required this.onSkip,
  });

  final SvgGenImage icon;
  final String text;
  final int current;
  final int total;
  final String nextText;
  final String skipText;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      // 與 TPDialog 相同的圓角
      decoration: BoxDecoration(
        color: TPColors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(child: icon.svg(width: 40, height: 40)),
              const SizedBox(width: 12),
              Expanded(
                child: TPText(text, style: TPTextStyles.h3Regular, color: TPColors.grayscale900),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // 進度點
              for (int i = 0; i < total; i++)
                Container(
                  width: i == current ? 16 : 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: i == current ? TPColors.primary500 : TPColors.grayscale200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              const Spacer(),
              if (current < total - 1)
                TextButton(
                  onPressed: onSkip,
                  child: TPText(skipText, style: TPTextStyles.h3Regular, color: TPColors.grayscale500),
                ),
              const SizedBox(width: 4),
              TPButton.primary(text: nextText, onPressed: onNext),
            ],
          ),
        ],
      ),
    );
  }
}
