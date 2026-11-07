import 'package:flutter/foundation.dart';
import 'package:town_pass/service/system_one/jev_client.dart';
import 'package:town_pass/service/user_traits/user_trait.dart';

/// 用 System One（Jev）從一句問句判斷使用者特徵。
///
/// 每個特徵都寫成一道題目，Jev 回傳的機率直接當作可信度（Jev 的機率有校準過，比 LLM 自評可靠）：
/// - 語言、與台北的關係、交通方式：選擇題（互斥，都有「看不出來」選項）。
/// - 照顧小孩、照顧長輩、每一種興趣：是非題。
/// - 另有一題「是否提到病況或就醫」：是的話不記 wellness（敏感資料不推論）。
///
/// 只問非敏感特徵；健康、犯罪受害、財務、宗教、政治、族群、性別、年齡都不出題。
class JevTraitClassifier {
  JevTraitClassifier({JevClient? client}) : client = client ?? JevClient();

  final JevClient client;

  /// 機率低於這個值的特徵不記。
  static const double minProbability = 0.5;

  static const String _unknown = 'unknown';
  static const String _medical = 'medical';

  bool get isEnabled => client.isEnabled;
  String get model => client.model;

  static final Map<String, JevQuestion> questions = {
    'language': const JevChoice('這句問句主要是用哪一種語言寫的？', {
      'zh': '中文',
      'en': '英文',
      'ja': '日文',
      'vi': '越南文',
      _unknown: '其他語言，或無法判斷',
    }),
    'relation': const JevChoice('只根據這句問句，提問者和台北的關係最可能是哪一種？沒有線索就選 unknown，不要猜。', {
      'resident': '住在台北（例如提到家裡、水費、里長、社區）',
      'commuter': '在台北上班或上學，但不住台北',
      'visitor': '來台北旅遊或短暫造訪',
      'new_resident': '從外國來台灣定居的新住民',
      _unknown: '問句中看不出來',
    }),
    'transport': const JevChoice('只根據這句問句，提問者平常主要的交通方式是哪一種？沒有線索就選 unknown，不要猜。', {
      'car_scooter': '開車或騎機車（例如提到停車、加油、車位）',
      'public_transit': '搭捷運或公車',
      'walk_bike': '走路或騎腳踏車（例如 YouBike）',
      _unknown: '問句中看不出來',
    }),
    'caregiver_child': const JevYesNo('從這句問句看，提問者是否需要照顧家中的小孩（例如提到孩子、親子、學費、托育）？'),
    'caregiver_elder': const JevYesNo('從這句問句看，提問者是否需要照顧家中的長輩（例如提到爸媽、阿公阿嬤、長照）？'),
    for (final String value in TraitDimension.interest.allowedValues)
      'interest_$value': JevYesNo('提問者是否關心「${TraitDimension.labels[value]}」相關的事？'
          '${value == 'wellness' ? '只限想看健康養生、運動保健資訊；提到症狀、生病、看醫生不算。' : ''}'),
    _medical: const JevYesNo('這句問句是否提到提問者或家人的症狀、生病、受傷、看醫生、掛號、疫苗或醫療費用？'),
  };

  /// 判斷一句問句的特徵；失敗時丟出 [JevException]。
  Future<List<InferredTrait>> classify(String query) async => parse(await client.decide(state: query, questions: questions));

  /// 把 Jev 的回答轉成特徵（測試可直接餵假回答）。
  @visibleForTesting
  static List<InferredTrait> parse(JevAnswers answers) {
    final List<InferredTrait> traits = [];
    void addChoice(String key, TraitDimension dimension) {
      final (String, double)? answer = answers.choice(key);
      if (answer == null) return;
      final (String value, double probability) = answer;
      if (value != _unknown && probability >= minProbability && dimension.allows(value)) {
        traits.add(InferredTrait(dimension, value, probability));
      }
    }

    void addYes(String key, TraitDimension dimension, String value) {
      final double? probability = answers.yes(key);
      if (probability != null && probability >= minProbability) traits.add(InferredTrait(dimension, value, probability));
    }

    addChoice('language', TraitDimension.language);
    addChoice('relation', TraitDimension.relation);
    addChoice('transport', TraitDimension.transport);
    addYes('caregiver_child', TraitDimension.caregiverOf, 'child');
    addYes('caregiver_elder', TraitDimension.caregiverOf, 'elder');
    final bool medical = (answers.yes(_medical) ?? 0) >= minProbability;
    for (final String value in TraitDimension.interest.allowedValues) {
      if (value == 'wellness' && medical) continue;
      addYes('interest_$value', TraitDimension.interest, value);
    }
    return traits;
  }
}
