/// 小幫手回覆用的固定句子：依提問的語言回覆（英文問就用英文答，其他一律繁體中文）。
///
/// 服務名稱沿用 App 裡的中文名稱（按鈕上也是中文），只翻譯句子本身。
class AssistantText {
  const AssistantText._(this.english);

  final bool english;

  static const AssistantText zh = AssistantText._(false);
  static const AssistantText en = AssistantText._(true);

  /// 有拉丁字母、沒有任何中日韓文字 → 英文；其餘（含中英夾雜）→ 中文。
  static AssistantText of(String query) {
    final bool hasCjk = RegExp(r'[぀-ヿ㐀-鿿豈-﫿가-힯]').hasMatch(query);
    final bool hasLatin = RegExp(r'[A-Za-z]').hasMatch(query);
    return !hasCjk && hasLatin ? en : zh;
  }

  /// Gemini 回覆要用的語言（放進提示詞）。
  String get replyLanguage => english ? 'English' : '繁體中文';

  String get thinking => english ? 'Let me think…' : '讓我想想…';

  String recommend(List<String> titles) {
    if (titles.isEmpty) return '';
    if (english) {
      final String names = titles.map((t) => '"$t"').join(', ');
      return 'I recommend $names. Tap to get started:';
    }
    return '推薦你使用${titles.map((t) => '「$t」').join('、')}，點一下就能開始：';
  }

  String get foundOne => english ? 'I found this service:' : '我找到這個服務：';
  String get foundMany => english ? 'I found these services. Tap one to use it:' : '我找到這些服務，點一下就能使用：';

  String get notSure => english ? "I'm not sure which service you need." : '我不太確定你要的是哪個服務';
  String get maybeRelated => english ? 'These might be related:' : '你可以看看這些是否相關：';

  String get notFound => english ? "Sorry, I couldn't find a related service." : '抱歉，我找不到相關的服務';
  String get tryRephrase => english ? 'Try asking another way, for example:' : '換個說法試試看，例如：';

  String get noServiceIn1999 => english
      ? "Sorry, the app doesn't have a service for this yet.\n"
          'You can call the 1999 Taipei Citizen Hotline, or try asking another way:'
      : '抱歉，App 裡目前沒有直接相關的服務。\n可以撥打 1999 臺北市民當家熱線詢問，或換個說法試試看：';

  String keywordFallback(String reason) =>
      english ? '($reason — showing keyword matches instead)' : '（$reason，以下是關鍵字比對的結果）';

  String get aiUnavailable => english ? 'AI assistant is temporarily unavailable' : 'AI 小幫手暫時無法使用';

  String grounding({required int hits, required bool usedVectors, List<String> rewritten = const []}) {
    if (english) {
      final List<String> details = [
        usedVectors ? 'keyword + semantic search' : 'keyword search',
        if (rewritten.isNotEmpty) 'rewritten as "${rewritten.join(', ')}"',
      ];
      return 'Based on $hits related entries in the service catalog (${details.join('; ')})';
    }
    final List<String> details = [
      usedVectors ? '關鍵字＋語意檢索' : '關鍵字檢索',
      if (rewritten.isNotEmpty) '改寫為「${rewritten.join('、')}」',
    ];
    return '依據服務清冊 $hits 筆相關資料（${details.join('，')}）';
  }
}
