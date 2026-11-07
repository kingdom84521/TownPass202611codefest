import 'package:flutter/material.dart';
import 'package:town_pass/gen/assets.gen.dart';
import 'package:town_pass/util/tp_colors.dart';
import 'package:town_pass/util/tp_dialog.dart';
import 'package:town_pass/util/tp_route.dart';
import 'package:town_pass/util/tp_text.dart';

/// 開啟服務網址；demo 版尚未提供網址的服務顯示「敬請期待」，避免點了沒反應。
Future<void> openServiceOrComingSoon({
  required String uri,
  required String title,
  String? forceTitle,
}) async {
  if (uri.isNotEmpty) {
    await TPRoute.openUri(uri: uri, forceTitle: forceTitle ?? title);
    return;
  }
  await TPDialog.showInfo(
    title: '敬請期待',
    content: TPText('「$title」服務即將推出', textAlign: TextAlign.center),
  );
}

/// 與首頁「市政新聞」「1999」卡片相同的外框：白底、圓角 6、淡邊框與陰影。
const ShapeBorder _cardShape = RoundedRectangleBorder(
  side: BorderSide(width: 1, color: TPColors.grayscale50),
  borderRadius: BorderRadius.all(Radius.circular(6)),
);
const List<BoxShadow> _cardShadows = [
  BoxShadow(color: TPColors.grayscale100, blurRadius: 8, offset: Offset(0, 1)),
];

/// 可點擊的卡片外框，讓大區塊與 App 其他卡片一致。
class _TappableCard extends StatelessWidget {
  const _TappableCard({required this.onTap, required this.padding, required this.child});

  final VoidCallback onTap;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const ShapeDecoration(shape: _cardShape, shadows: _cardShadows),
      child: Material(
        color: TPColors.white,
        shape: _cardShape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          highlightColor: TPColors.primary50,
          splashColor: TPColors.primary50,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// 大區塊服務按鈕，用於 2x2 網格（簡易模式）。
class TPServiceBlock extends StatelessWidget {
  const TPServiceBlock({
    super.key,
    required this.title,
    required this.onTap,
    this.icon,
    this.description,
    this.titleColor = TPColors.grayscale800,
    this.iconSize = 48,
    this.descriptionMaxLines = 2,
  });

  final String title;
  final String? description;
  final Widget? icon;
  final VoidCallback onTap;

  /// 標題顏色；只有語意上需要強調時才改（例如緊急求救用紅色）。
  final Color titleColor;
  final double iconSize;
  final int descriptionMaxLines;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: [title, if (description != null) description].join('，'),
      excludeSemantics: true,
      child: _TappableCard(
        onTap: onTap,
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              SizedBox.square(dimension: iconSize, child: icon),
              const SizedBox(height: 12),
            ],
            TPText(
              title,
              style: TPTextStyles.h3SemiBold,
              color: titleColor,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (description != null) ...[
              const SizedBox(height: 4),
              TPText(
                description,
                style: TPTextStyles.bodyRegular,
                color: TPColors.grayscale600,
                textAlign: TextAlign.center,
                maxLines: descriptionMaxLines,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 2 欄的大區塊網格，內容不需捲動（放在外層可捲動的頁面中）。
class TPServiceBlockGrid extends StatelessWidget {
  const TPServiceBlockGrid({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.childAspectRatio = 1.0,
  });

  final List<Widget> children;
  final EdgeInsets padding;
  final double childAspectRatio;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: childAspectRatio,
      padding: padding,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: children,
    );
  }
}

/// 整列寬的條列式服務區塊：圖示＋標題（＋說明）＋箭頭。
class TPServiceListBlock extends StatelessWidget {
  const TPServiceListBlock({
    super.key,
    required this.title,
    required this.onTap,
    this.icon,
    this.description,
  });

  final String title;
  final String? description;
  final Widget? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: [title, if (description != null) description].join('，'),
      excludeSemantics: true,
      child: _TappableCard(
        onTap: onTap,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            if (icon != null) ...[
              SizedBox.square(dimension: 40, child: icon),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TPText(title, style: TPTextStyles.h3SemiBold, color: TPColors.grayscale800),
                  if (description != null)
                    TPText(description, style: TPTextStyles.bodyRegular, color: TPColors.grayscale600),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Assets.svg.iconExpand.svg(),
          ],
        ),
      ),
    );
  }
}
