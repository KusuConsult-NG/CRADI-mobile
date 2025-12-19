import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/core/services/appwrite_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:flutter_chat_ui/flutter_chat_ui.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Support Chat'),
        backgroundColor: AppColors.primaryRed,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<types.User?>(
        future: _getCurrentChatUser(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final chatUser = snapshot.data;
          if (chatUser == null) {
            return const Center(child: Text('Please login to chat'));
          }

          return _ChatView(user: chatUser);
        },
      ),
    );
  }

  Future<types.User?> _getCurrentChatUser() async {
    final appwrite = AppwriteService();
    final user = await appwrite.getCurrentUser();

    if (user == null) return null;

    return types.User(id: user.$id, firstName: user.name);
  }
}

class _ChatView extends StatefulWidget {
  final types.User user;

  const _ChatView({required this.user});

  @override
  State<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<_ChatView> {
  final AppwriteService _appwrite = AppwriteService();
  final List<types.Message> _messages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    try {
      final docs = await _appwrite.listDocuments(
        collectionId: AppwriteService.messagesCollectionId,
        queries: ['chatId=general'],
      );

      final messages = docs.documents.map((doc) {
        final data = doc.data;
        return types.TextMessage(
          author: types.User(id: data['senderId'] ?? 'unknown'),
          createdAt: DateTime.parse(
            data['sentAt'] ?? DateTime.now().toIso8601String(),
          ).millisecondsSinceEpoch,
          id: doc.$id,
          text: data['message'] ?? '',
        );
      }).toList();

      setState(() {
        _messages.clear();
        _messages.addAll(messages);
        _isLoading = false;
      });
    } on Exception {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSendPressed(types.PartialText message) async {
    try {
      await _appwrite.createDocument(
        collectionId: AppwriteService.messagesCollectionId,
        data: {
          'chatId': 'general',
          'senderId': widget.user.id,
          'senderName': widget.user.firstName ?? 'User',
          'message': message.text,
          'type': 'text',
          'sentAt': DateTime.now().toIso8601String(),
          'read': false,
        },
      );

      // Reload messages
      await _loadMessages();
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send message: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Chat(
      messages: _messages,
      onSendPressed: _handleSendPressed,
      user: widget.user,
      theme: DefaultChatTheme(
        primaryColor: AppColors.primaryRed,
        backgroundColor: AppColors.background,
        inputBackgroundColor: Colors.white,
        inputTextColor: Colors.black, // Fix white text color issue
        inputBorderRadius: const BorderRadius.all(Radius.circular(12)),
        inputPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        inputMargin: const EdgeInsets.all(16),
        inputTextStyle: const TextStyle(
          fontSize: 16,
          color: Colors.black, // Ensure text is black, not white
          height: 1.5,
        ),
        // Make input box larger
        inputContainerDecoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
      // Make text input box larger
      textMessageOptions: const TextMessageOptions(isTextSelectable: true),
    );
  }
}
