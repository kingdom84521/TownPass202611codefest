import 'package:flutter/material.dart';
import 'package:town_pass/gen/assets.gen.dart';
import 'package:town_pass/page/child_mode/widget/child_mode_call_dialog.dart';
import 'package:town_pass/page/city_service/model/my_service_model.dart';
import 'package:town_pass/util/tp_service_block.dart';

/// 可被「找服務」搜尋到的服務。
class ServiceSearchEntry {
  const ServiceSearchEntry({
    required this.title,
    required this.description,
    required this.icon,
    required this.keywords,
    this.uri = '',
    this.forceTitle,
    this.onOpen,
  });

  final String title;
  final String description;
  final Widget icon;

  /// 同義詞與口語說法，例如「借書」對應圖書借閱。
  final List<String> keywords;
  final String uri;
  final String? forceTitle;

  /// 自訂開啟行為（例如撥號），未設定時開啟 [uri]。
  final VoidCallback? onOpen;

  void open() {
    if (onOpen != null) {
      onOpen!();
    } else {
      openServiceOrComingSoon(uri: uri, title: title, forceTitle: forceTitle);
    }
  }
}

/// 內建的文字比對搜尋：比對服務名稱、同義詞與說明，不需網路或 AI。
abstract final class ServiceSearch {
  static const int maxResults = 4;

  /// 問句中常見、不帶意義的詞，比對前先移除，避免「我想要」之類的字誤配。
  static const List<String> _fillerWords = [
    '我想要', '我想', '我要', '想要', '請問', '幫我', '可以', '怎麼', '如何', '哪裡', '哪邊', '在哪',
    '一下', '要去', '需要', '有沒有', '什麼', '服務', '台北市', '臺北市', '台北', '臺北', '市政',
    '線上', '提供', '我', '的', '了', '嗎', '呢', '吧', '啊', '去',
  ];

  /// 每個服務的同義詞；名稱本身會自動加入比對，不必重複列出。
  static const Map<MyServiceItemId, List<String>> _keywords = {
    MyServiceItemId.dedicatedLine: ['市民熱線', '客服', '打電話', '電話', '陳情', '諮詢'],
    MyServiceItemId.districtOffice: ['申辦', '申請', '區公所', '辦證件', '戶政', '辦理'],
    MyServiceItemId.reportIssue: ['陳情', '抱怨', '檢舉', '反映', '意見', '路燈', '坑洞', '噪音'],
    MyServiceItemId.reservation: ['叫號', '排隊', '預約', '臨櫃', '號碼牌'],
    MyServiceItemId.iVoting: ['投票', '民意', 'ivoting'],
    MyServiceItemId.dashboard: ['數據', '統計', '儀表板', '資料'],
    MyServiceItemId.survey: ['問卷', '調查', '意見', '回饋'],
    MyServiceItemId.police: ['報案', '警察', '派出所', '110', '小偷', '被偷', '失竊', '遺失', '詐騙', '165'],
    MyServiceItemId.neighborhood: ['里長', '里辦', '鄰里', '社區'],
    MyServiceItemId.disasterReport: ['災情', '地震', '颱風', '淹水', '積水', '倒樹', '土石流'],
    MyServiceItemId.vaccineAppointment: ['疫苗', '打針', '流感', '新冠', 'covid', '接種'],
    MyServiceItemId.medicalAppointment: ['掛號', '看病', '看醫生', '醫院', '聯醫', '門診', '生病'],
    MyServiceItemId.cityRadio: ['電台', '廣播', '收音機', '收聽'],
    MyServiceItemId.familyCenter: ['親子', '小孩', '兒童', '育兒', '寶寶', '玩'],
    MyServiceItemId.greenMap: ['公園', '綠地', '森林', '散步', '綠化', '樹'],
    MyServiceItemId.petFriendlyMap: ['寵物', '狗', '貓', '遛狗', '帶狗', '狗狗', '遛貓', '毛小孩'],
    MyServiceItemId.waterMeter: ['水費', '自來水', '用水', '水表', '停水', '繳費'],
    MyServiceItemId.essentialGoods: ['菜價', '物價', '物資', '價格', '市場'],
    MyServiceItemId.library: ['借書', '還書', '圖書館', '書', '閱讀', '看書'],
    MyServiceItemId.locationSearch: ['地圖', '附近', '地點', '位置', '在哪', '找路'],
    MyServiceItemId.zoo: ['動物園', '動物', '木柵', '熊貓'],
  };

