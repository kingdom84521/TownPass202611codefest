import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:town_pass/page/service_assistant/service_search.dart';

enum ChatSender { user, assistant }

class ChatMessage {
  const ChatMessage({
    required this.sender,
    required this.text,
    this.results = const [],
    this.suggestions = const [],
  });

  final ChatSender sender;
  final String text;

  /// 小幫手找到的服務，以按鈕呈現。
  final List<ServiceSearchEntry> results;

  /// 建議的問法，點了直接送出。
  final List<String> suggestions;
}

class ServiceAssistantController extends GetxController {
  static const List<String> defaultSuggestions = ['我想借書', '附近有什麼', '要看醫生', '繳水費', '我要報案'];

  final TextEditingController inputController = TextEditingController();
  final ScrollController scrollController = ScrollController();

  final RxList<ChatMessage> messages = <ChatMessage>[
    const ChatMessage(
      sender: ChatSender.assistant,
      text: '你好！我是服務小幫手 👋\n告訴我你想做什麼，我幫你找對應的服務。',
      suggestions: defaultSuggestions,
    ),
  ].obs;

  void send([String? text]) {
    final String query = (text ?? inputController.text).trim();
    if (query.isEmpty) {
      return;
    }
    inputController.clear();

    final List<ServiceSearchEntry> results = ServiceSearch.search(query);
    messages
      ..add(ChatMessage(sender: ChatSender.user, text: query))
      ..add(
        results.isEmpty
            ? const ChatMessage(
                sender: ChatSender.assistant,
                text: '抱歉，我找不到相關的服務 🙇\n換個說法試試看，例如：',
                suggestions: defaultSuggestions,
              )
            : ChatMessage(
                sender: ChatSender.assistant,
                text: results.length == 1 ? '我找到這個服務：' : '我找到這些服務，點一下就能使用：',
                results: results,
              ),
      );
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
