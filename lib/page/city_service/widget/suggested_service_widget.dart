import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:town_pass/page/city_service/model/my_service_model.dart';
import 'package:town_pass/page/city_service/widget/pinned_service_item_widget.dart';
import 'package:town_pass/page/city_service/widget/pinned_service_widget_controller.dart';
import 'package:town_pass/service/recommendation_service.dart';
import 'package:town_pass/util/tp_colors.dart';
import 'package:town_pass/util/tp_text.dart';

/// 「你可能需要」：依使用者特徵推薦、但還沒放進我的服務的服務，點了直接開啟。
/// 沒有推薦（新使用者，或推薦的都已在我的服務）時整段不顯示。
class SuggestedServiceWidget extends StatelessWidget {
  const SuggestedServiceWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final RecommendationService? recommendation = RecommendationService.maybe;
    if (recommendation == null) return const SizedBox.shrink();
    final PinnedServiceWidgetController pinned = Get.find<PinnedServiceWidgetController>();

    return Obx(() {
      final List<MyServiceItemId> services = recommendation.suggestedServices(pinned: pinned.pinnedList.toList());
      if (services.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TPText(
                '你可能需要',
                style: TPTextStyles.h3SemiBold.copyWith(fontSize: 18),
                color: TPColors.grayscale900,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                for (int i = 0; i < 4; i++)
                  Expanded(
                    child: i < services.length
                        ? PinnedServiceItemWidget(service: services[i].item)
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ],
        ),
      );
    });
  }
}
