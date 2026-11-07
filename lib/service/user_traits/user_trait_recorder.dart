import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:town_pass/page/service_assistant/service_search.dart';
import 'package:town_pass/service/recommendation_service.dart';
import 'package:town_pass/service/user_traits/user_trait.dart';
import 'package:town_pass/service/user_traits/user_trait_repository.dart';

/// 把服務小幫手的各種訊號轉成特徵觀察並寫進資料庫：
///
/// - LLM 推論的特徵（[recordInferred]）：可信度由 LLM 自評。
/// - 關鍵字直接命中的服務（[recordKeywordMatch]）、使用者點開的服務（[recordOpened]）：
///   依 [_serviceTraits] 對應到特徵，可信度為固定值。
///
/// 記錄失敗只寫 log，不影響小幫手本身。
class UserTraitRecorder {
  UserTraitRecorder({Future<UserTraitRepository> Function()? repository, DateTime Function()? clock})
      : _repository = repository ?? UserTraitRepository.shared,
        _clock = clock ?? DateTime.now;

  final Future<UserTraitRepository> Function() _repository;
  final DateTime Function() _clock;

  /// 關鍵字命中與點擊的固定可信度（再乘上 [TraitSource.weight]）。
  static const double keywordConfidence = 0.5;
  static const double clickConfidence = 0.8;

  /// 服務 → 它透露的特徵。刻意不列入敏感服務：警政報案、緊急求救、110／119／165／113、
  /// 醫療（聯醫掛號、疫苗、醫療費）、社福身分（國／社宅、平價住宅）。不在表上的服務不產生任何觀察。
  static const Map<String, List<(TraitDimension, String)>> _serviceTraits = {
    '申辦服務': [(TraitDimension.interest, 'city_affairs')],
    '臨櫃叫號': [(TraitDimension.interest, 'city_affairs')],
    '里辦服務': [(TraitDimension.interest, 'city_affairs'), (TraitDimension.relation, 'resident')],
    '有話要說': [(TraitDimension.interest, 'civic_participation')],
    '意見調查': [(TraitDimension.interest, 'civic_participation')],
    '網路投票': [(TraitDimension.interest, 'civic_participation')],
    '1999': [(TraitDimension.interest, 'civic_participation')],
    '圖書借閱': [(TraitDimension.interest, 'reading')],
    '親子館': [(TraitDimension.interest, 'family_outings'), (TraitDimension.caregiverOf, 'child')],
    '愛遊動物園': [(TraitDimension.interest, 'family_outings')],
    '寵物安心遛': [(TraitDimension.interest, 'pets')],
    '簡單森呼吸': [(TraitDimension.interest, 'nature_parks')],
    '找地點': [(TraitDimension.interest, 'places_travel')],
    '施工資訊': [(TraitDimension.interest, 'roads_traffic')],
    '災情通報': [(TraitDimension.interest, 'disaster_weather')],
    '市政資訊儀表板': [(TraitDimension.interest, 'city_data')],
    '台北電台': [(TraitDimension.interest, 'local_media')],
    '民生物資': [(TraitDimension.interest, 'living_costs')],
    '用水服務': [(TraitDimension.interest, 'bills_payment'), (TraitDimension.relation, 'resident')],
    '水費': [(TraitDimension.interest, 'bills_payment'), (TraitDimension.relation, 'resident')],
    '地方稅': [(TraitDimension.interest, 'bills_payment'), (TraitDimension.relation, 'resident')],
    '停車費': [(TraitDimension.interest, 'bills_payment'), (TraitDimension.transport, 'car_scooter')],
    '學雜費': [(TraitDimension.interest, 'bills_payment'), (TraitDimension.caregiverOf, 'child')],
    '公訓處自費課程': [(TraitDimension.interest, 'bills_payment'), (TraitDimension.interest, 'learning')],
    '其他繳費': [(TraitDimension.interest, 'bills_payment')],
    '掃描繳費': [(TraitDimension.interest, 'bills_payment')],
    '繳費紀錄': [(TraitDimension.interest, 'bills_payment')],
  };

  /// 服務透露的特徵；推薦對照表（RecommendationTargets）也用這份。
  static List<(TraitDimension, String)> traitsOfService(String title) => _serviceTraits[title] ?? const [];

  /// 對照表裡的所有服務（推薦的語意相似度只會用到這些，不含敏感服務）。
  static Iterable<String> get serviceTitles => _serviceTraits.keys;

