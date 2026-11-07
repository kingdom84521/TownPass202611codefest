import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:town_pass/page/service_assistant/assistant_text.dart';
import 'package:town_pass/page/demo_scenarios/demo_scenarios_view.dart';
import 'package:town_pass/page/service_assistant/gemini_service_matcher.dart';
import 'package:town_pass/page/service_assistant/jev_service_selector.dart';
import 'package:town_pass/page/service_assistant/rag/rag_document.dart';
import 'package:town_pass/page/service_assistant/rag/service_rag.dart';
import 'package:town_pass/page/service_assistant/service_search.dart';
import 'package:town_pass/service/recommendation_service.dart';
import 'package:town_pass/service/system_one/jev_client.dart';
import 'package:town_pass/service/user_traits/jev_trait_classifier.dart';
import 'package:town_pass/service/user_traits/user_trait.dart';
import 'package:town_pass/service/user_traits/user_trait_recorder.dart';

enum ChatSender { user, assistant }

class ChatMessage {
  const ChatMessage({
    required this.sender,
    required this.text,
    this.results = const [],
    this.suggestions = const [],
    this.groundingNote,
    this.query,
  });

  final ChatSender sender;
  final String text;

  /// 這則回覆是回答哪一句問句；使用者點開服務時，用來把點擊記成該問題的佐證。
  final String? query;

  ChatMessage withQuery(String query) => ChatMessage(
        sender: sender,
        text: text,
        results: results,
        suggestions: suggestions,
        groundingNote: groundingNote,
        query: query,
      );

  /// 小幫手找到的服務，以按鈕呈現。
  final List<ServiceSearchEntry> results;

  /// 建議的問法，點了直接送出。
  final List<String> suggestions;

  /// RAG 回答的依據說明，例如「依據服務清冊 6 筆相關資料」；非 RAG 回答為 null。
  final String? groundingNote;
}

class ServiceAssistantController extends GetxController {
  /// [generator] 預設為 Gemini；[rag] 可直接注入（測試用），否則第一次需要時從辭庫載入。
  /// [traits] 記錄從提問推論的使用者特徵（本機 SQLite），預設寫入 App 共用的資料庫。
  ServiceAssistantController({
    RagGenerator? generator,
    ServiceRag? rag,
    UserTraitRecorder? traits,
    JevTraitClassifier? systemOne,
  })  : generator = generator ?? rag?.generator ?? JevServiceSelector(fallback: GeminiServiceMatcher()),
        traits = traits ?? UserTraitRecorder(),
        systemOne = systemOne ?? JevTraitClassifier(),
        _ragFuture = rag == null ? null : Future.value(rag);

  @override
  void onReady() {
    super.onReady();
    // 從「示範題組」進來：自動依序提問（每題等回覆與特徵寫入完成再問下一題）
    if (Get.arguments case final DemoRun demo) _runDemo(demo.questions);
  }

  Future<void> _runDemo(List<String> questions) async {
    for (final String question in questions) {
      if (isClosed) return;
      await Future<void>.delayed(const Duration(milliseconds: 600)); // 讓畫面看得出一題一題問
      await send(question);
      await lastTraitRecord;
    }
  }

  /// System One（Jev）判斷特徵：有金鑰時每個問題都問（關鍵字直接回覆的也問），取代 Gemini 順帶推論的特徵。
  final JevTraitClassifier systemOne;

  /// 每個問題都用 Jev 判斷特徵；失敗時退回 [fallback]（Gemini 順帶推論的特徵，沒有就不記）。
  void _classifyTraits(String query, {List<InferredTrait> fallback = const [], String? fallbackModel}) {
    _recordTraits((recorder) async {
      List<InferredTrait> inferred = fallback;
      String? model = fallbackModel;
      if (systemOne.isEnabled) {
        try {
          inferred = await systemOne.classify(query);
          model = systemOne.model;
          debugPrint('[System One/Jev] 推論特徵：$inferred');
        } on JevException catch (error) {
          debugPrint('[System One/Jev] 失敗，改用 ${fallback.isEmpty ? '不記' : 'Gemini 的特徵'}：${error.message}');
        }
      }
      if (inferred.isNotEmpty) await recorder.recordInferred(query, inferred, model: model);
    });
  }

  final UserTraitRecorder traits;

