import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:town_pass/page/service_assistant/rag/rag_document.dart';
import 'package:town_pass/page/service_assistant/rag/service_rag.dart';
import 'package:town_pass/page/service_assistant/service_search.dart';

/// AI 判斷的結果：挑出的服務，以及給使用者的一句話。
class AiMatchResult {
  const AiMatchResult({required this.entries, required this.reply, this.documents = const []});

  final List<ServiceSearchEntry> entries;
  final String reply;

  /// RAG 模式下，AI 選中的辭庫文件（與 [entries] 一一對應）。
  final List<RagDocument> documents;
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
/// - 只送出「使用者問句」與「服務名稱／說明」，不送帳號、定位等個資。
/// - 回傳格式以 JSON Schema 的 enum 限制為給定清單內的名稱，收到後再驗證一次，
///   AI 無法讓 App 開啟清單以外的網址。
/// - 金鑰與模型由編譯參數帶入：flutter run --dart-define-from-file=gemini.env.json
///
/// RAG 流程（[ServiceRag]）使用 [generate] 與 [rewriteQuery]；[match] 是把整份清單交給 AI 的舊做法，保留給相容與測試。
class GeminiServiceMatcher implements RagGenerator {
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
  static const int maxRewriteKeywords = 5;
  static const String _logTag = '[服務小幫手/AI]';

  final String _apiKey;
  final String model;
  final http.Client _client;
  final Duration timeout;

  /// 沒有設定金鑰時不呼叫 AI，小幫手只用關鍵字比對。
  @override
  bool get isEnabled => _apiKey.isNotEmpty;

  /// 舊做法：把整份 [catalog] 交給 AI 挑。
  Future<AiMatchResult> match(String query, List<ServiceSearchEntry> catalog) async {
    final Map<String, ServiceSearchEntry> byTitle = {for (final entry in catalog) entry.title: entry};
    final _Output output = await _call(
      query: query,
      systemText: _rules(intro: '請從下方服務清單中挑出最符合的服務', listName: '服務清單（名稱｜說明）') +
          catalog.map((entry) => '- ${entry.title}｜${entry.description}${entry.isComingSoon ? '｜（尚未開放）' : ''}').join('\n'),
      schema: _matchSchema(catalog.map((entry) => entry.title).toList()),
    );
    final List<String> titles = _validTitles(output.json, byTitle.keys.toSet());
    final AiMatchResult result = AiMatchResult(
      entries: titles.map((title) => byTitle[title]!).toList(),
      reply: (output.json['reply'] as String? ?? '').trim(),
    );
    _logSuccess(output, query, result.entries.map((e) => e.title).toList());
    return result;
  }

  /// RAG 的「生成」：只把檢索到的 [context] 交給 AI，AI 只能從這些文件挑選並據此回答。
  @override
  Future<AiMatchResult> generate(String query, List<RagHit> context) async {
    final Map<String, RagDocument> byTitle = {for (final hit in context) hit.document.title: hit.document};
    final _Output output = await _call(
      query: query,
      systemText: _rules(
            intro: '下方是依使用者問句，從「台北通服務清冊」檢索出的參考資料（依相關程度排序）。'
                '只能根據這些資料回答，請挑出最符合的服務',
            listName: '參考資料（名稱｜說明｜狀態）',
          ) +
          context.map((hit) => hit.document.toContextLine()).join('\n'),
      schema: _matchSchema(byTitle.keys.toList()),
    );
    final List<RagDocument> documents =
        _validTitles(output.json, byTitle.keys.toSet()).map((title) => byTitle[title]!).toList();
    final AiMatchResult result = AiMatchResult(
      entries: documents.map((document) => document.action).toList(),
      reply: (output.json['reply'] as String? ?? '').trim(),
      documents: documents,
    );
    _logSuccess(output, query, documents.map((d) => d.id).toList(), contextSize: context.length);
    return result;
  }

  /// RAG 的「查詢改寫」：檢索不到或太弱時，把問句改寫成辭庫裡常見的繁體中文關鍵詞再檢索一次。
  /// 用來接住英文、日文、越南文問句，以及口語、錯字。
  @override
  Future<List<String>> rewriteQuery(String query) async {
    final _Output output = await _call(
      query: query,
      systemText: '你是「台北通 Town Pass」App 的搜尋助手。使用者可能用任何語言、口語或錯字描述需求，'
          '請改寫成 1 到 $maxRewriteKeywords 個繁體中文關鍵詞，用台北市政服務常見的說法'
          '（例如：借書、報案、詐騙、繳費、停車費、陳情、噪音、掛號、災情、寵物）。'
          '只輸出關鍵詞，不要解釋；與市政服務完全無關時回傳空陣列。',
      schema: {
        'type': 'object',
        'properties': {
          'keywords': {
            'type': 'array',
            'items': {'type': 'string'},
          },
        },
        'required': ['keywords'],
      },
    );
    final List<String> keywords = ((output.json['keywords'] as List<dynamic>?) ?? const [])
        .whereType<String>()
        .map((keyword) => keyword.trim())
        .where((keyword) => keyword.isNotEmpty)
        .toSet()
        .take(maxRewriteKeywords)
        .toList();
    _log('改寫 ${output.elapsedMs}ms，model=$model，關鍵詞=$keywords${kDebugMode ? '，問句「$query」' : ''}');
    return keywords;
  }

