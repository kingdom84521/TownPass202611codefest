import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/page/service_assistant/service_search.dart';

List<String> _titles(String query) => ServiceSearch.search(query).map((entry) => entry.title).toList();

void main() {
  group('ServiceSearch', () {
    test('matches service title directly', () {
      expect(_titles('圖書借閱').first, '圖書借閱');
      expect(_titles('1999').first, '1999');
    });

    test('matches colloquial synonyms inside a sentence', () {
      expect(_titles('我想借書').first, '圖書借閱');
      expect(_titles('請問要怎麼繳水費？').first, '用水服務');
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

    test('limits number of results', () {
      expect(_titles('預約掛號疫苗叫號').length, lessThanOrEqualTo(ServiceSearch.maxResults));
    });
  });
}