  /// 最近一次特徵寫入；寫入不阻擋對話，測試可 await 這個值確認寫完。
  Future<void> lastTraitRecord = Future.value();

  void _recordTraits(Future<void> Function(UserTraitRecorder recorder) record) {
    lastTraitRecord = record(traits).catchError((Object error) => debugPrint('[使用者特徵] 失敗：$error'));
  }

  /// 使用者點開小幫手推薦的服務：先記錄（點擊是比文字更可靠的佐證），再開啟。
  void openResult(ChatMessage message, ServiceSearchEntry entry) {
    final String? query = message.query;
    if (query != null) _recordTraits((recorder) => recorder.recordOpened(query, entry));
    entry.open();
  }

  static const List<String> defaultSuggestions = ['我想借書', '附近有什麼', '要看醫生', '繳水費', '我要報案'];

  /// 建議問法：依使用者特徵排序（推薦服務未註冊或沒有特徵時就是 [defaultSuggestions]）。
  static List<String> get suggestions => RecommendationService.maybe?.assistantChips() ?? defaultSuggestions;


  /// 關鍵字比對達到這個分數（約等於名稱直接命中）就直接回覆，不呼叫 AI。
  static const int confidentScore = 20;

  /// AI 判斷沒有合適服務時，列出幾筆檢索結果供參考。
  static const int maxRelatedHits = 3;

  final RagGenerator generator;
  Future<ServiceRag>? _ragFuture;

  Future<ServiceRag> get _rag => _ragFuture ??= ServiceRag.load(
        generator: generator,
        // 問句向量化由 Gemini 負責（Jev 選服務時沿用它的 fallback）
        embedder: switch (generator) {
          final JevServiceSelector selector => selector.embedder,
          final QueryEmbedder embedder => embedder,
          _ => null,
        },
      );

  final TextEditingController inputController = TextEditingController();
  final ScrollController scrollController = ScrollController();

  /// 等待 AI 回覆中；期間不接受新問題，避免回覆順序錯亂。
  final RxBool isThinking = false.obs;

  final RxList<ChatMessage> messages = <ChatMessage>[
    ChatMessage(
      sender: ChatSender.assistant,
      text: '你好！我是服務小幫手\n告訴我你想做什麼，我幫你找對應的服務。',
      suggestions: suggestions,
    ),
  ].obs;

  Future<void> send([String? text]) async {
    final String query = (text ?? inputController.text).trim();
    if (query.isEmpty || isThinking.value) {
      return;
    }
    inputController.clear();
    messages.add(ChatMessage(sender: ChatSender.user, text: query));
    // 英文問就用英文答（服務名稱仍是 App 裡的中文名稱）
    final AssistantText lang = AssistantText.of(query);

    final List<ServiceSearchEntry> keywordResults = ServiceSearch.search(query);
    final bool confident = ServiceSearch.topScore(query) >= confidentScore;

    if (confident || !generator.isEnabled) {
      if (keywordResults.isNotEmpty) {
        _recordTraits((recorder) => recorder.recordKeywordMatch(query, keywordResults.first));
      }
      if (systemOne.isEnabled) _classifyTraits(query);
      _reply(_keywordReply(keywordResults, lang).withQuery(query));
      return;
    }

    isThinking.value = true;
    _reply(ChatMessage(sender: ChatSender.assistant, text: lang.thinking));
    ChatMessage answer;
    RagRetrieval? retrieval;
    try {
      final ServiceRag rag = await _rag;
      retrieval = await rag.retrieve(query);
      final AiMatchResult ai = await rag.generate(retrieval);
      answer = _ragReply(ai, retrieval, keywordResults, lang);
      final String? decidedBy = ai.decidedBy;
      if (decidedBy != null && decidedBy.startsWith(JevServiceSelector.decidedByPrefix)) {
        // System One 選服務時已一併判斷特徵，不必再問一次
        if (ai.traits.isNotEmpty) {
          _recordTraits((recorder) => recorder.recordInferred(query, ai.traits, model: decidedBy));
        }
      } else {
        _classifyTraits(
          query,
          fallback: ai.traits,
          fallbackModel: generator is GeminiServiceMatcher ? (generator as GeminiServiceMatcher).model : null,
        );
      }
    } on AiMatchException catch (error) {
      // 詳細原因已由 GeminiServiceMatcher 寫進 log；這裡告訴使用者並退回關鍵字（或檢索）結果
      answer = _keywordReply(
        keywordResults.isNotEmpty ? keywordResults : _relatedEntries(retrieval),
        lang,
        note: lang.keywordFallback(lang.english ? lang.aiUnavailable : error.userMessage),
      );
    } catch (error) {
      // 辭庫載入失敗等非預期錯誤：記錄後退回關鍵字比對，小幫手仍可用
      debugPrint('[服務小幫手/RAG] 失敗：$error');
      _ragFuture = null; // 下次再試著載入
      answer = _keywordReply(keywordResults, lang, note: lang.keywordFallback(lang.aiUnavailable));
    } finally {
      isThinking.value = false;
    }

    if (isClosed) return;
    messages.removeLast(); // 移除「讓我想想」
    _reply(answer.withQuery(query));
  }

