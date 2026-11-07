import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:town_pass/service/recommendation_service.dart';
import 'package:town_pass/service/subscription_service.dart';
import 'package:town_pass/service/user_traits/demo_scenarios.dart';
import 'package:town_pass/service/user_traits/user_trait_repository.dart';
import 'package:town_pass/util/tp_app_bar.dart';
import 'package:town_pass/util/tp_colors.dart';
import 'package:town_pass/util/tp_route.dart';
import 'package:town_pass/util/tp_text.dart';

/// 示範題組：選一組人物，清空目前的特徵與訂閱，再到服務小幫手自動依序提問，
/// 問完回首頁就能看到這組對應的推薦（題目與預期結果見 [DemoScenario]）。
class DemoScenariosView extends StatelessWidget {
  const DemoScenariosView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TPColors.grayscale50,
      appBar: const TPAppBar(title: '示範題組'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const TPText(
            '選一組人物：會先清空目前的使用者特徵與訂閱，再自動到服務小幫手依序提問。'
            '問完回首頁，就能看到這組對應的推薦。',
            style: TPTextStyles.bodyRegular,
            color: TPColors.grayscale600,
          ),
          const SizedBox(height: 16),
          for (final DemoScenario scenario in DemoScenario.all) ...[
            _ScenarioCard(scenario: scenario),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _ScenarioCard extends StatelessWidget {
  const _ScenarioCard({required this.scenario});

  final DemoScenario scenario;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TPColors.white,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _run(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: TPText(scenario.name, style: TPTextStyles.h3SemiBold, color: TPColors.grayscale900)),
                  const Icon(Icons.play_circle_outline, color: TPColors.primary500),
                ],
              ),
              const SizedBox(height: 4),
              TPText(scenario.description, style: TPTextStyles.bodyRegular, color: TPColors.primary600),
              const SizedBox(height: 8),
              for (int i = 0; i < scenario.questions.length; i++)
                TPText('${i + 1}. ${scenario.questions[i]}', style: TPTextStyles.bodyRegular, color: TPColors.grayscale700),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _run(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: TPText('開始「${scenario.name}」', style: TPTextStyles.h3SemiBold),
        content: const TPText('會清空目前的使用者特徵與訂閱（只限這支手機），確定嗎？', style: TPTextStyles.bodyRegular),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('開始')),
        ],
      ),
    );
    if (confirmed != true) return;
    await resetForDemo();
    await Get.toNamed(TPRoute.serviceAssistant, arguments: DemoRun(scenario.questions));
  }
}

/// 帶給服務小幫手的參數：進入後自動依序問這些問題。
class DemoRun {
  const DemoRun(this.questions);

  final List<String> questions;
}

/// 清空使用者特徵（含「不再推薦」清單）與 App 內的訂閱，回到「什麼都沒有」的狀態。
Future<void> resetForDemo() async {
  await (await UserTraitRepository.shared()).clear();
  if (Get.isRegistered<SubscriptionService>()) {
    final SubscriptionService subscriptions = Get.find<SubscriptionService>();
    for (final String title in subscriptions.subscribedTitles) {
      subscriptions.removeSubscription(title: title);
    }
  }
  await RecommendationService.maybe?.reload();
}
