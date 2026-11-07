import 'package:town_pass/page/service_assistant/service_search.dart';

/// 辭庫裡的一筆文件：檢索的單位，也是交給 LLM 的參考資料。
class RagDocument {
  const RagDocument({
    required this.id,
    required this.title,
    required this.body,
    required this.action,
    this.aliases = const [],
    this.keywords = const [],
    this.category,
    this.source = RagSource.inventory,
  });

  /// 穩定的識別碼，例如 `service:library`、`subpage:online_police:165`。
  final String id;

  /// 顯示名稱；同時是 LLM 回答時唯一能用的名稱，在辭庫內不重複。
  final String title;

  /// 給檢索與 LLM 看的說明文字（說明、分類、開放狀態、所屬區塊等）。
  final String body;

  /// 畫面上的其他叫法，例如清冊入口「警政報案」對應服務「警政服務」。
  final List<String> aliases;

  /// 同義詞與口語說法，例如「借書」。
  final List<String> keywords;

  /// 清冊的服務分類名稱，例如「城市生活」；清冊以外的文件為 null。
  final String? category;

  final RagSource source;

  /// 使用者點選後要做的事（開網頁、開 App 內頁、撥號確認、或「敬請期待」）。
  final ServiceSearchEntry action;

  bool get isComingSoon => action.isComingSoon;

  /// 交給 LLM 的一行參考資料：`名稱｜說明｜狀態`。
  String toContextLine() => '- $title｜$body${isComingSoon ? '｜（尚未開放）' : ''}';

  @override
  String toString() => 'RagDocument($id, $title)';
}

/// 文件從哪裡來。
enum RagSource {
  /// assets/rag/service_inventory.json（「服務」頁籤的服務清冊）。
  inventory,

  /// 清冊範圍外、但小幫手原本就能找到的項目：帳務繳費、App 內建頁、緊急求救。
  catalog,
}

/// 檢索結果：文件與 BM25 分數。
class RagHit {
  const RagHit(this.document, this.score);

  final RagDocument document;
  final double score;

  @override
  String toString() => 'RagHit(${document.title}, ${score.toStringAsFixed(2)})';
}