  List<ServiceSearchEntry> _relatedEntries(RagRetrieval? retrieval) =>
      _distinct((retrieval?.hits ?? const <RagHit>[]).map((hit) => hit.document.action)).take(maxRelatedHits).toList();

  /// 同一個服務只列一次（辭庫裡不同文件可能指向同一個服務，例如 110／119 都是「緊急求救」）。
  static List<ServiceSearchEntry> _distinct(Iterable<ServiceSearchEntry> entries) {
    final Set<String> seen = {};
    return [
      for (final ServiceSearchEntry entry in entries)
        if (seen.add(entry.title)) entry,
    ];
  }

  String _groundingNote(RagRetrieval retrieval, AssistantText lang) => lang.grounding(
        hits: retrieval.hits.length,
        usedVectors: retrieval.usedVectors,
        rewritten: retrieval.wasRewritten ? retrieval.rewrittenKeywords : const [],
      );

  ChatMessage _ragReply(
    AiMatchResult ai,
    RagRetrieval retrieval,
    List<ServiceSearchEntry> keywordResults,
    AssistantText lang,
  ) {
    if (ai.entries.isNotEmpty) {
      return ChatMessage(
        sender: ChatSender.assistant,
        text: ai.reply.isNotEmpty ? ai.reply : lang.foundMany,
        results: _distinct(ai.entries),
        groundingNote: _groundingNote(retrieval, lang),
      );
    }
    // AI 判斷參考資料裡沒有合適服務。System One 決定時只列它認為「可能相關」的（被它判為不相關的不再列）；
    // Gemini 決定時沿用原本做法：檢索或關鍵字有勉強對到的，仍列出讓使用者參考
    final List<ServiceSearchEntry> related = ai.related ??
        (keywordResults.isNotEmpty ? _distinct(keywordResults) : _relatedEntries(retrieval));
    if (ai.related != null && related.isEmpty) {
      return ChatMessage(
        sender: ChatSender.assistant,
        text: lang.noServiceIn1999,
        suggestions: suggestions,
      );
    }
    if (related.isNotEmpty) {
      return ChatMessage(
        sender: ChatSender.assistant,
        text: '${ai.reply.isNotEmpty ? ai.reply : lang.notSure}\n${lang.maybeRelated}',
        results: related,
        groundingNote: retrieval.hits.isEmpty ? null : _groundingNote(retrieval, lang),
      );
    }
    return ChatMessage(
      sender: ChatSender.assistant,
      text: '${ai.reply.isNotEmpty ? ai.reply : lang.notFound}\n${lang.tryRephrase}',
      suggestions: suggestions,
    );
  }

  ChatMessage _keywordReply(List<ServiceSearchEntry> results, AssistantText lang, {String? note}) {
    final String prefix = note == null ? '' : '$note\n';
    if (results.isEmpty) {
      return ChatMessage(
        sender: ChatSender.assistant,
        text: '$prefix${lang.notFound}\n${lang.tryRephrase}',
        suggestions: suggestions,
      );
    }
    return ChatMessage(
      sender: ChatSender.assistant,
      text: '$prefix${results.length == 1 ? lang.foundOne : lang.foundMany}',
      results: results,
    );
  }

  void _reply(ChatMessage message) {
    if (isClosed) return;
    messages.add(message);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) return;
      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void onClose() {
    inputController.dispose();
    scrollController.dispose();
    super.onClose();
  }
}
