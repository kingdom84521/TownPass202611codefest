import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/page/bill/bill_view.dart';
import 'package:town_pass/page/service_assistant/service_search.dart';
import 'package:town_pass/util/tp_route.dart';

List<String> _titles(String query) => ServiceSearch.search(query).map((entry) => entry.title).toList();

void main() {
  group('ServiceSearch', () {
    test('matches service title directly', () {
      expect(_titles('圖書借閱').first, '圖書借閱');
      expect(_titles('1999').first, '1999');
    });

    test('matches colloquial synonyms inside a sentence', () {
      expect(_titles('我想借書').first, '圖書借閱');
      // 帳務的「水費」有實際繳費網址，排在「用水服務」（尚未上線）前面
      expect(_titles('請問要怎麼繳水費？').take(2), ['水費', '用水服務']);
      expect(_titles('我要報案').first, '警政服務');
      expect(_titles('想去看醫生').first, '聯醫掛號');
      expect(_titles('家裡淹水了').first, '災情通報');
      expect(_titles('帶狗去散步').first, '寵物安心遛');
      expect(_titles('救命 有人受傷').first, '緊急求救');
    });

    test('normalizes 臺/台 and ignores punctuation and spaces', () {
      expect(_titles('臺北 動物園!!').first, '愛遊動物園');
    });

    test('returns nothing for empty or unrelated input', () {
      expect(_titles(''), isEmpty);
      expect(_titles('   我想要   '), isEmpty);
      expect(_titles('今天晚餐吃什麼'), isEmpty);
    });

    test('finds bill payment items from the bill page', () {
      expect(_titles('我要繳停車費').first, '停車費');
      expect(_titles('繳稅').first, '地方稅');
      expect(_titles('學費').first, '學雜費');
      expect(_titles('社宅房租').first, '國/社宅租金維管費');
      expect(_titles('查繳費紀錄').first, '繳費紀錄');
    });

    test('bill entries reuse the bill page data', () {
      final ServiceSearchEntry parking = ServiceSearch.catalog.firstWhere((entry) => entry.title == '停車費');
      expect(parking.uri, BillView.popularBillItems.firstWhere((item) => item.name == '停車費').uri);
    });

    test('finds in-app pages', () {
      expect(_titles('我的帳號').first, '我的帳戶');
      expect(_titles('改個人資料').first, '基本資料');
      expect(_titles('看訊息').first, '訊息');
      expect(_titles('發票載具').first, '手機載具');
      expect(_titles('切換成英文').first, '語言');
    });

    test('in-app pages open through local:// routes', () {
      final List<ServiceSearchEntry> localEntries =
          ServiceSearch.catalog.where((entry) => entry.uri.startsWith('local://')).toList();
      expect(localEntries, isNotEmpty);
      for (final ServiceSearchEntry entry in localEntries) {
        final String route = '/${Uri.parse(entry.uri).host}';
        expect(TPRoute.page.any((page) => page.name == route), isTrue, reason: '${entry.title} → $route 沒有註冊');
      }
    });

    test('colloquial phrasing', () {
      expect(_titles('樓上很吵').first, '有話要說');
      expect(_titles('我錢包掉了').first, '警政服務');
    });

    test('keywords never contain filler words (they are stripped from queries only)', () {
      final List<String> fillers = ServiceSearch.fillerWords.map((word) => word.toLowerCase()).toList();
      for (final ServiceSearchEntry entry in ServiceSearch.catalog) {
        for (final String keyword in entry.keywords) {
          final String normalized = keyword.toLowerCase();
          final Iterable<String> hits = fillers.where(normalized.contains);
          expect(hits, isEmpty, reason: '「${entry.title}」的同義詞「$keyword」含贅字 $hits，永遠比對不到');
        }
      }
    });

    test('does not expose account suspension', () {
      expect(_titles('停用帳號').map((title) => title.contains('停用')), everyElement(isFalse));
    });

    test('limits number of results', () {
      expect(_titles('預約掛號疫苗叫號').length, lessThanOrEqualTo(ServiceSearch.maxResults));
    });
  });
}
