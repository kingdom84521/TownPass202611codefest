import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:town_pass/service/translation_service.dart';
import 'package:town_pass/service/user_traits/user_trait_recorder.dart';
import 'package:town_pass/util/tp_app_bar.dart';
import 'package:town_pass/util/tp_colors.dart';
import 'package:town_pass/util/tp_setting_list.dart';
import 'package:town_pass/util/tp_text.dart';

/// 設定訂閱訊息「翻譯」按鈕要翻成的語言。
class TranslationLanguageView extends StatelessWidget {
  const TranslationLanguageView({super.key});

  TranslationService get _translationService => Get.find<TranslationService>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TPColors.white,
      appBar: const TPAppBar(title: '翻譯語言'),
      body: TPSettingList(
        children: [
          const TPSettingListTile(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TPText(
              '首頁訂閱訊息的「翻譯」按鈕會翻譯成此語言\nSubscription messages will be translated into this language',
              style: TPTextStyles.caption,
              color: TPColors.grayscale500,
            ),
          ),
          TPSettingListTile.selectionList(
            initialIndex: _translationService.targetLanguage.value.index,
            onIndexChange: (index) {
              final TranslationLanguage language = TranslationLanguage.values[index];
              _translationService.setTargetLanguage(language);
              // 主動選語言是很強的語言特徵，記下來給推薦用
              UserTraitRecorder().recordLanguageChoice(language.traitCode);
            },
            selections: TranslationLanguage.values
                .map((language) => SettingSelectionListItem(title: language.label))
                .toList(),
          ),
        ],
      ),
    );
  }
}
