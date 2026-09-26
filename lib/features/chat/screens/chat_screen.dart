import 'package:flutter/material.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sp;
import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Community Chat'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
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
          final user = sp.Supabase.instance.client.auth.currentUser;
          if (user == null) {
            return const Center(child: Text('Please login to chat'));
          }
          return _ChatView(user: user);
        },
      ),
    );
  }
}

class _ChatView extends StatefulWidget {
  final sp.User user;
  const _ChatView({required this.user});

  @override
  State<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<_ChatView> {
  final SupabaseService _supabase = SupabaseService();
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
      final docs = await _supabase.listDocuments(
        collectionId: AppConfig.messagesCollection,
        queries: [
          SQuery.equal('chat_id', 'general'),
          SQuery.orderAsc('sent_at'),
          SQuery.limit(50),
        ],
      );

      for (final data in docs) {
        final id = (data['id'] ?? data['\$id'] ?? const Uuid().v4()).toString();
        final senderId = (data['sender_id'] ?? data['senderId'] ?? 'unknown').toString();
        final text = (data['message'] ?? '').toString();
        final sentAt = data['sent_at'] ?? data['sentAt'];

        final msg = Message.text(
          id: id,
          authorId: senderId,
          text: text,
          createdAt: sentAt != null ? DateTime.tryParse(sentAt.toString()) : null,
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
    if (id == widget.user.id) {
      final name = widget.user.userMetadata?['full_name'] as String? ?? 'Me';
      return User(id: id, name: name);
    }
    return User(id: id);
  }

  Future<void> _handleMessageSend(String text) async {
    if (text.trim().isEmpty) return;
    final user = widget.user;
    final msgId = const Uuid().v4();

    // Optimistic insert
    final message = Message.text(
      id: msgId,
      authorId: user.id,
      text: text.trim(),
      createdAt: DateTime.now(),
    );
    await _chatController.insertMessage(message);

    try {
      await _supabase.createDocument(
        collectionId: AppConfig.messagesCollection,
        data: {
          'chat_id': 'general',
          'sender_id': user.id,
          'sender_name': user.userMetadata?['full_name'] as String? ?? 'User',
          'message': text.trim(),
          'type': 'text',
          'sent_at': DateTime.now().toUtc().toIso8601String(),
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
      currentUserId: widget.user.id,
      chatController: _chatController,
      resolveUser: _resolveUser,
      onMessageSend: _handleMessageSend,
      theme: ChatTheme.fromThemeData(Theme.of(context)),
    );
  }
}
