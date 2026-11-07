import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:town_pass/gen/assets.gen.dart';
import 'package:town_pass/page/city_service/widget/official_service_card/official_service_card_widget.dart';
import 'package:town_pass/page/city_service/widget/pinned_service_widget.dart';
import 'package:town_pass/page/city_service/widget/simple_service_widget.dart';
import 'package:town_pass/page/city_service/widget/suggested_service_widget.dart';
import 'package:town_pass/page/city_service/widget/trending_service_widget.dart';
import 'package:town_pass/service/simple_mode_service.dart';
import 'package:town_pass/util/tp_app_bar.dart';
import 'package:town_pass/util/tp_colors.dart';
import 'package:town_pass/util/tp_route.dart';
import 'package:town_pass/util/tp_text.dart';

class CityServiceView extends StatelessWidget {
  const CityServiceView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TPColors.white,
      appBar: TPAppBar(
        showLogo: true,
        title: '服務',
        leading: IconButton(
          icon: Semantics(
            label: '帳戶',
            child: Assets.svg.iconPerson.svg(),
          ),
          onPressed: () => Get.toNamed(TPRoute.account),
        ),
      ),
      body: Obx(
        () => Get.find<SimpleModeService>().isEnabled.value ? _simpleBody() : _defaultBody(),
      ),
    );
  }

  /// 簡易模式：內容不變，改為 2 欄大區塊與條列區塊。
  Widget _simpleBody() {
    return ListView(
      physics: const BouncingScrollPhysics(),
      children: const [
        SimpleSectionTitle('我的服務'),
        SimplePinnedServiceWidget(),
        SimpleSectionTitle('官方服務'),
        SimpleOfficialServiceWidget(),
        SimpleSectionTitle('熱門'),
        SimpleTrendingServiceWidget(),
        SizedBox(height: 20),
      ],
    );
  }

  Widget _defaultBody() {
    return ListView(
      physics: const BouncingScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: _myServiceTitle(),
        ),
        PinnedServiceWidget(
          onMoreTap: () => Get.toNamed(TPRoute.serviceEdit),
        ),
        const SuggestedServiceWidget(),
        const SizedBox(height: 50),
        const OfficialServiceCardWidget(),
        const SizedBox(height: 20),
        const TrendingServiceWidget(),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _myServiceTitle() {
    return Semantics(
      explicitChildNodes: true,
      child: Row(
        children: [
          TPText(
            '我的服務',
            style: TPTextStyles.h3SemiBold.copyWith(fontSize: 18),
            color: TPColors.grayscale900,
          ),
          const Spacer(),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Get.toNamed(TPRoute.serviceEdit),
            child: Row(
              children: [
                const TPText(
                  '更多',
                  style: TPTextStyles.h3Regular,
                  color: TPColors.grayscale700,
                ),
                const SizedBox(width: 8.0),
                Assets.svg.iconExpand.svg(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