  // ── 共用 ──────────────────────────────────────────────────────────────

  String _rules({required String intro, required String listName}) =>
      '你是「台北通 Town Pass」App 的服務小幫手。使用者會用口語描述想做的事，'
      '$intro（最多 $maxMatches 個，依符合程度排序）。\n'
      '規則：\n'
      '1. 只能使用清單中的名稱，一字不差。\n'
      '2. 沒有合適的服務就回傳空陣列，不要硬湊。\n'
      '3. 只有「人身正處於危險」（受傷、昏倒、冒煙或疑似火災、聞到瓦斯、被攻擊等）時，第一個才是「緊急求救」，'
      '且不要再推薦「1999」（1999 是市民熱線，不是急救）；'
      '設施損壞、噪音、路面問題等一般反映，即使提到危險，也不要放「緊急求救」。\n'
      '4. 優先選擇已開放的服務；標示「尚未開放」的服務只有在最符合時才選。\n'
      '5. reply 用繁體中文、一句話（30 字內），親切說明為什麼推薦這些服務；'
      '找不到時說明 App 目前沒有這項服務。你只負責推薦服務，不要承諾會處理、派人或回覆結果。\n\n'
      '$listName：\n';

  Map<String, Object> _matchSchema(List<String> titles) => {
        'type': 'object',
        'properties': {
          'matches': {
            'type': 'array',
            'items': {'type': 'string', 'enum': titles},
          },
          'reply': {'type': 'string'},
        },
        'required': ['matches', 'reply'],
      };

  List<String> _validTitles(Map<String, dynamic> output, Set<String> allowed) {
    final List<String> titles = ((output['matches'] as List<dynamic>?) ?? const []).whereType<String>().toList();
    final List<String> unknown = titles.where((title) => !allowed.contains(title)).toList();
    if (unknown.isNotEmpty) {
      // 理論上 enum 已限制；仍出現就丟棄並記錄，不讓 AI 帶使用者去清單外的地方
      _log('丟棄清單外的名稱：$unknown');
    }
    return titles.where(allowed.contains).toSet().take(maxMatches).toList();
  }

  Future<_Output> _call({
    required String query,
    required String systemText,
    required Map<String, Object> schema,
  }) async {
    if (!isEnabled) {
      throw const AiMatchException('AI 小幫手尚未設定', '未設定 GEMINI_API_KEY');
    }

    final Stopwatch stopwatch = Stopwatch()..start();
    final Uri uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent');
    final Map<String, Object> request = {
      'systemInstruction': {
        'parts': [
          {'text': systemText},
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
        'responseJsonSchema': schema,
        // 分類與改寫不需要深度推理，降低延遲
        'thinkingConfig': {'thinkingLevel': 'MINIMAL'},
      },
    };

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
            body: jsonEncode(request),
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
    return _Output(_parseOutput(body, elapsedMs), elapsedMs);
  }

  Map<String, dynamic> _parseOutput(String body, int elapsedMs) {
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

    try {
      return jsonDecode(text) as Map<String, dynamic>;
    } on FormatException {
      throw _fail('AI 回覆格式錯誤', '結構化輸出不是 JSON finishReason=$finishReason，text=${_truncate(text)}');
    }
  }

  void _logSuccess(_Output output, String query, List<String> picked, {int? contextSize}) {
    _log('成功 ${output.elapsedMs}ms，model=$model，問句長度=${query.length}，'
        '${contextSize == null ? '' : '參考資料=$contextSize 筆，'}'
        '結果=$picked${kDebugMode ? '，問句「$query」' : ''}');
  }

  AiMatchException _fail(String userMessage, String detail) {
    _log('失敗：$detail');
    return AiMatchException(userMessage, detail);
  }

  static void _log(String message) => debugPrint('$_logTag $message');

  static String _truncate(String text, [int max = 300]) => text.length <= max ? text : '${text.substring(0, max)}…';
}

class _Output {
  const _Output(this.json, this.elapsedMs);

  final Map<String, dynamic> json;
  final int elapsedMs;
}
