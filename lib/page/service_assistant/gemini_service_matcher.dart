import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:town_pass/page/service_assistant/service_search.dart';

/// AI 判斷的結果：從 [ServiceSearch.catalog] 挑出的服務，以及給使用者的一句話。
class AiMatchResult {
  const AiMatchResult({required this.entries, required this.reply});

  final List<ServiceSearchEntry> entries;
  final String reply;
}

/// AI 判斷失敗。[userMessage] 給使用者看，[detail] 寫進 log 供追查。
class AiMatchException implements Exception {
  const AiMatchException(this.userMessage, this.detail);

  final String userMessage;
  final String detail;

  @override
  String toString() => 'AiMatchException: $detail';
}

/// 用 Gemini 把自然語言問句對應到 App 內的服務。
///
/// - 只送出「使用者問句」與「服務名稱／說明清單」，不送帳號、定位等個資。
/// - 回傳格式以 JSON Schema 的 enum 限制為清單內的服務名稱，收到後再驗證一次，
///   AI 無法讓 App 開啟清單以外的網址。
/// - 金鑰與模型由編譯參數帶入：flutter run --dart-define-from-file=gemini.env.json
class GeminiServiceMatcher {
  GeminiServiceMatcher({
    String? apiKey,
    String? model,
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
  })  : _apiKey = apiKey ?? const String.fromEnvironment('GEMINI_API_KEY'),
        model = model ?? const String.fromEnvironment('GEMINI_MODEL', defaultValue: defaultModel),
        _client = client ?? http.Client();

  static const String defaultModel = 'gemini-3.5-flash-lite';
  static const int maxMatches = 3;
  static const String _logTag = '[服務小幫手/AI]';

  final String _apiKey;
  final String model;
  final http.Client _client;
  final Duration timeout;

  /// 沒有設定金鑰時不呼叫 AI，小幫手只用關鍵字比對。
  bool get isEnabled => _apiKey.isNotEmpty;

