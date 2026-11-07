import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:town_pass/gen/assets.gen.dart';
import 'package:town_pass/page/service_assistant/rag/rag_document.dart';
import 'package:town_pass/page/service_assistant/service_search.dart';
import 'package:town_pass/util/tp_call_dialog.dart';

/// 服務小幫手的辭庫：由 `assets/rag/service_inventory.json`（「服務」頁籤服務清冊）建成。
///
/// 建立規則：
/// 1. 清冊的每項服務（`services`）各成一份文件，同義詞沿用 [ServiceSearch.catalog]。
/// 2. 畫面入口（`entries`）若指向既有服務，只把入口名稱併為該服務的別名（例如「警政報案」）；
///    不指向服務的入口（官方卡片、熱門「施工資訊」）自成一份文件。
/// 3. 子頁項目（`subpages`，例如警政報案系統的 165、113）各成一份文件。
/// 4. 清冊範圍外、但小幫手原本就找得到的項目（帳務繳費、App 內建頁、緊急求救）
///    從 [ServiceSearch.catalog] 補進來，避免改成 RAG 後找不到。
class ServiceInventoryCorpus {
  ServiceInventoryCorpus._(this.documents, this.sourceCommit);

  static const String assetPath = 'assets/rag/service_inventory.json';

  final List<RagDocument> documents;

  /// 清冊對應的程式碼版本（`meta.sourceCommit`），寫進 log 方便追查辭庫是否過期。
  final String sourceCommit;

  static Future<ServiceInventoryCorpus> load({AssetBundle? bundle, List<ServiceSearchEntry>? catalog}) async {
    final String text = await (bundle ?? rootBundle).loadString(assetPath);
    return ServiceInventoryCorpus.fromJson(
      jsonDecode(text) as Map<String, dynamic>,
      catalog: catalog ?? ServiceSearch.catalog,
    );
  }

  factory ServiceInventoryCorpus.fromJson(Map<String, dynamic> json, {required List<ServiceSearchEntry> catalog}) {
    final Map<String, ServiceSearchEntry> catalogByTitle = {for (final entry in catalog) entry.title: entry};
    final Map<String, String> categoryNames = {
      for (final category in _list(json['categories'])) category['code'] as String: category['name'] as String,
    };
    final Map<String, String> sectionNames = {
      for (final section in _list(json['sections'])) section['id'] as String: section['name'] as String,
    };

    // 以名稱為鍵，保持加入順序；名稱必須唯一（LLM 用名稱作答）
    final Map<String, _Draft> drafts = {};
    final Map<String, _Draft> byServiceCode = {};

    // 1. 服務主檔
    for (final Map<String, dynamic> service in _list(json['services'])) {
      final String code = service['code'] as String;
      final String title = service['title'] as String;
      final String description = service['description'] as String? ?? '';
      final ServiceSearchEntry action = catalogByTitle[title] ??
          ServiceSearchEntry(
            title: title,
            description: description,
            icon: _defaultIcon(),
            keywords: const [],
            uri: service['url'] as String? ?? '',
          );
      final String? category = categoryNames[service['category']];
      final _Draft draft = _Draft(
        id: 'service:$code',
        title: title,
        action: action,
        category: category,
        keywords: [...action.keywords],
        // 不放清冊的 `note`：那是寫給開發者的備註，不是給使用者或 LLM 的服務說明
        bodyParts: [
          description,
          if (category != null) '分類：$category',
        ],
      );
      drafts[title] = draft;
      byServiceCode[code] = draft;
    }

    // 2. 畫面入口
    for (final Map<String, dynamic> entry in _list(json['entries'])) {
      final String label = entry['label'] as String;
      final String? serviceCode = entry['serviceCode'] as String?;
      final _Draft? service = serviceCode == null ? null : byServiceCode[serviceCode];
      if (service != null) {
        if (label != service.title && !service.aliases.contains(label)) service.aliases.add(label);
        continue;
      }
      if (drafts.containsKey(label)) continue;

      final String? subLabel = entry['subLabel'] as String?;
      final String? section = sectionNames[entry['section']];
      final String url = entry['url'] as String? ?? '';
      final ServiceSearchEntry action = catalogByTitle[label] ??
          ServiceSearchEntry(
            title: label,
            description: subLabel ?? section ?? '',
            icon: _entryIcons[label]?.call() ?? _defaultIcon(),
            keywords: const [],
            uri: url.startsWith('local://') || url.startsWith('http') ? url : '',
          );
      drafts[label] = _Draft(
        id: 'entry:${entry['id']}',
        title: label,
        action: action,
        keywords: [...action.keywords],
        bodyParts: [
          ?subLabel,
          if (section != null) '服務頁「$section」區塊',
          if (action.description.isNotEmpty && action.description != subLabel) action.description,
        ],
      );
    }

    // 3. 子頁項目（例如警政報案系統）
    for (final Map<String, dynamic> subpage in _list(json['subpages'])) {
      final String subpageTitle = subpage['title'] as String;
      for (final Map<String, dynamic> item in _list(subpage['items'])) {
        final String label = item['label'] as String;
        final String description = item['description'] as String? ?? '';
        final String url = item['url'] as String? ?? '';
        final bool isPhone = url.startsWith('tel://');
        // 電話號碼單獨當名稱看不懂，例如「165」改為「165 反詐騙專線」
        final String title = isPhone ? '$label $description' : label;
        if (drafts.containsKey(title)) continue;

        final ServiceSearchEntry action = switch (label) {
          // 110、119 沿用「緊急求救」的雙按鈕對話框
          '110' || '119' when catalogByTitle['緊急求救'] != null => catalogByTitle['緊急求救']!,
          _ when isPhone => ServiceSearchEntry(
              title: title,
              description: description,
              icon: Assets.svg.iconPolice.svg(),
              keywords: const [],
              onOpen: () => TPCallDialog.confirm(number: label),
            ),
          _ => ServiceSearchEntry(
              title: title,
              description: description,
              icon: Assets.svg.iconPolice.svg(),
              keywords: const [],
              uri: url,
            ),
        };
        drafts[title] = _Draft(
          id: 'subpage:${subpage['id']}:$label',
          title: title,
          action: action,
          keywords: [label, ...?_subpageKeywords[label]],
          bodyParts: [description, '$subpageTitle › ${item['group']}'],
        );
      }
    }

    // 4. 清冊範圍外的項目
    final Set<String> covered = {
      for (final _Draft draft in drafts.values) ...[draft.title, ...draft.aliases],
    };
    for (final ServiceSearchEntry entry in catalog) {
      if (covered.contains(entry.title)) continue;
      drafts[entry.title] = _Draft(
        id: 'catalog:${entry.title}',
        title: entry.title,
        action: entry,
        keywords: [...entry.keywords],
        bodyParts: [entry.description],
        source: RagSource.catalog,
      );
    }

    return ServiceInventoryCorpus._(
      List.unmodifiable(drafts.values.map((draft) => draft.build())),
      (json['meta'] as Map<String, dynamic>?)?['sourceCommit'] as String? ?? 'unknown',
    );
  }

