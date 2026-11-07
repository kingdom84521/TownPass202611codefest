import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:town_pass/gen/assets.gen.dart';
import 'package:town_pass/page/home/tour/home_tour.dart';
import 'package:town_pass/service/simple_mode_service.dart';
import 'package:town_pass/service/translation_service.dart';
import 'package:town_pass/service/user_persona_service.dart';
import 'package:town_pass/util/tp_app_bar.dart';
import 'package:town_pass/util/tp_colors.dart';
import 'package:town_pass/util/tp_route.dart';
import 'package:town_pass/util/tp_service_block.dart';
import 'package:town_pass/util/tp_text.dart';

/// 「我是誰」選擇頁：用圖像與多國語言標示，讓看不懂中文或不熟悉 App 的人也能選。
/// 第一次開啟 App 時顯示，之後可從帳戶頁「重新選擇使用方式」進入。
class PersonaSelectView extends StatefulWidget {
  const PersonaSelectView({super.key});

  @override
  State<PersonaSelectView> createState() => _PersonaSelectViewState();
}

class _PersonaSelectViewState extends State<PersonaSelectView> {
  UserPersonaService get _personaService => Get.find<UserPersonaService>();

  /// 第一次開啟 App（尚未選過）時沒有返回鍵。
  late final bool _isFirstLaunch = !_personaService.hasChosen;

  /// 選了「Foreign visitor」後的第二步：選語言。
  bool _isChoosingLanguage = false;

  Future<void> _onPersonaTap(UserPersona persona) async {
    switch (persona) {
      case UserPersona.foreign:
        setState(() => _isChoosingLanguage = true);
      case UserPersona.general || UserPersona.simple:
        await _finish(persona);
    }
  }

  Future<void> _onLanguageTap(TranslationLanguage language) async {
    await Get.find<TranslationService>().setTargetLanguage(language);
    await _finish(UserPersona.foreign);
  }

  Future<void> _finish(UserPersona persona) async {
    await _personaService.setPersona(persona);
    // 換了使用方式（可能也換了語言），首頁導覽重新顯示一次
    await HomeTour.reset();
    await Get.find<SimpleModeService>().setEnabled(persona == UserPersona.simple);
    await Get.offAllNamed(TPRoute.main);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 第二步可用返回鍵回到第一步；第一次開啟時不可略過
      canPop: !_isChoosingLanguage && !_isFirstLaunch,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isChoosingLanguage) setState(() => _isChoosingLanguage = false);
      },
      child: Scaffold(
        backgroundColor: TPColors.grayscale50,
        appBar: TPAppBar(
          leading: switch ((_isChoosingLanguage, _isFirstLaunch)) {
            (true, _) => BackButton(onPressed: () => setState(() => _isChoosingLanguage = false)),
            (false, false) => const BackButton(),
            (false, true) => const SizedBox.shrink(),
          },
        ),
        body: SafeArea(
          top: false,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _isChoosingLanguage ? _buildLanguageStep() : _buildPersonaStep(),
          ),
        ),
      ),
    );
  }

  Widget _buildPersonaStep() {
    return ListView(
      key: const ValueKey('persona'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _Header(
          icon: Assets.svg.logoS.svg(),
          title: '歡迎使用・Welcome',
          subtitle: 'ようこそ・Xin chào\n請選擇使用方式・Choose how to use',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              TPServiceListBlock(
                icon: Assets.svg.iconPerson.svg(),
                title: '一般使用',
                description: 'Standard',
                onTap: () => _onPersonaTap(UserPersona.general),
              ),
              const SizedBox(height: 12),
              TPServiceListBlock(
                icon: Assets.svg.iconExploreTaipei.svg(),
                title: 'Foreign visitor',
                description: '外籍人士・外国の方・Người nước ngoài',
                onTap: () => _onPersonaTap(UserPersona.foreign),
              ),
              const SizedBox(height: 12),
              TPServiceListBlock(
                // icon_more 的 viewBox 內留白較多，放大到與其他 24 規格圖示一致
                icon: Transform.scale(scale: 2, child: Assets.svg.iconMore.svg()),
                title: '簡單好用',
                description: '大按鈕、好找服務・Easy mode',
                onTap: () => _onPersonaTap(UserPersona.simple),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: TPText(
            '之後可在「帳戶」中重新選擇\nYou can change this later in Account',
            style: TPTextStyles.bodyRegular,
            color: TPColors.grayscale500,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildLanguageStep() {
    const Map<TranslationLanguage, String> hint = {
      TranslationLanguage.english: 'English',
      TranslationLanguage.japanese: 'Japanese',
      TranslationLanguage.vietnamese: 'Vietnamese',
    };

    return ListView(
      key: const ValueKey('language'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _Header(
          icon: Assets.svg.iconExploreTaipei.svg(),
          title: 'Choose your language',
          subtitle: '言語を選択・Chọn ngôn ngữ\n請選擇語言',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              for (final TranslationLanguage language in TranslationLanguage.values) ...[
                TPServiceListBlock(
                  title: language.label,
                  description: hint[language],
                  onTap: () => _onLanguageTap(language),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TPText(
            'Messages will be translated into this language automatically.\n訊息會自動翻譯成此語言',
            style: TPTextStyles.bodyRegular,
            color: TPColors.grayscale500,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.icon, required this.title, required this.subtitle});

  final Widget icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        children: [
          ExcludeSemantics(child: SizedBox.square(dimension: 48, child: icon)),
          const SizedBox(height: 16),
          Semantics(
            header: true,
            child: TPText(
              title,
              style: TPTextStyles.h2SemiBold,
              color: TPColors.grayscale900,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          TPText(
            subtitle,
            style: TPTextStyles.bodyRegular,
            color: TPColors.grayscale600,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