  Future<AiMatchResult> match(String query, List<ServiceSearchEntry> catalog) async {
    if (!isEnabled) {
      throw const AiMatchException('AI 小幫手尚未設定', '未設定 GEMINI_API_KEY');
    }

    final Map<String, ServiceSearchEntry> byTitle = {for (final entry in catalog) entry.title: entry};
    final Stopwatch stopwatch = Stopwatch()..start();
    final Uri uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent');

    http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              // 金鑰放 header 而非網址，避免出現在網址相關的 log
              'x-goog-api-key': _apiKey,
            },
            body: jsonEncode(_buildRequest(query, catalog)),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw _fail('AI 回應逾時', '逾時 ${timeout.inSeconds}s，model=$model');
    } on Exception catch (error) {
      throw _fail('目前連不上 AI 服務，請確認網路', '連線失敗：$error');
    }

    final int elapsedMs = stopwatch.elapsedMilliseconds;
    // 一律以 UTF-8 解碼，不依賴回應標頭的 charset（缺 charset 時 response.body 會把中文解成亂碼）
    final String body = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode != 200) {
      throw _fail(
        response.statusCode == 429 ? 'AI 使用量已達上限，請稍後再試' : 'AI 服務暫時無法使用',
        'HTTP ${response.statusCode}，${elapsedMs}ms，model=$model，body=${_truncate(body)}',
      );
    }

    final AiMatchResult result = _parseResponse(body, byTitle, elapsedMs);
    _log('成功 ${elapsedMs}ms，model=$model，問句長度=${query.length}，'
        '結果=${result.entries.map((e) => e.title).toList()}${kDebugMode ? '，問句「$query」' : ''}');
    return result;
  }

  Map<String, Object> _buildRequest(String query, List<ServiceSearchEntry> catalog) {
    final String serviceList = catalog
        .map((entry) => '- ${entry.title}｜${entry.description}${entry.isComingSoon ? '｜（尚未開放）' : ''}')
        .join('\n');

    return {
      'systemInstruction': {
        'parts': [
          {
            'text': '你是「台北通 Town Pass」App 的服務小幫手。使用者會用口語描述想做的事，'
                '請從下方服務清單中挑出最符合的服務（最多 $maxMatches 個，依符合程度排序）。\n'
                '規則：\n'
                '1. 只能使用清單中的服務名稱，一字不差。\n'
                '2. 沒有合適的服務就回傳空陣列，不要硬湊。\n'
                '3. 只有「人身正處於危險」（受傷、昏倒、冒煙或疑似火災、聞到瓦斯、被攻擊等）時，第一個才是「緊急求救」，'
                '且不要再推薦「1999」（1999 是市民熱線，不是急救）；'
                '設施損壞、噪音、路面問題等一般反映，即使提到危險，也不要放「緊急求救」。\n'
                '4. 優先選擇已開放的服務；標示「尚未開放」的服務只有在最符合時才選。\n'
                '5. reply 用繁體中文、一句話（30 字內），親切說明為什麼推薦這些服務；'
                '找不到時說明 App 目前沒有這項服務。你只負責推薦服務，不要承諾會處理、派人或回覆結果。\n\n'
                '服務清單（名稱｜說明）：\n$serviceList',
          },
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': query},
          ],
        },
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
        'responseJsonSchema': {
          'type': 'object',
          'properties': {
            'matches': {
              'type': 'array',
              'items': {
                'type': 'string',
                'enum': catalog.map((entry) => entry.title).toList(),
              },
            },
            'reply': {'type': 'string'},
          },
          'required': ['matches', 'reply'],
        },
        // 分類工作不需要深度推理，降低延遲
        'thinkingConfig': {'thinkingLevel': 'MINIMAL'},
      },
    };
  }

  AiMatchResult _parseResponse(String body, Map<String, ServiceSearchEntry> byTitle, int elapsedMs) {
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(body) as Map<String, dynamic>;
    } on FormatException {
      throw _fail('AI 回覆格式錯誤', '回應不是 JSON，${elapsedMs}ms，body=${_truncate(body)}');
    }

    final String? blockReason = (json['promptFeedback'] as Map<String, dynamic>?)?['blockReason'] as String?;
    if (blockReason != null) {
      throw _fail('這個問題 AI 無法回答，請換個說法', '問句被擋下 blockReason=$blockReason');
    }

    final List<dynamic> candidates = (json['candidates'] as List<dynamic>?) ?? const [];
    if (candidates.isEmpty) {
      throw _fail('AI 沒有回覆', '回應沒有 candidates，body=${_truncate(body)}');
    }
    final Map<String, dynamic> candidate = candidates.first as Map<String, dynamic>;
    final String? finishReason = candidate['finishReason'] as String?;
    final List<dynamic> parts =
        ((candidate['content'] as Map<String, dynamic>?)?['parts'] as List<dynamic>?) ?? const [];
    final String text = parts
        .map((part) => (part as Map<String, dynamic>)['text'])
        .whereType<String>()
        .join();
    if (text.isEmpty) {
      throw _fail('AI 沒有回覆', '沒有文字內容 finishReason=$finishReason');
    }

    final Map<String, dynamic> output;
    try {
      output = jsonDecode(text) as Map<String, dynamic>;
    } on FormatException {
      throw _fail('AI 回覆格式錯誤', '結構化輸出不是 JSON finishReason=$finishReason，text=${_truncate(text)}');
    }

    final List<String> titles = ((output['matches'] as List<dynamic>?) ?? const []).whereType<String>().toList();
    final List<String> unknown = titles.where((title) => !byTitle.containsKey(title)).toList();
    if (unknown.isNotEmpty) {
      // 理論上 enum 已限制；仍出現就丟棄並記錄，不讓 AI 帶使用者去清單外的地方
      _log('丟棄清單外的服務名稱：$unknown');
    }

    return AiMatchResult(
      entries: titles.where(byTitle.containsKey).toSet().take(maxMatches).map((title) => byTitle[title]!).toList(),
      reply: (output['reply'] as String? ?? '').trim(),
    );
  }

  AiMatchException _fail(String userMessage, String detail) {
    _log('失敗：$detail');
    return AiMatchException(userMessage, detail);
  }

  static void _log(String message) => debugPrint('$_logTag $message');

  static String _truncate(String text, [int max = 300]) => text.length <= max ? text : '${text.substring(0, max)}…';
}
