import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/core/services/firebase_service.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Support Chat'),
        backgroundColor: AppColors.primaryRed,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/dashboard');
            }
          },
        ),
      ),
      body: Builder(
        builder: (context) {
          final fbUser = fb_auth.FirebaseAuth.instance.currentUser;
          if (fbUser == null) {
            return const Center(child: Text('Please login to chat'));
          }
          return _ChatView(fbUser: fbUser);
        },
      ),
    );
  }
}

class _ChatView extends StatefulWidget {
  final fb_auth.User fbUser;
  const _ChatView({required this.fbUser});

  @override
  State<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<_ChatView> {
  final FirebaseService _firebase = FirebaseService();
  late final InMemoryChatController _chatController;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _chatController = InMemoryChatController();
    _loadMessages();
  }

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    try {
      final docs = await _firebase.listDocuments(
        collectionId: AppConfig.messagesCollection,
        queries: [
          FQuery.equal('chatId', 'general'),
          FQuery.orderAsc('sentAt'),
          FQuery.limit(50),
        ],
      );

      for (final data in docs) {
        final msg = Message.text(
          id: data['\$id'] as String? ?? const Uuid().v4(),
          authorId: data['senderId'] as String? ?? 'unknown',
          text: data['message'] as String? ?? '',
          createdAt: data['sentAt'] != null
              ? DateTime.tryParse(data['sentAt'] as String)
              : null,
        );
        await _chatController.insertMessage(msg, animated: false);
      }
    } on Exception catch (e) {
      debugPrint('Chat load error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<User?> _resolveUser(UserID id) async {
    if (id == widget.fbUser.uid) {
      return User(id: id, name: widget.fbUser.displayName ?? 'Me');
    }
    return User(id: id);
  }

  Future<void> _handleMessageSend(String text) async {
    if (text.trim().isEmpty) return;
    final user = widget.fbUser;
    final msgId = const Uuid().v4();

    // Optimistic insert
    final message = Message.text(
      id: msgId,
      authorId: user.uid,
      text: text.trim(),
      createdAt: DateTime.now(),
    );
    await _chatController.insertMessage(message);

    try {
      await _firebase.createDocument(
        collectionId: AppConfig.messagesCollection,
        data: {
          'chatId': 'general',
          'senderId': user.uid,
          'senderName': user.displayName ?? 'User',
          'message': text.trim(),
          'type': 'text',
          'sentAt': DateTime.now().toIso8601String(),
          'read': false,
        },
      );
    } on Exception catch (e) {
      debugPrint('Failed to send message: $e');
      await _chatController.removeMessage(message);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Chat(
      currentUserId: widget.fbUser.uid,
      chatController: _chatController,
      resolveUser: _resolveUser,
      onMessageSend: _handleMessageSend,
      theme: ChatTheme.fromThemeData(Theme.of(context)),
    );
  }
}
