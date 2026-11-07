import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/page/service_assistant/assistant_text.dart';

void main() {
  group('小幫手依問句語言回覆', () {
    test('英文問句 → 英文', () {
      for (final String query in ['Where can I see pandas?', 'How do I get to Taipei 101?', 'library']) {
        expect(AssistantText.of(query).english, isTrue, reason: query);
      }
    });

    test('中文或中英夾雜 → 中文；只有數字符號也是中文', () {
      for (final String query in ['我想借書', '我要繳 parking 費', '1999', '？']) {
        expect(AssistantText.of(query).english, isFalse, reason: query);
      }
    });

    test('推薦句型：英文句子、服務名稱保留原文', () {
      expect(AssistantText.en.recommend(['圖書借閱']), 'I recommend "圖書借閱". Tap to get started:');
      expect(AssistantText.zh.recommend(['圖書借閱', '找地點']), '推薦你使用「圖書借閱」、「找地點」，點一下就能開始：');
      expect(AssistantText.en.recommend(const []), isEmpty);
    });

    test('英文的固定回覆裡沒有中文', () {
      const AssistantText en = AssistantText.en;
      final RegExp cjk = RegExp(r'[一-鿿]');
      for (final String text in [
        en.thinking,
        en.foundOne,
        en.foundMany,
        en.notSure,
        en.maybeRelated,
        en.notFound,
        en.tryRephrase,
        en.noServiceIn1999,
        en.keywordFallback(en.aiUnavailable),
        en.grounding(hits: 8, usedVectors: true),
      ]) {
        expect(cjk.hasMatch(text), isFalse, reason: text);
      }
    });
  });
}
