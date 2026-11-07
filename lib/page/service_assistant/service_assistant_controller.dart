import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:town_pass/page/service_assistant/gemini_service_matcher.dart';
import 'package:town_pass/page/service_assistant/rag/rag_document.dart';
import 'package:town_pass/page/service_assistant/rag/service_rag.dart';
import 'package:town_pass/page/service_assistant/service_search.dart';
import 'package:town_pass/service/recommendation_service.dart';
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
  ServiceAssistantController({RagGenerator? generator, ServiceRag? rag, UserTraitRecorder? traits})
      : generator = generator ?? rag?.generator ?? GeminiServiceMatcher(),
        traits = traits ?? UserTraitRecorder(),
        _ragFuture = rag == null ? null : Future.value(rag);

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
        // GeminiServiceMatcher 同時負責生成與問句向量化
        embedder: generator is QueryEmbedder ? generator as QueryEmbedder : null,
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

    final List<ServiceSearchEntry> keywordResults = ServiceSearch.search(query);
    final bool confident = ServiceSearch.topScore(query) >= confidentScore;

    if (confident || !generator.isEnabled) {
      if (keywordResults.isNotEmpty) {
        _recordTraits((recorder) => recorder.recordKeywordMatch(query, keywordResults.first));
      }
      _reply(_keywordReply(keywordResults).withQuery(query));
      return;
    }

    isThinking.value = true;
    _reply(const ChatMessage(sender: ChatSender.assistant, text: '讓我想想…'));
    ChatMessage answer;
    RagRetrieval? retrieval;
    try {
      final ServiceRag rag = await _rag;
      retrieval = await rag.retrieve(query);
      final AiMatchResult ai = await rag.generate(retrieval);
      answer = _ragReply(ai, retrieval, keywordResults);
      if (ai.traits.isNotEmpty) {
        final String? model = generator is GeminiServiceMatcher ? (generator as GeminiServiceMatcher).model : null;
        _recordTraits((recorder) => recorder.recordInferred(query, ai.traits, model: model));
      }
    } on AiMatchException catch (error) {
      // 詳細原因已由 GeminiServiceMatcher 寫進 log；這裡告訴使用者並退回關鍵字（或檢索）結果
      answer = _keywordReply(
        keywordResults.isNotEmpty ? keywordResults : _relatedEntries(retrieval),
        note: '（${error.userMessage}，以下是關鍵字比對的結果）',
      );
    } catch (error) {
      // 辭庫載入失敗等非預期錯誤：記錄後退回關鍵字比對，小幫手仍可用
      debugPrint('[服務小幫手/RAG] 失敗：$error');
      _ragFuture = null; // 下次再試著載入
      answer = _keywordReply(keywordResults, note: '（AI 小幫手暫時無法使用，以下是關鍵字比對的結果）');
    } finally {
      isThinking.value = false;
    }

    if (isClosed) return;
    messages.removeLast(); // 移除「讓我想想」
    _reply(answer.withQuery(query));
  }

  List<ServiceSearchEntry> _relatedEntries(RagRetrieval? retrieval) =>
      (retrieval?.hits ?? const <RagHit>[]).take(maxRelatedHits).map((hit) => hit.document.action).toList();

  String _groundingNote(RagRetrieval retrieval) {
    final List<String> details = [
      retrieval.usedVectors ? '關鍵字＋語意檢索' : '關鍵字檢索',
      if (retrieval.wasRewritten) '改寫為「${retrieval.rewrittenKeywords.join('、')}」',
    ];
    return '依據服務清冊 ${retrieval.hits.length} 筆相關資料（${details.join('，')}）';
  }

  ChatMessage _ragReply(AiMatchResult ai, RagRetrieval retrieval, List<ServiceSearchEntry> keywordResults) {
    if (ai.entries.isNotEmpty) {
      return ChatMessage(
        sender: ChatSender.assistant,
        text: ai.reply.isNotEmpty ? ai.reply : '我找到這些服務，點一下就能使用：',
        results: ai.entries,
        groundingNote: _groundingNote(retrieval),
      );
    }
    // AI 判斷參考資料裡沒有合適服務；檢索或關鍵字有勉強對到的，仍列出讓使用者參考
    final List<ServiceSearchEntry> related =
        keywordResults.isNotEmpty ? keywordResults : _relatedEntries(retrieval);
    if (related.isNotEmpty) {
      return ChatMessage(
        sender: ChatSender.assistant,
        text: '${ai.reply.isNotEmpty ? ai.reply : '我不太確定你要的是哪個服務'}\n你可以看看這些是否相關：',
        results: related,
        groundingNote: retrieval.hits.isEmpty ? null : _groundingNote(retrieval),
      );
    }
    return ChatMessage(
      sender: ChatSender.assistant,
      text: '${ai.reply.isNotEmpty ? ai.reply : '抱歉，我找不到相關的服務'}\n換個說法試試看，例如：',
      suggestions: suggestions,
    );
  }

  ChatMessage _keywordReply(List<ServiceSearchEntry> results, {String? note}) {
    final String prefix = note == null ? '' : '$note\n';
    if (results.isEmpty) {
      return ChatMessage(
        sender: ChatSender.assistant,
        text: '$prefix抱歉，我找不到相關的服務\n換個說法試試看，例如：',
        suggestions: suggestions,
      );
    }
    return ChatMessage(
      sender: ChatSender.assistant,
      text: '$prefix${results.length == 1 ? '我找到這個服務：' : '我找到這些服務，點一下就能使用：'}',
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