  /// 各服務開啟方式的例外：清單中尚無網址、但 App 內已有對應功能者。
  static final Map<MyServiceItemId, ({String uri, VoidCallback? onOpen})> _overrides = {
    MyServiceItemId.police: (uri: 'local://online_police', onOpen: null),
    MyServiceItemId.dedicatedLine: (uri: '', onOpen: () => ChildModeCallDialog.confirm(number: '1999')),
  };

  static List<ServiceSearchEntry> get catalog => [
        ServiceSearchEntry(
          title: '緊急求救',
          description: '撥打 110 警察、119 消防救護',
          icon: Assets.svg.icon110.svg(),
          keywords: const ['緊急', '救命', '危險', '110', '119', '火災', '失火', '救護車', '受傷', '車禍'],
          onOpen: ChildModeCallDialog.emergency,
        ),
        for (final MyServiceItemId id in MyServiceItemId.values)
          ServiceSearchEntry(
            title: id.item.title,
            description: id.item.description,
            icon: id.item.icon,
            keywords: _keywords[id] ?? const [],
            uri: _overrides[id]?.uri ?? id.item.destinationUrl,
            forceTitle: id.item.forceWebViewTitle,
            onOpen: _overrides[id]?.onOpen,
          ),
        ServiceSearchEntry(
          title: '施工資訊',
          description: '查詢道路施工資訊',
          icon: Assets.svg.iconLocationSearch.svg(),
          keywords: const ['施工', '修路', '道路', '挖路', '封路', '塞車'],
        ),
      ];

  /// 依關聯程度排序，回傳最相關的服務；沒有任何相關時回傳空清單。
  static List<ServiceSearchEntry> search(String query, {List<ServiceSearchEntry>? entries}) {
    final String normalizedQuery = _stripFillers(_normalize(query));
    if (normalizedQuery.isEmpty) {
      return [];
    }

    final List<(ServiceSearchEntry, int)> scored = [
      for (final entry in entries ?? catalog) (entry, score(entry, normalizedQuery)),
    ]..removeWhere((pair) => pair.$2 < _minScore);

    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.take(maxResults).map((pair) => pair.$1).toList();
  }

  static const int _minScore = 3;

  /// [query] 須已經過 [_normalize] 與 [_stripFillers]。
  static int score(ServiceSearchEntry entry, String query) {
    int score = 0;
    final String title = _normalize(entry.title);

    // 1. 名稱完全符合或互相包含
    if (title == query) {
      score += 30;
    } else if (query.contains(title) || (query.length >= 2 && title.contains(query))) {
      score += 20;
    }

    // 2. 同義詞：問句中出現同義詞（例如「我想借書」含「借書」）
    for (final String keyword in entry.keywords.map(_normalize)) {
      if (keyword.isEmpty) continue;
      if (query.contains(keyword)) {
        // 越長的詞越明確，給越高分
        score += 6 + keyword.length * 2;
      } else if (query.length >= 2 && keyword.contains(query)) {
        score += 5;
      }
    }

    // 3. 字詞片段重疊：處理沒列入同義詞的說法
    final Set<String> queryGrams = _bigrams(query);
    final Set<String> entryGrams = _bigrams(_normalize('${entry.title}${entry.description}'));
    score += queryGrams.intersection(entryGrams).length * 2;

    return score;
  }

  static String _normalize(String text) {
    return text.toLowerCase().replaceAll('臺', '台').replaceAll(RegExp(r'[\s\p{P}\p{S}]', unicode: true), '');
  }

  static String _stripFillers(String text) {
    String result = text;
    for (final String filler in _fillerWords.map(_normalize)) {
      result = result.replaceAll(filler, '');
    }
    return result;
  }

  /// 連續兩字的片段；單一字元時回傳該字。
  static Set<String> _bigrams(String text) {
    if (text.length < 2) {
      return text.isEmpty ? {} : {text};
    }
    return {for (int i = 0; i < text.length - 1; i++) text.substring(i, i + 2)};
  }
}