  static List<Map<String, dynamic>> _list(Object? value) =>
      (value as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();

  static Widget _defaultIcon() => Assets.svg.iconInfo.svg();

  /// 清冊沒有記圖示的官方卡片，沿用簡易模式服務頁的圖示。
  static final Map<String, Widget Function()> _entryIcons = {
    '市政服務': () => Assets.svg.illustrationsGov.svg(),
    '防疫醫療': () => Assets.svg.iconCovidMedical.svg(),
    '市政APP': () => Assets.svg.iconMore.svg(),
    '城市生活': () => Assets.svg.illustrationsChair.svg(),
  };

  /// 子頁項目的口語說法。
  static const Map<String, List<String>> _subpageKeywords = {
    '網路報案': ['報案', '線上報案', '警察'],
    '案件查詢': ['報案進度', '查詢案件', '案件'],
    '165': ['詐騙', '被騙', '假冒', '投資詐騙', '反詐騙'],
    '113': ['家暴', '家庭暴力', '性侵', '兒少保護', '婦幼'],
    '110': ['報警', '警察'],
    '119': ['火災', '失火', '救護車'],
  };
}

class _Draft {
  _Draft({
    required this.id,
    required this.title,
    required this.action,
    required this.bodyParts,
    this.category,
    List<String>? keywords,
    this.source = RagSource.inventory,
  }) : keywords = keywords ?? [];

  final String id;
  final String title;
  final ServiceSearchEntry action;
  final List<String> bodyParts;
  final String? category;
  final List<String> keywords;
  final List<String> aliases = [];
  final RagSource source;

  RagDocument build() => RagDocument(
        id: id,
        title: title,
        body: [...bodyParts.where((part) => part.isNotEmpty), if (aliases.isNotEmpty) '又稱：${aliases.join('、')}']
            .join('；'),
        aliases: List.unmodifiable(aliases),
        keywords: List.unmodifiable(keywords),
        category: category,
        source: source,
        action: action,
      );
}
