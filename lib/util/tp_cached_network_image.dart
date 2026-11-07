import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:town_pass/gen/assets.gen.dart';
import 'package:town_pass/util/tp_colors.dart';

class TPCachedNetworkImage extends StatelessWidget {
  final String imageUrl;
  final Map<String, String>? httpHeaders;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Color? color;
  final double borderRadius;

  const TPCachedNetworkImage({
    super.key,
    required this.imageUrl,
    this.httpHeaders,
    this.width,
    this.height,
    this.fit,
    this.color = TPColors.white,
    this.borderRadius = 6,
  });

  @override
  Widget build(BuildContext context) {
    return _buildContainer();
  }

  Widget _buildContainer() {
    return Container(
      width: width,
      height: height,
      // 設定容器的背景顏色和外框圓角，在圖片載入中或錯誤時可見。
      decoration: ShapeDecoration(
        color: color,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius)),
      ),
      child: ClipRRect( // 確保圖片內容（包含載入中及錯誤狀態）也依照圓角進行裁切。
        borderRadius: BorderRadius.circular(borderRadius),
        child: tpImage(
          imageUrl,
          httpHeaders: httpHeaders,
          width: double.infinity,
          height: double.infinity,
          fit: fit,
          placeholder: const Center(child: CircularProgressIndicator()),
          error: ColoredBox(
            color: TPColors.grayscale100,
            child: Center(
              child: Assets.svg.logoS.svg(),
            ),
          ),
        ),
      ),
    );
  }
}

/// 顯示圖片：`assets/` 開頭用 App 內建的圖（示範資料用，.svg 或點陣圖），其餘當作網址載入。
Widget tpImage(
  String url, {
  Map<String, String>? httpHeaders,
  double? width,
  double? height,
  BoxFit? fit,
  Widget? placeholder,
  Widget? error,
}) {
  if (url.startsWith('assets/')) {
    return url.endsWith('.svg')
        ? SvgPicture.asset(url, width: width, height: height, fit: fit ?? BoxFit.contain)
        : Image.asset(url, width: width, height: height, fit: fit);
  }
  return CachedNetworkImage(
    imageUrl: url,
    httpHeaders: httpHeaders,
    width: width,
    height: height,
    fit: fit,
    placeholder: placeholder == null ? null : (_, __) => placeholder,
    errorWidget: error == null ? null : (_, __, ___) => error,
  );
}