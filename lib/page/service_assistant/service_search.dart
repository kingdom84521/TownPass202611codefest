import 'package:flutter/material.dart';
import 'package:town_pass/gen/assets.gen.dart';
import 'package:town_pass/page/bill/bill_view.dart';
import 'package:town_pass/util/tp_call_dialog.dart';
import 'package:town_pass/page/city_service/model/my_service_model.dart';
import 'package:town_pass/util/tp_colors.dart';
import 'package:town_pass/util/tp_route.dart';
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

  /// 沒有網址也沒有自訂行為，點了只會顯示「敬請期待」。
  bool get isComingSoon => uri.isEmpty && onOpen == null;

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
  /// 注意：只會從「問句」移除，同義詞若含這些字（例如「掉了」）就永遠比對不到；
  /// test/service_search_test.dart 會檢查。
  @visibleForTesting
  static List<String> get fillerWords => _fillerWords;

  static const List<String> _fillerWords = [
    '我想要', '我想', '我要', '想要', '請問', '幫我', '可以', '怎麼', '如何', '哪裡', '哪邊', '在哪',
    '一下', '要去', '需要', '有沒有', '什麼', '服務', '台北市', '臺北市', '台北', '臺北', '市政',
    '線上', '提供', '我', '的', '了', '嗎', '呢', '吧', '啊', '去',
  ];

  /// 每個服務的同義詞；名稱本身會自動加入比對，不必重複列出。
  static const Map<MyServiceItemId, List<String>> _keywords = {
    MyServiceItemId.dedicatedLine: ['市民熱線', '客服', '打電話', '電話', '陳情', '諮詢'],
    MyServiceItemId.districtOffice: ['申辦', '申請', '區公所', '辦證件', '戶政', '辦理'],
    MyServiceItemId.reportIssue: ['陳情', '抱怨', '檢舉', '反映', '意見', '路燈', '坑洞', '噪音', '吵', '壞', '故障'],
    MyServiceItemId.reservation: ['叫號', '排隊', '預約', '臨櫃', '號碼牌'],
    MyServiceItemId.iVoting: ['投票', '民意', 'ivoting'],
    // 不放「資料」：會讓「改個人資料」誤配到儀表板
    MyServiceItemId.dashboard: ['數據', '統計', '儀表板', '開放資料'],
    MyServiceItemId.survey: ['問卷', '調查', '意見', '回饋'],
    MyServiceItemId.police: ['報案', '警察', '派出所', '110', '小偷', '被偷', '失竊', '遺失', '詐騙', '165', '掉', '不見', '弄丟', '錢包', '皮夾'],
    MyServiceItemId.neighborhood: ['里長', '里辦', '鄰里', '社區'],
    MyServiceItemId.disasterReport: ['災情', '地震', '颱風', '淹水', '積水', '倒樹', '土石流'],
    MyServiceItemId.vaccineAppointment: ['疫苗', '打針', '流感', '新冠', 'covid', '接種'],
    MyServiceItemId.medicalAppointment: ['掛號', '看病', '看醫生', '醫院', '聯醫', '門診', '生病'],
    MyServiceItemId.cityRadio: ['電台', '廣播', '收音機', '收聽'],
    MyServiceItemId.familyCenter: ['親子', '小孩', '兒童', '育兒', '寶寶', '玩'],
    MyServiceItemId.greenMap: ['公園', '綠地', '森林', '散步', '綠化', '樹'],
    MyServiceItemId.petFriendlyMap: ['寵物', '狗', '貓', '遛狗', '帶狗', '狗狗', '遛貓', '毛小孩'],
    // 不放「繳費」：泛稱的繳費交給帳務的繳費項目
    MyServiceItemId.waterMeter: ['水費', '自來水', '用水', '水表', '停水'],
    MyServiceItemId.essentialGoods: ['菜價', '物價', '物資', '價格', '市場'],
    MyServiceItemId.library: ['借書', '還書', '圖書館', '書', '閱讀', '看書'],
    // 「在哪」是贅字，比對前會從問句移除，放在這裡永遠比對不到
    MyServiceItemId.locationSearch: ['地圖', '附近', '地點', '位置', '找路'],
    MyServiceItemId.zoo: ['動物園', '動物', '木柵', '熊貓'],
  };

  /// 各服務開啟方式的例外：清單中尚無網址、但 App 內已有對應功能者。
  static final Map<MyServiceItemId, ({String uri, VoidCallback? onOpen})> _overrides = {
    MyServiceItemId.police: (uri: 'local://online_police', onOpen: null),
    MyServiceItemId.dedicatedLine: (uri: '', onOpen: () => TPCallDialog.confirm(number: '1999')),
  };

  /// 帳務「熱門繳費」各項的同義詞，以 [PopularBillItem.name] 對應。
  /// 繳費項目本身來自 [BillView.popularBillItems]，帳務頁增減項目時這裡自動跟上；
  /// 新項目沒有同義詞也能用名稱搜到。
  static const Map<String, List<String>> _billKeywords = {
    '停車費': ['停車', '停車單', '路邊停車', '繳費'],
    '水費': ['自來水', '繳費'],
    '地方稅': ['稅', '繳稅', '房屋稅', '地價稅', '牌照稅', '繳費'],
    '學雜費': ['學費', '註冊費', '繳費'],
    '國/社宅租金維管費': ['社宅', '國宅', '房租', '租金', '公宅', '繳費'],
    '聯合醫院醫療費': ['醫療費', '醫藥費', '住院費', '聯醫', '繳費'],
    '平價住宅維護費': ['平價住宅', '維護費', '繳費'],
    '公訓處自費課程': ['課程', '上課', '公訓處', '繳費'],
    '其他': ['其他費用', '繳費'],
  };

  /// 「其他」單獨出現在搜尋結果裡看不懂，改成較完整的名稱。
  static const Map<String, String> _billTitles = {'其他': '其他繳費'};

  /// App 內建頁面的圖示（沒有合適 SVG 的用 Material Icon）。
  static Widget _materialIcon(IconData icon) => Icon(icon, size: 32, color: TPColors.grayscale700);

  static List<ServiceSearchEntry> get catalog => [
        ServiceSearchEntry(
          title: '緊急求救',
          description: '撥打 110 警察、119 消防救護',
          icon: Assets.svg.icon110.svg(),
          keywords: const ['緊急', '救命', '危險', '110', '119', '火災', '失火', '救護車', '受傷', '車禍'],
          onOpen: TPCallDialog.emergency,
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

        // ── 帳務：熱門繳費（資料來源 BillView.popularBillItems）──
        for (final PopularBillItem bill in BillView.popularBillItems)
          ServiceSearchEntry(
            title: _billTitles[bill.name] ?? bill.name,
            description: '帳務 › 熱門繳費',
            icon: bill.icon,
            keywords: _billKeywords[bill.name] ?? const ['繳費'],
            uri: bill.uri,
          ),

        // ── 帳務：上方功能列（網址與 bill_app_bar.dart 相同，改網址時兩邊要一起改）──
        ServiceSearchEntry(
          title: '掃描繳費',
          description: '帳務 › 掃描帳單條碼繳費',
          icon: Assets.svg.iconScan.svg(),
          keywords: const ['掃描', '條碼', '掃碼', '帳單', '繳費單'],
          uri: 'https://taipei-pass-service.vercel.app/fee-payment/scan/',
        ),
        ServiceSearchEntry(
          title: '繳費紀錄',
          description: '帳務 › 查詢繳費紀錄',
          icon: Assets.svg.iconBill.svg(),
          keywords: const ['紀錄', '記錄', '繳過', '繳費明細', '繳費紀錄'],
          uri: 'https://taipei-pass-service.vercel.app/fee-payment/history/',
        ),

        // ── App 內建頁面（local:// 由 TPRoute.openUri 轉成 Get.toNamed）──
        // 刻意不收錄「停用帳號」：模糊比對不應一步導到帳號停用。
        // 不收錄需要帶參數的頁面（活動詳情、訊息詳情、訂閱內容等），直接開會出錯。
        ServiceSearchEntry(
          title: '我的帳戶',
          description: '查看帳戶與 App 相關設定',
          icon: Assets.svg.iconPerson.svg(),
          keywords: const ['帳戶', '帳號', '會員', '登入'],
          uri: 'local:/${TPRoute.account}',
        ),
        ServiceSearchEntry(
          title: '基本資料',
          description: '查看或修改姓名、電話、Email 等個人資料',
          icon: Assets.svg.iconInfo.svg(),
          keywords: const ['個人資料', '改資料', '修改資料', '姓名', '電話', '手機號碼', 'email', '地址', '身分證'],
          uri: 'local:/${TPRoute.basicInfo}',
        ),
        ServiceSearchEntry(
          title: '設定',
          description: '通知、發票、安全性等 App 設定',
          icon: Assets.svg.iconSettings.svg(),
          keywords: const ['設定', '通知', '快速登入', '安全'],
          uri: 'local:/${TPRoute.setting}',
        ),
        ServiceSearchEntry(
          title: '語言',
          description: '切換 App 顯示語言',
          icon: _materialIcon(Icons.language),
          keywords: const ['語言', '英文', 'english', '中文', '日文'],
          uri: 'local:/${TPRoute.language}',
        ),
        ServiceSearchEntry(
          title: 'APP起始頁面',
          description: '設定打開 App 時先看到哪一頁',
          icon: Assets.svg.iconSettings.svg(),
          keywords: const ['起始頁', '首頁設定', '開啟頁面', '預設頁面'],
          uri: 'local:/${TPRoute.settingStartPage}',
        ),
        ServiceSearchEntry(
          title: '手機載具',
          description: '設定電子發票手機條碼載具',
          icon: Assets.svg.iconBill.svg(),
          keywords: const ['載具', '發票', '電子發票', '手機條碼', '收據'],
          uri: 'local:/${TPRoute.invoiceReceipt}',
        ),
        ServiceSearchEntry(
          title: '訊息',
          description: '查看 App 收到的通知訊息',
          icon: Assets.svg.iconMail.svg(),
          keywords: const ['訊息', '通知', '信件', '收件匣', '消息'],
          uri: 'local:/${TPRoute.message}',
        ),
        ServiceSearchEntry(
          title: '意見回饋',
          description: '對 App 提出建議或回報問題',
          icon: Assets.svg.iconSurveyFeedback.svg(),
          keywords: const ['回饋', '建議', 'app壞', '閃退', '回報問題', 'bug', '客訴'],
          uri: 'local:/${TPRoute.feedback}',
        ),
        ServiceSearchEntry(
          title: '翻譯語言',
          description: '設定訂閱內容要翻譯成哪種語言',
          icon: _materialIcon(Icons.translate),
          keywords: const ['翻譯', '外語', '英文'],
          uri: 'local:/${TPRoute.translationLanguage}',
        ),
        ServiceSearchEntry(
          title: '重新選擇使用方式',
          description: '重新選擇一般、外籍人士、簡易等使用方式',
          icon: _materialIcon(Icons.people_alt_outlined),
          keywords: const ['使用方式', '長輩', '長者', '老人', '簡易', '身分'],
          uri: 'local:/${TPRoute.personaSelect}',
        ),
        ServiceSearchEntry(
          title: '功能教學',
          description: '常見問題與 App 使用教學',
          icon: Assets.svg.iconInfo.svg(),
          keywords: const ['教學', '操作', '使用說明', '常見問題', 'faq', '說明'],
          uri: 'https://id.taipei/tpcd/about/faq',
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

  /// 問句對所有服務的最高分；小幫手用來判斷關鍵字比對夠不夠有把握，不夠就改問 AI。
  /// 參考值：名稱直接命中 ≥ 20；只靠單字同義詞或字詞片段重疊多半 < 20。
  static int topScore(String query, {List<ServiceSearchEntry>? entries}) {
    final String normalizedQuery = _stripFillers(_normalize(query));
    if (normalizedQuery.isEmpty) {
      return 0;
    }
    int best = 0;
    for (final ServiceSearchEntry entry in entries ?? catalog) {
      final int value = score(entry, normalizedQuery);
      if (value > best) best = value;
    }
    return best;
  }

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
