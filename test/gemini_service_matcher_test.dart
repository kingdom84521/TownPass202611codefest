import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:town_pass/page/service_assistant/gemini_service_matcher.dart';
import 'package:town_pass/page/service_assistant/service_assistant_controller.dart';
import 'package:town_pass/page/service_assistant/service_search.dart';

/// 模擬 Gemini 的 HTTP 回應。刻意不帶 charset，確認程式一律用 UTF-8 解碼中文。
http.Response _jsonResponse(String body, int status) => http.Response.bytes(utf8.encode(body), status);

/// 包成 Gemini generateContent 的回應格式。
String _geminiBody(Map<String, Object> output, {String finishReason = 'STOP'}) => jsonEncode({
      'candidates': [
        {
          'content': {
            'role': 'model',
            'parts': [
              {'text': jsonEncode(output)},
            ],
          },
          'finishReason': finishReason,
        },
      ],
    });

GeminiServiceMatcher _matcher(MockClientHandler handler, {Duration timeout = const Duration(seconds: 8)}) =>
    GeminiServiceMatcher(apiKey: 'test-key', model: 'test-model', client: MockClient(handler), timeout: timeout);

/// 測試控制器用：不打網路，直接回傳指定結果或錯誤。
class _FakeMatcher extends GeminiServiceMatcher {
  _FakeMatcher({this.result, this.error}) : super(apiKey: 'fake');

  final AiMatchResult? result;
  final AiMatchException? error;
  int calls = 0;

