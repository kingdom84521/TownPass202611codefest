import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// TypeSafe AI 的 Jev（System One 模型）：不產生文字，而是對「題目」給出校準過的機率。
///
/// - 是非題（noul）：回傳「是」的機率。
/// - 選擇題（choice）：回傳每個選項的機率。
///
/// API：`POST https://api.typesafe.ai/v1/systemone`，`Authorization: Bearer <金鑰>`。
/// 金鑰用 `--dart-define-from-file=typesafe.env.json` 帶入（TYPESAFE_API_KEY，不進版控）。
class JevClient {
  JevClient({http.Client? client, String? apiKey, String? model, this.timeout = const Duration(seconds: 8)})
      : _client = client ?? http.Client(),
        _apiKey = apiKey ?? const String.fromEnvironment('TYPESAFE_API_KEY'),
        model = model ?? const String.fromEnvironment('TYPESAFE_MODEL', defaultValue: defaultModel);

  static final Uri endpoint = Uri.parse('https://api.typesafe.ai/v1/systemone');

  /// 固定版本：門檻是依這個版本調的，升版前先驗證（官方文件也建議調過門檻就固定版本）。
  static const String defaultModel = 'jev-1.14.0';

  final http.Client _client;
  final String _apiKey;
  final String model;
  final Duration timeout;

  /// 有金鑰才啟用；沒有時呼叫端退回原本的做法。
  bool get isEnabled => _apiKey.isNotEmpty && !_apiKey.contains('貼在這');

  /// 送出一組題目，回傳每題的答案（key 與題目相同）。失敗時丟出 [JevException]。
  Future<JevAnswers> decide({required Object state, required Map<String, JevQuestion> questions}) async {
    final Stopwatch watch = Stopwatch()..start();
    final http.Response response;
    try {
      response = await _client
          .post(
            endpoint,
            headers: {'Authorization': 'Bearer $_apiKey', 'Content-Type': 'application/json'},
            body: jsonEncode({
              'model': model,
              'state': state,
              'questions': {for (final MapEntry<String, JevQuestion> q in questions.entries) q.key: q.value.toJson()},
            }),
          )
          .timeout(timeout);
    } catch (error) {
      throw JevException('連線失敗：$error');
    }
    final String body = utf8.decode(response.bodyBytes);
    if (response.statusCode != 200) {
      // 錯誤內容不含金鑰；只記狀態碼與前段訊息
      throw JevException('HTTP ${response.statusCode}：${body.length > 200 ? body.substring(0, 200) : body}');
    }
    final Map<String, dynamic> json = jsonDecode(body) as Map<String, dynamic>;
    final JevAnswers answers = JevAnswers(
      model: json['model'] as String? ?? model,
      answers: (json['answers'] as Map<String, dynamic>? ?? const {}).cast<String, dynamic>(),
    );
    debugPrint('[System One/Jev] ${watch.elapsedMilliseconds}ms，model=${answers.model}，'
        '${questions.length} 題，input_tokens=${(json['usage'] as Map?)?['input_tokens']}');
    return answers;
  }
}

/// 一道題目。
sealed class JevQuestion {
  const JevQuestion(this.instructions);

  final String instructions;

  Map<String, Object?> toJson();
}

/// 是非題：回答「是」的機率。
class JevYesNo extends JevQuestion {
  const JevYesNo(super.instructions);

  @override
  Map<String, Object?> toJson() => {'type': 'noul', 'instructions': instructions};
}

/// 選擇題：每個選項（名稱 → 說明）的機率。
class JevChoice extends JevQuestion {
  const JevChoice(super.instructions, this.options);

  final Map<String, String> options;

  @override
  Map<String, Object?> toJson() => {'type': 'choice', 'instructions': instructions, 'criteria': options};
}

class JevAnswers {
  const JevAnswers({required this.model, required this.answers});

  /// 實際回答的版本，例如 jev-1.14.0。
  final String model;
  final Map<String, dynamic> answers;

  /// 是非題「是」的機率；沒有這題或格式不對時回傳 null。
  double? yes(String key) => ((answers[key] as Map?)?['noul'] as num?)?.toDouble();

  /// 選擇題：機率最高的選項與它的機率。
  (String, double)? choice(String key) {
    final Map? answer = answers[key] as Map?;
    final String? choice = answer?['choice'] as String?;
    final num? probability = (answer?['probabilities'] as Map?)?[choice] as num?;
    if (choice == null || probability == null) return null;
    return (choice, probability.toDouble());
  }
}

class JevException implements Exception {
  const JevException(this.message);

  final String message;

  @override
  String toString() => 'JevException: $message';
}
