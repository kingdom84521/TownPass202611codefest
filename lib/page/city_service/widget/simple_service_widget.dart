import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:town_pass/gen/assets.gen.dart';
import 'package:town_pass/page/city_service/model/my_service_model.dart';
import 'package:town_pass/page/city_service/model/trending_service_model.dart';
import 'package:town_pass/page/city_service/widget/pinned_service_widget_controller.dart';
import 'package:town_pass/util/tp_colors.dart';
import 'package:town_pass/util/tp_route.dart';
import 'package:town_pass/util/tp_service_block.dart';
import 'package:town_pass/util/tp_text.dart';

// 簡易模式下「服務」頁的各區塊：內容與一般模式相同，只換成大區塊版面。

/// 我的服務：2 欄大區塊，最後一格為「新增服務」。
class SimplePinnedServiceWidget extends GetView<PinnedServiceWidgetController> {
  const SimplePinnedServiceWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => TPServiceBlockGrid(
        childAspectRatio: 1.1,
        children: [
          for (final MyServiceItemId itemId in controller.pinnedList)
            TPServiceBlock(
              icon: itemId.item.icon,
              title: itemId.item.title,
              description: itemId.item.description,
              onTap: () => openServiceOrComingSoon(
                uri: itemId.item.destinationUrl,
                title: itemId.item.title,
                forceTitle: itemId.item.forceWebViewTitle,
              ),
            ),
          TPServiceBlock(
            icon: Assets.svg.iconAdd.svg(),
            title: '新增服務',
            backgroundColor: TPColors.grayscale50,
            onTap: () => Get.toNamed(TPRoute.serviceEdit),
          ),
        ],
      ),
    );
  }
}

/// 官方服務：一般模式中大小不一的 4 張卡片，攤平成 6 個等大區塊。
class SimpleOfficialServiceWidget extends StatelessWidget {
  const SimpleOfficialServiceWidget({super.key});

  @override
  Widget build(BuildContext context) {
    // 與 OfficialServiceCard 各卡片的內容與連結保持一致
    final List<({String title, String subtitle, Widget icon, String uri})> services = [
      (title: '市政服務', subtitle: 'Service', icon: Assets.svg.illustrationsGov.svg(), uri: ''),
      (
        title: '有話要說',
        subtitle: '1999',
        icon: Assets.svg.iconTalk.svg(),
        uri: 'https://taipei-pass-service.vercel.app/citizen-report/',
      ),
      (title: '警政報案', subtitle: 'Police', icon: Assets.svg.iconPolice.svg(), uri: 'local://online_police'),
      (title: '城市生活', subtitle: 'City Life', icon: Assets.svg.illustrationsChair.svg(), uri: ''),
      (title: '防疫醫療', subtitle: 'Health', icon: Assets.svg.iconCovidMedical.svg(), uri: ''),
      (title: '市政APP', subtitle: 'More', icon: Assets.svg.iconMore.svg(), uri: ''),
    ];

    return TPServiceBlockGrid(
      childAspectRatio: 1.2,
      children: [
        for (final service in services)
          TPServiceBlock(
            icon: service.icon,
            title: service.title,
            description: service.subtitle,
            backgroundColor: TPColors.primary50,
            borderColor: TPColors.primary200,
            onTap: () => openServiceOrComingSoon(uri: service.uri, title: service.title),
          ),
      ],
    );
  }
}

/// 熱門：條列式大區塊。
class SimpleTrendingServiceWidget extends StatelessWidget {
  const SimpleTrendingServiceWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (final TrendingService service in TrendingServiceModel.serviceList) ...[
            TPServiceListBlock(
              icon: service.icon,
              title: service.title,
              onTap: () => openServiceOrComingSoon(
                uri: service.url,
                title: service.title,
                forceTitle: service.forceWebViewTitle,
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

/// 簡易模式的區塊標題。
class SimpleSectionTitle extends StatelessWidget {
  const SimpleSectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Semantics(
        header: true,
        child: TPText(
          title,
          style: TPTextStyles.h2SemiBold,
          color: TPColors.grayscale900,
        ),
      ),
    );
  }
}
