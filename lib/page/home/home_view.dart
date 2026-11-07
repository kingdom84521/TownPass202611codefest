import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:town_pass/gen/assets.gen.dart';
import 'package:town_pass/page/home/tour/home_tour.dart';
import 'package:town_pass/page/home/widget/activity_info/activity_info_widget.dart';
import 'package:town_pass/page/home/widget/city_news/city_news_widget.dart';
import 'package:town_pass/page/home/widget/news/news_banner_widget.dart';
import 'package:town_pass/page/home/widget/subscription/subscription_widget.dart';
import 'package:town_pass/util/tp_app_bar.dart';
import 'package:town_pass/util/tp_colors.dart';
import 'package:town_pass/util/tp_route.dart';
import 'package:town_pass/util/tp_text.dart';

class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TPAppBar(
        showLogo: true,
        title: '首頁',
        leading: IconButton(
          key: HomeTourKeys.accountButton,
          icon: Semantics(
            label: '帳戶',
            child: Assets.svg.iconPerson.svg(),
          ),
          onPressed: () => Get.toNamed(TPRoute.account),
        ),
        actions: [
          TextButton(
            key: HomeTourKeys.childModeButton,
            onPressed: () => Get.toNamed(TPRoute.childMode),
            child: const TPText(
              '兒童模式',
              style: TPTextStyles.bodySemiBold,
              color: TPColors.primary500,
            ),
          ),
          const SizedBox(width: 4),
        ],
        backgroundColor: TPColors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: HomeTourKeys.assistantButton,
        onPressed: () => Get.toNamed(TPRoute.serviceAssistant),
        backgroundColor: TPColors.primary500,
        foregroundColor: TPColors.white,
        icon: const Icon(Icons.chat_bubble_outline_rounded),
        label: const TPText('找服務', style: TPTextStyles.h3SemiBold, color: TPColors.white),
        tooltip: '服務小幫手',
      ),
      body: const CustomScrollView(
        slivers: [
          _SliverGap(20),
          SliverToBoxAdapter(child: NewsBannerWidget()),
          _SliverGap(20),
          SliverToBoxAdapter(child: ActivityInfoWidget()),
          _SliverGap(8),
          SliverToBoxAdapter(child: CityNewsWidget()),
          _SliverGap(16),
          SliverToBoxAdapter(child: SubscriptionWidget()),
          // 預留浮動按鈕的空間，避免擋住最後一則訂閱
          _SliverGap(96),
        ],
      ),
    );
  }
}

class _SliverGap extends StatelessWidget {
  const _SliverGap(this.height);

  final double height;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(child: SizedBox(height: height));
  }
}