  @override
  Future<AiMatchResult> match(String query, List<ServiceSearchEntry> catalog) async {
    calls++;
    if (error != null) throw error!;
    return result!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final List<ServiceSearchEntry> catalog = ServiceSearch.catalog;

  group('GeminiServiceMatcher', () {
    test('service titles are unique (AI answers by title)', () {
      final List<String> titles = catalog.map((entry) => entry.title).toList();
      expect(titles.toSet().length, titles.length);
    });

    test('is disabled without an API key', () async {
      final GeminiServiceMatcher matcher = GeminiServiceMatcher(apiKey: '', client: MockClient((_) async => http.Response('', 500)));
      expect(matcher.isEnabled, isFalse);
      await expectLater(matcher.match('借書', catalog), throwsA(isA<AiMatchException>()));
    });

    test('sends key in header, query as user content, titles as enum', () async {
      late http.Request sent;
      final GeminiServiceMatcher matcher = _matcher((request) async {
        sent = request;
        return _jsonResponse(_geminiBody({'matches': ['圖書借閱'], 'reply': '可以用圖書借閱'}), 200);
      });

      await matcher.match('想看書', catalog);

      expect(sent.url.toString(), 'https://generativelanguage.googleapis.com/v1beta/models/test-model:generateContent');
      expect(sent.url.queryParameters, isEmpty, reason: '金鑰不可放在網址');
      expect(sent.headers['x-goog-api-key'], 'test-key');
      final Map<String, dynamic> body = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(body['contents'][0]['parts'][0]['text'], '想看書');
      final List<dynamic> allowed =
          body['generationConfig']['responseJsonSchema']['properties']['matches']['items']['enum'] as List<dynamic>;
      expect(allowed, catalog.map((entry) => entry.title).toList());
      expect(body['generationConfig']['thinkingConfig'], {'thinkingLevel': 'MINIMAL'});
    });

    test('maps titles back to catalog entries and keeps the reply', () async {
      final AiMatchResult result = await _matcher(
        (_) async => _jsonResponse(_geminiBody({'matches': ['有話要說', '警政服務'], 'reply': '可以陳情或報案'}), 200),
      ).match('鄰居一直製造噪音', catalog);

      expect(result.entries.map((entry) => entry.title), ['有話要說', '警政服務']);
      expect(result.reply, '可以陳情或報案');
    });

    test('drops titles not in the catalog and limits the count', () async {
      final AiMatchResult result = await _matcher(
        (_) async => _jsonResponse(
          _geminiBody({'matches': ['不存在的服務', '停車費', '停車費', '水費', '地方稅', '學雜費'], 'reply': ''}),
          200,
        ),
      ).match('繳費', catalog);

      expect(result.entries.map((entry) => entry.title), ['停車費', '水費', '地方稅']);
    });

    test('empty matches is a valid answer', () async {
      final AiMatchResult result = await _matcher(
        (_) async => _jsonResponse(_geminiBody({'matches': <String>[], 'reply': 'App 目前沒有天氣服務'}), 200),
      ).match('今天天氣', catalog);
      expect(result.entries, isEmpty);
      expect(result.reply, 'App 目前沒有天氣服務');
    });

    test('HTTP errors become readable messages', () async {
      Future<AiMatchException> errorFor(int status) async {
        try {
          await _matcher((_) async => http.Response('{"error":{"message":"x"}}', status)).match('借書', catalog);
        } on AiMatchException catch (error) {
          return error;
        }
        fail('應該拋出 AiMatchException');
      }

      expect((await errorFor(429)).userMessage, contains('上限'));
      final AiMatchException serverError = await errorFor(500);
      expect(serverError.userMessage, 'AI 服務暫時無法使用');
      expect(serverError.detail, contains('HTTP 500'));
    });

    test('timeout', () async {
      final GeminiServiceMatcher matcher = _matcher(
        (_) => Completer<http.Response>().future, // 永遠不回應
        timeout: const Duration(milliseconds: 50),
      );
      await expectLater(
        matcher.match('借書', catalog),
        throwsA(isA<AiMatchException>().having((e) => e.userMessage, 'userMessage', contains('逾時'))),
      );
    });

    test('blocked prompt and malformed output', () async {
      await expectLater(
        _matcher((_) async => _jsonResponse(jsonEncode({'promptFeedback': {'blockReason': 'SAFETY'}}), 200))
            .match('x', catalog),
        throwsA(isA<AiMatchException>().having((e) => e.detail, 'detail', contains('SAFETY'))),
      );
      await expectLater(
        _matcher((_) async => _jsonResponse(jsonEncode({
                  'candidates': [
                    {
                      'content': {
                        'parts': [
                          {'text': 'not json'},
                        ],
                      },
                      'finishReason': 'MAX_TOKENS',
                    },
                  ],
                }), 200)).match('x', catalog),
        throwsA(isA<AiMatchException>().having((e) => e.detail, 'detail', contains('MAX_TOKENS'))),
      );
    });
  });

  group('ServiceAssistantController with AI', () {
    ServiceSearchEntry entry(String title) => catalog.firstWhere((e) => e.title == title);

    test('confident keyword match does not call AI', () async {
      final _FakeMatcher ai = _FakeMatcher(result: const AiMatchResult(entries: [], reply: ''));
      final ServiceAssistantController controller = ServiceAssistantController(aiMatcher: ai);

      await controller.send('圖書借閱');

      expect(ai.calls, 0);
      expect(controller.messages.last.results.first.title, '圖書借閱');
    });

    test('weak keyword match asks AI and shows its results', () async {
      final _FakeMatcher ai = _FakeMatcher(result: AiMatchResult(entries: [entry('有話要說')], reply: '可以向市府陳情'));
      final ServiceAssistantController controller = ServiceAssistantController(aiMatcher: ai);

      await controller.send('隔壁工地一大早就在施工好吵');

      expect(ai.calls, 1);
      expect(controller.messages.last.text, '可以向市府陳情');
      expect(controller.messages.last.results.map((e) => e.title), ['有話要說']);
      expect(controller.messages.where((m) => m.text.contains('讓我想想')), isEmpty, reason: '等待訊息要移除');
      expect(controller.isThinking.value, isFalse);
    });

    test('AI failure falls back to keyword results with a note', () async {
      final _FakeMatcher ai = _FakeMatcher(error: const AiMatchException('AI 回應逾時', 'timeout'));
      final ServiceAssistantController controller = ServiceAssistantController(aiMatcher: ai);

      await controller.send('樓上很吵');

      expect(controller.messages.last.text, contains('AI 回應逾時'));
      expect(controller.messages.last.results.first.title, '有話要說');
      expect(controller.isThinking.value, isFalse);
    });

    test('works without AI key (keyword only)', () async {
      final ServiceAssistantController controller = ServiceAssistantController(
        aiMatcher: GeminiServiceMatcher(apiKey: '', client: MockClient((_) async => http.Response('', 500))),
      );

      await controller.send('樓上很吵');

      expect(controller.messages.last.results.first.title, '有話要說');
    });
  });
}
