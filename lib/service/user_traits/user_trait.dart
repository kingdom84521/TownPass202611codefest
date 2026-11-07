/// 從使用者的提問推論出的「非敏感」特徵，供之後做功能推薦。
///
/// 只允許下列固定的維度與值（LLM 回傳也以 enum 限制）。刻意不包含任何敏感類別：
/// 健康狀況與疾病、犯罪受害（詐騙、家暴、報案）、財務與社福身分、宗教、政治、族群、性別、年齡。
///
/// `wellness` 只代表「想看健康養生、運動保健的資訊」，不代表任何健康狀況：
/// 不從症狀、看病、掛號推論，問句對應到醫療服務時也會被丟棄（見 UserTraitRecorder.recordInferred）。
enum TraitDimension {
  /// 提問使用的語言。
  language(exclusive: true, allowedValues: ['zh', 'en', 'ja', 'vi']),

  /// 與台北的關係：住在台北、在台北通勤（上班上學）、來旅遊、新住民（從外國來台定居）。
  relation(exclusive: true, allowedValues: ['resident', 'commuter', 'visitor', 'new_resident']),

  /// 平常的交通方式。
  transport(exclusive: true, allowedValues: ['car_scooter', 'public_transit', 'walk_bike']),

  /// 家中需要照顧的對象（可多個）。
  caregiverOf(exclusive: false, allowedValues: ['elder', 'child']),

  /// 關心的服務類型（可多個）。
  interest(exclusive: false, allowedValues: [
    'city_affairs', // 申辦、臨櫃、里辦
    'civic_participation', // 陳情、1999、投票、意見調查
    'reading', // 借書
    'family_outings', // 親子館、動物園
    'pets',
    'nature_parks',
    'places_travel', // 找地點、觀光
    'bills_payment',
    'roads_traffic', // 施工、交通管制
    'disaster_weather', // 災情、颱風、空品
    'city_data',
    'local_media',
    'living_costs', // 物價、民生物資
    'sports', // 運動、賽事、運動場館
    'culture_events', // 廟會、節慶、展覽、藝文活動
    'environment', // 環保、減碳、空氣品質
    'wellness', // 想看健康養生資訊（不是健康狀況）
    'learning', // 進修、課程
  ]);

  /// 每個值的中文說明：給 LLM 判斷用，也可直接顯示。
  static const Map<String, String> labels = {
    'zh': '中文',
    'en': '英文',
    'ja': '日文',
    'vi': '越南文',
    'resident': '住在台北',
    'commuter': '在台北上班或上學',
    'visitor': '來台北旅遊',
    'new_resident': '從外國來台灣定居（新住民）',
    'car_scooter': '開車或騎機車',
    'public_transit': '搭捷運、公車',
    'walk_bike': '走路或騎腳踏車',
    'elder': '長輩',
    'child': '小孩',
    'city_affairs': '辦事、申請（申辦、臨櫃、里辦）',
    'civic_participation': '反映意見（陳情、1999、投票、問卷）',
    'reading': '借書、閱讀',
    'family_outings': '親子活動（親子館、動物園）',
    'pets': '寵物',
    'nature_parks': '公園綠地',
    'places_travel': '找地點、觀光',
    'bills_payment': '繳費',
    'roads_traffic': '道路交通、施工',
    'disaster_weather': '災情、天氣、颱風',
    'city_data': '市政數據',
    'local_media': '在地廣播',
    'living_costs': '物價',
    'sports': '運動、賽事、運動場館',
    'culture_events': '文化活動（廟會、節慶、展覽）',
    'environment': '環保、減碳、空氣品質',
    'wellness': '想看健康養生、運動保健資訊',
    'learning': '進修、課程',
  };

  const TraitDimension({required this.exclusive, required this.allowedValues});

  /// 互斥的維度同一時間只會有一個值成立（例如語言）；互相矛盾的觀察會降低彼此的可信度。
  final bool exclusive;

  /// 允許的值；其他值一律丟棄。
  final List<String> allowedValues;

  bool allows(String value) => allowedValues.contains(value);

  static TraitDimension? byName(String name) {
    for (final TraitDimension dimension in values) {
      if (dimension.name == name) return dimension;
    }
    return null;
  }
}

/// 觀察的來源。不同來源的可信度權重不同。
enum TraitSource {
  /// LLM 從問句推論，附帶 LLM 自評的可信度。
  llm(weight: 1.0),

  /// 使用者點開了小幫手推薦的服務：行為比文字更可靠。
  click(weight: 0.9),

  /// 關鍵字直接命中服務名稱（沒有經過 LLM）。
  keyword(weight: 0.6);

  const TraitSource({required this.weight});

  final double weight;
}

/// LLM 從一句問句推論出的特徵（尚未存檔）。
class InferredTrait {
  const InferredTrait(this.dimension, this.value, this.confidence);

  final TraitDimension dimension;
  final String value;
  final double confidence;

  @override
  bool operator ==(Object other) =>
      other is InferredTrait && other.dimension == dimension && other.value == value && other.confidence == confidence;

  @override
  int get hashCode => Object.hash(dimension, value, confidence);

  @override
  String toString() => 'InferredTrait(${dimension.name}=$value, $confidence)';
}

/// 一筆觀察：某次提問（或點擊）顯示使用者可能有某個特徵。
///
/// 不保存問句原文；[evidenceKey] 是問句正規化後的雜湊，用來辨認「同一個問題問了好幾次」，
/// 避免重複的問題灌高可信度。
class TraitObservation {
  TraitObservation({
    required this.dimension,
    required this.value,
    required double confidence,
    required this.source,
    required this.evidenceKey,
    required this.observedAt,
    this.detail,
    this.model,
  })  : assert(dimension.allows(value), '$value 不是 ${dimension.name} 允許的值'),
        confidence = confidence.clamp(0.0, 1.0).toDouble();

  final TraitDimension dimension;
  final String value;

  /// 這一筆觀察本身的可信度（0–1）。LLM 自評，或依來源給的固定值。
  final double confidence;
  final TraitSource source;
  final String evidenceKey;
  final DateTime observedAt;

  /// 補充說明（不含問句原文），例如觸發的服務名稱。
  final String? detail;

  /// 產生觀察的模型（LLM 來源才有）。
  final String? model;

  @override
  String toString() => 'TraitObservation(${dimension.name}=$value, ${confidence.toStringAsFixed(2)}, ${source.name})';
}

/// 綜合多筆觀察後的特徵。
class UserTrait {
  const UserTrait({
    required this.dimension,
    required this.value,
    required this.confidence,
    required this.evidenceCount,
    required this.lastObservedAt,
  });

  final TraitDimension dimension;
  final String value;

  /// 綜合可信度（0–1），見 [TraitAggregator]。
  final double confidence;

  /// 支持這個特徵的不同證據數（不同問題或點擊）。
  final int evidenceCount;
  final DateTime lastObservedAt;

  @override
  String toString() =>
      'UserTrait(${dimension.name}=$value, ${confidence.toStringAsFixed(2)}, n=$evidenceCount)';
}
