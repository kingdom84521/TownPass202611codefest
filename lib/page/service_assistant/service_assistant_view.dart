import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:town_pass/page/service_assistant/service_assistant_controller.dart';
import 'package:town_pass/util/tp_app_bar.dart';
import 'package:town_pass/util/tp_colors.dart';
import 'package:town_pass/util/tp_service_block.dart';
import 'package:town_pass/util/tp_text.dart';

/// 服務小幫手：用對話描述需求，回覆對應的服務按鈕。
class ServiceAssistantView extends GetView<ServiceAssistantController> {
  const ServiceAssistantView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TPColors.grayscale50,
      appBar: const TPAppBar(title: '服務小幫手'),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Obx(
                () => ListView.separated(
                  controller: controller.scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: controller.messages.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 16),
                  itemBuilder: (_, index) => _MessageItem(
                    message: controller.messages[index],
                    onSuggestionTap: controller.send,
                  ),
                ),
              ),
            ),
            _InputBar(
              controller: controller.inputController,
              onSend: controller.send,
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageItem extends StatelessWidget {
  const _MessageItem({required this.message, required this.onSuggestionTap});

  final ChatMessage message;
  final ValueChanged<String> onSuggestionTap;

  bool get _isUser => message.sender == ChatSender.user;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: _isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _isUser ? TPColors.primary500 : TPColors.white,
              // 圓角與 TPButton／TPDialog 一致，靠近發話者的一角收小
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(10),
                topRight: const Radius.circular(10),
                bottomLeft: Radius.circular(_isUser ? 10 : 2),
                bottomRight: Radius.circular(_isUser ? 2 : 10),
              ),
              border: _isUser ? null : Border.all(color: TPColors.grayscale100),
            ),
            child: TPText(
              message.text,
              style: TPTextStyles.h3Regular,
              color: _isUser ? TPColors.white : TPColors.grayscale800,
            ),
          ),
        ),
        if (message.results.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final result in message.results) ...[
            TPServiceListBlock(
              icon: result.icon,
              title: result.title,
              description: result.description,
              onTap: result.open,
            ),
            const SizedBox(height: 8),
          ],
        ],
        // RAG 回答的依據：讓使用者知道推薦來自服務清冊，不是 AI 自己編的
        if (message.groundingNote != null)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: TPText(message.groundingNote, style: TPTextStyles.caption, color: TPColors.grayscale500),
          ),
        if (message.suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final suggestion in message.suggestions)
                ActionChip(
                  label: TPText(suggestion, style: TPTextStyles.bodyRegular, color: TPColors.primary600),
                  backgroundColor: TPColors.white,
                  side: const BorderSide(color: TPColors.primary500),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  onPressed: () => onSuggestionTap(suggestion),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      // 與 TPBottomSheet 相同的白底與上緣陰影
      decoration: const BoxDecoration(
        color: TPColors.white,
        boxShadow: [BoxShadow(color: Color(0x19000000), blurRadius: 6)],
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              style: TPTextStyles.h3Regular,
              decoration: InputDecoration(
                hintText: '想找什麼服務？例如：借書',
                hintStyle: TPTextStyles.h3Regular.copyWith(color: TPColors.grayscale400),
                filled: true,
                fillColor: TPColors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: TPColors.grayscale200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: TPColors.primary500, width: 2),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: '送出',
            onPressed: onSend,
            icon: const Icon(Icons.send_rounded, color: TPColors.primary500, size: 28),
          ),
        ],
      ),
    );
  }
}