  /// 問句的證據鍵：正規化後的 FNV-1a 雜湊。同一句話（不分大小寫、標點）得到同一個鍵；不保存原文。
  static String evidenceKey(String query) {
    int hash = 0x811c9dc5;
    for (final int byte in utf8.encode(ServiceSearch.normalize(query))) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return 'q:${hash.toRadixString(16).padLeft(8, '0')}';
  }

  /// 問句提到這些字，代表在講自己或家人的病況或就醫，此時不記錄 `wellness`
  /// （避免把病況變成「健康資訊興趣」存下來）。提示詞也要求 LLM 不要填，這裡是第二道防線。
  /// 只看問句、不看 AI 推薦的服務：App 沒有健康資訊類服務，單純想看養生資訊時 AI 也常推薦聯醫掛號。
  static const List<String> medicalWords = [
    '病', '醫', '診', '藥', '痛', '咳', '燒', '癢', '傷', '吐', '暈', '症', '癌', '孕', '掛號', '疫苗', '住院', '開刀',
    'sick', 'ill', 'doctor', 'hospital', 'clinic', 'fever', 'cough', 'pain', 'medicine', 'vaccine', 'symptom',
  ];

  static bool mentionsMedical(String query) {
    final String text = query.toLowerCase();
    return medicalWords.any(text.contains);
  }

  /// 記錄 LLM 推論的特徵（問句提到病況或就醫時略過 `wellness`）。
  Future<void> recordInferred(String query, List<InferredTrait> traits, {String? model}) => _save([
        for (final InferredTrait trait in traits)
          if (trait.dimension.allows(trait.value) && !(trait.value == 'wellness' && mentionsMedical(query)))
            TraitObservation(
              dimension: trait.dimension,
              value: trait.value,
              confidence: trait.confidence,
              source: TraitSource.llm,
              evidenceKey: evidenceKey(query),
              observedAt: _clock(),
              model: model,
            ),
      ]);

  /// 關鍵字直接命中時，只記最相關的那一個服務（後面幾個多半只是部分相符）。
  Future<void> recordKeywordMatch(String query, ServiceSearchEntry top) =>
      _save(_fromService(top.title, TraitSource.keyword, keywordConfidence, evidenceKey(query)));

  /// 使用者點開推薦的服務。證據鍵與該問題不同，點擊算一份獨立的佐證。
  Future<void> recordOpened(String query, ServiceSearchEntry entry) =>
      _save(_fromService(entry.title, TraitSource.click, clickConfidence, '${evidenceKey(query)}:click:${entry.title}'));

  static const String _languageSettingKey = 'setting:translation_language';

  /// 使用者自己在設定裡選了翻譯語言（取代原本「我是誰」選外籍人士的訊號）。
  /// 只保留最新的選擇：重複選不會疊加，改選時舊的選擇會被取代。
  Future<void> recordLanguageChoice(String languageCode) async {
    if (!TraitDimension.language.allows(languageCode)) return;
    try {
      await (await _repository()).removeEvidence(_languageSettingKey);
    } catch (error) {
      debugPrint('[使用者特徵] 清除舊的語言設定失敗：$error');
    }
    await _save([
      TraitObservation(
        dimension: TraitDimension.language,
        value: languageCode,
        confidence: clickConfidence,
        source: TraitSource.click,
        evidenceKey: _languageSettingKey,
        observedAt: _clock(),
        detail: '翻譯語言',
      ),
    ]);
  }

  Future<List<UserTrait>> traits({double minConfidence = 0}) async =>
      (await _repository()).traits(now: _clock(), minConfidence: minConfidence);

  List<TraitObservation> _fromService(String title, TraitSource source, double confidence, String key) => [
        for (final (TraitDimension dimension, String value) in traitsOfService(title))
          TraitObservation(
            dimension: dimension,
            value: value,
            confidence: confidence,
            source: source,
            evidenceKey: key,
            observedAt: _clock(),
            detail: title,
          ),
      ];

  Future<void> _save(List<TraitObservation> observations) async {
    if (observations.isEmpty) return;
    try {
      await (await _repository()).add(observations);
      notifyTraitsChanged();
      debugPrint('[使用者特徵] 記錄 ${observations.length} 筆：'
          '${observations.map((o) => '${o.dimension.name}=${o.value}(${o.source.name} ${o.confidence.toStringAsFixed(2)})').join('、')}');
    } catch (error) {
      debugPrint('[使用者特徵] 記錄失敗：$error');
    }
  }
}
