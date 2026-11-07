import 'package:flutter/foundation.dart';
import 'package:town_pass/page/service_assistant/assistant_text.dart';
import 'package:town_pass/page/service_assistant/gemini_service_matcher.dart';
import 'package:town_pass/page/service_assistant/rag/rag_document.dart';
import 'package:town_pass/page/service_assistant/rag/service_rag.dart';
import 'package:town_pass/page/service_assistant/service_search.dart';
import 'package:town_pass/service/system_one/jev_client.dart';
import 'package:town_pass/service/user_traits/jev_trait_classifier.dart';

/// 小幫手用 System One（Jev）決定「使用者要的是哪個服務」。
///
/// 檢索出來的每個候選服務都是一道是非題：「這個服務能不能直接幫到提問者？」，
/// Jev 回傳校準過的機率，≥ [minProbability] 的依機率由高到低最多取 [maxResults] 個。
/// 同一次請求也一併判斷使用者特徵（[JevTraitClassifier.questions]），不另外打 API。
///
/// Jev 不產生文字，回覆用固定句型。改寫問句仍交給 [fallback]（Gemini）；
/// 沒有 Jev 金鑰或 Jev 失敗時，整個生成也退回 [fallback]。
class JevServiceSelector implements RagGenerator {
  JevServiceSelector({required this.fallback, JevClient? client}) : client = client ?? JevClient();

  final RagGenerator fallback;
  final JevClient client;

  /// 選中的門檻：機率 ≥ 0.4，而且 ≥ 第一名的 [relativeToTop] 倍。
  /// 實測：淹水→災情通報 0.44 要選到；路燈→有話要說 0.75、意見回饋 0.56 要選，災情通報 0.44 不選。
  static const double minProbability = 0.4;
  static const double relativeToTop = 0.7;
  static const int maxResults = 3;

  /// 每個候選服務的說明最多帶這麼多字（題目越短越快、越便宜）。
  static const int maxDescriptionLength = 160;

  /// AiMatchResult.decidedBy 用的前綴，小幫手據此知道特徵已經判斷過、不必再問一次。
  static const String decidedByPrefix = 'jev';

  @override
  bool get isEnabled => client.isEnabled || fallback.isEnabled;

  /// 問句向量化沿用 fallback（Gemini）的實作。
  QueryEmbedder? get embedder => fallback is QueryEmbedder ? fallback as QueryEmbedder : null;

  @override
  Future<List<String>> rewriteQuery(String query) => fallback.rewriteQuery(query);

  @override
  Future<AiMatchResult> generate(String query, List<RagHit> context) async {
    if (!client.isEnabled || context.isEmpty) return fallback.generate(query, context);
    final JevAnswers answers;
    try {
      answers = await client.decide(state: query, questions: {
        ...JevTraitClassifier.questions,
        for (int i = 0; i < context.length; i++) 'service_$i': serviceQuestion(context[i].document),
      });
    } on JevException catch (error) {
      debugPrint('[System One/Jev] 選服務失敗，改用 Gemini：${error.message}');
      return fallback.generate(query, context);
    }
    final List<RagDocument> picked = pick(answers, context);
    final List<InferredTraitLog> log = [
      for (int i = 0; i < context.length; i++) (context[i].document.title, answers.yes('service_$i') ?? 0),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    debugPrint('[System One/Jev] 候選服務機率：${log.take(5).map((e) => '${e.$1} ${e.$2.toStringAsFixed(2)}').join('、')}');
    return AiMatchResult(
      entries: picked.map((document) => document.action).toList(),
      documents: picked,
      reply: replyFor(picked, lang: AssistantText.of(query)),
      traits: JevTraitClassifier.parse(answers),
      decidedBy: '$decidedByPrefix:${answers.model}',
      related: picked.isEmpty ? related(answers, context) : const [],
    );
  }

  /// 沒有選中時，機率 ≥ [minRelatedProbability] 的「可能相關」服務（最多 [maxResults] 個、同一服務只列一次）。
  /// 低於這個值的候選視為不相關，不再列給使用者（例如問失業補助時列出警政、緊急求救）。
  static const double minRelatedProbability = 0.25;

  @visibleForTesting
  static List<ServiceSearchEntry> related(JevAnswers answers, List<RagHit> context) {
    final List<(ServiceSearchEntry, double)> scored = [
      for (int i = 0; i < context.length; i++)
        if ((answers.yes('service_$i') ?? 0) case final double p when p >= minRelatedProbability)
          (context[i].document.action, p),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    final Set<String> seen = {};
    return [
      for (final (ServiceSearchEntry entry, _) in scored)
        if (seen.add(entry.title)) entry,
    ].take(maxResults).toList();
  }

  static JevYesNo serviceQuestion(RagDocument document) {
    final String body = document.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    final String description = body.length > maxDescriptionLength ? '${body.substring(0, maxDescriptionLength)}…' : body;
    return JevYesNo('「${document.title}」這個服務能不能直接幫提問者完成他想做的事、或回答他的問題？'
        '服務說明：$description');
  }

  /// 機率 ≥ [minProbability] 的候選，依機率由高到低，最多 [maxResults] 個。
  @visibleForTesting
  static List<RagDocument> pick(JevAnswers answers, List<RagHit> context) {
    final List<(RagDocument, double)> scored = [
      for (int i = 0; i < context.length; i++)
        if ((answers.yes('service_$i') ?? 0) case final double p when p >= minProbability) (context[i].document, p),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    if (scored.isEmpty) return const [];
    // 第二名以後要和第一名差不多才列出，避免明顯較弱的候選混進來
    final double cutoff = scored.first.$2 * relativeToTop;
    return [
      for (final (RagDocument document, double p) in scored.take(maxResults))
        if (p >= cutoff) document,
    ];
  }

  /// 固定句型的回覆，語言跟著問句（沒有選到服務時回傳空字串，由小幫手顯示「找不到」）。
  @visibleForTesting
  static String replyFor(List<RagDocument> picked, {AssistantText lang = AssistantText.zh}) =>
      lang.recommend([for (final RagDocument d in picked) d.title]);
}

typedef InferredTraitLog = (String, double);
