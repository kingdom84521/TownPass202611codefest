import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:town_pass/bean/subscription.dart';
import 'package:town_pass/page/subscription/widget/subscription_translation_widget.dart';
import 'package:town_pass/util/tp_app_bar.dart';
import 'package:town_pass/util/tp_colors.dart';

class SubscriptionView extends StatelessWidget {
  SubscriptionItem get subscription => Get.arguments;

  const SubscriptionView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const TPAppBar(title: '訂閱'),
      backgroundColor: TPColors.white,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8.0),
              SubscriptionTranslationWidget(item: subscription),
              const SizedBox(height: 32.0),
            ],
          ),
        ),
      ),
    );
  }
}
