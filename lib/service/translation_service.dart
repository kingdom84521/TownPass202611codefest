import 'package:get/get.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:town_pass/service/shared_preferences_service.dart';

/// 可供外籍人士選擇的翻譯語言。
enum TranslationLanguage {
  english('English', TranslateLanguage.english),
  japanese('日本語', TranslateLanguage.japanese),
  vietnamese('Tiếng Việt', TranslateLanguage.vietnamese),
  ;

  const TranslationLanguage(this.label, this.mlKitLanguage);

  /// 以該語言本身書寫的名稱，讓外籍人士能認得。
  final String label;
  final TranslateLanguage mlKitLanguage;

  /// 對應的使用者語言特徵值（見 TraitDimension.language）。
  String get traitCode => switch (this) {
        TranslationLanguage.english => 'en',
        TranslationLanguage.japanese => 'ja',
        TranslationLanguage.vietnamese => 'vi',
      };
}

/// 使用 Google ML Kit 在手機上離線翻譯（中文 → 使用者設定的翻譯語言）。
/// 每種語言第一次使用時需下載約 30MB 的翻譯模型。
class TranslationService extends GetxService {
  static const String _keyTranslationLanguage = 'translation_language';
  static const TranslateLanguage _sourceLanguage = TranslateLanguage.chinese;

  final Rx<TranslationLanguage> targetLanguage = TranslationLanguage.english.obs;

  final OnDeviceTranslatorModelManager _modelManager = OnDeviceTranslatorModelManager();
  final Map<TranslationLanguage, OnDeviceTranslator> _translators = {};
  final Map<(TranslationLanguage, String), String> _cache = {};

  SharedPreferencesService get _preferences => Get.find<SharedPreferencesService>();

  Future<TranslationService> init() async {
    final String? saved = _preferences.instance.getString(_keyTranslationLanguage);
    targetLanguage.value = TranslationLanguage.values.firstWhere(
      (language) => language.name == saved,
      orElse: () => TranslationLanguage.english,
    );
    return this;
  }

  Future<void> setTargetLanguage(TranslationLanguage language) async {
    targetLanguage.value = language;
    await _preferences.instance.setString(_keyTranslationLanguage, language.name);
  }

  /// 翻譯模型是否已下載，未下載時翻譯會花較久時間。
  Future<bool> isModelReady(TranslationLanguage language) async {
    final List<bool> results = await Future.wait([
      _modelManager.isModelDownloaded(_sourceLanguage.bcpCode),
      _modelManager.isModelDownloaded(language.mlKitLanguage.bcpCode),
    ]);
    return results.every((downloaded) => downloaded);
  }

  /// 將中文翻譯成目前設定的翻譯語言，必要時先下載模型。
  Future<String> translate(String text) async {
    final TranslationLanguage language = targetLanguage.value;
    final String? cached = _cache[(language, text)];
    if (cached != null) {
      return cached;
    }

    await _ensureModel(_sourceLanguage);
    await _ensureModel(language.mlKitLanguage);

    final OnDeviceTranslator translator = _translators.putIfAbsent(
      language,
      () => OnDeviceTranslator(
        sourceLanguage: _sourceLanguage,
        targetLanguage: language.mlKitLanguage,
      ),
    );
    final String result = await translator.translateText(text);
    _cache[(language, text)] = result;
    return result;
  }

  Future<void> _ensureModel(TranslateLanguage language) async {
    if (await _modelManager.isModelDownloaded(language.bcpCode)) {
      return;
    }
    final bool downloaded = await _modelManager.downloadModel(language.bcpCode, isWifiRequired: false);
    if (!downloaded) {
      throw Exception('Failed to download translation model: ${language.bcpCode}');
    }
  }

  @override
  void onClose() {
    for (final translator in _translators.values) {
      translator.close();
    }
    super.onClose();
  }
}
