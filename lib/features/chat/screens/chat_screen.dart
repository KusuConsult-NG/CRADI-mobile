import 'dart:async';

import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/core/services/backend_failure.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:climate_app/features/chat/providers/chat_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:climate_app/core/l10n/l10n.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.profileSupportChat),
        backgroundColor: AppColors.primaryRed,
        foregroundColor: Colors.white,
        leading: IconButton(
          tooltip: context.l10n.back,
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
          final fbUser = SupabaseService().getCurrentUser();
          if (fbUser == null) {
            return Center(child: Text(context.l10n.chatLoginRequired));
          }
          return _ChatView(fbUser: fbUser);
        },
      ),
    );
  }
}

class _ChatView extends StatefulWidget {
  final sb.User fbUser;
  const _ChatView({required this.fbUser});

  @override
  State<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<_ChatView> {
  static const String _chatId = 'general';

  final SupabaseService _db = SupabaseService();
  late final ChatProvider _chat;
  late final InMemoryChatController _chatController;
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;

  /// Sender display names keyed by sender id (from the message rows).
  final Map<String, String> _senderNames = {};

  /// Optimistically inserted messages not yet echoed by the realtime stream.
  final Map<String, Message> _pending = {};

  bool _isLoading = true;
  LocalizedText? _error;

  @override
  void initState() {
    super.initState();
    _chatController = InMemoryChatController();
    _chat = context.read<ChatProvider>();
    _subscribe();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _chatController.dispose();
    super.dispose();
  }

  void _subscribe() {
    _subscription?.cancel();
    _subscription = _chat
        .getMessages(chatId: _chatId)
        .listen(
          _onMessages,
          onError: (Object e) {
            debugPrint('Chat stream error: $e');
            if (mounted) {
              setState(() {
                _isLoading = false;
                _error = (l) => l.chatLoadError;
              });
            }
          },
        );
  }

  Future<void> _onMessages(List<Map<String, dynamic>> docs) async {
    // The stream delivers the newest messages first; the chat UI expects
    // chronological order (oldest first).
    final messages = <Message>[];
    final seen = <String>{};
    for (final data in docs.reversed) {
      final id = (data[r'$id'] ?? data['id'])?.toString() ?? const Uuid().v4();
      if (!seen.add(id)) continue;
      final authorId = data['senderId']?.toString() ?? 'unknown';
      final name = data['senderName']?.toString().trim() ?? '';
      if (name.isNotEmpty) _senderNames[authorId] = name;
      messages.add(
        Message.text(
          id: id,
          authorId: authorId,
          text: data['message']?.toString() ?? '',
          createdAt: parseTimestamp(data['sentAt']),
        ),
      );
    }
    _pending.removeWhere((id, _) => seen.contains(id));
    messages.addAll(_pending.values);

    if (!mounted) return;
    await _chatController.setMessages(messages, animated: !_isLoading);
    if (mounted && (_isLoading || _error != null)) {
      setState(() {
        _isLoading = false;
        _error = null;
      });
    }
  }

  Future<User?> _resolveUser(UserID id) async {
    if (id == widget.fbUser.id) {
      return User(
        id: id,
        name: _displayName(widget.fbUser, context.l10n.chatMe),
      );
    }
    final name = _senderNames[id];
    return User(id: id, name: name);
  }

  Future<void> _handleMessageSend(String text) async {
    if (text.trim().isEmpty) return;
    final user = widget.fbUser;
    final msgId = const Uuid().v4();

    // Optimistic insert. The row is created with the same id so the realtime
    // echo replaces it instead of duplicating it.
    final message = Message.text(
      id: msgId,
      authorId: user.id,
      text: text.trim(),
      createdAt: DateTime.now(),
    );
    _pending[msgId] = message;
    await _chatController.insertMessage(message);

    try {
      await _db.createDocument(
        collectionId: AppConfig.messagesCollection,
        documentId: msgId,
        data: {
          'chatId': _chatId,
          'senderId': user.id,
          // sender_name is set by the database from the sender's profile.
          'message': text.trim(),
          'type': 'text',
          'read': false,
        },
      );
    } on Exception catch (e) {
      debugPrint('Failed to send message: $e');
      _pending.remove(msgId);
      try {
        await _chatController.removeMessage(message);
      } on Object catch (_) {
        // Already replaced by a stream emission.
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              backendFailureOf(e) == BackendFailure.rateLimited
                  ? context.l10n.chatRateLimited(backendMessageOf(e) ?? '')
                  : context.l10n.chatSendFailed(
                      ErrorHandler.getUserMessage(e, context.l10n),
                    ),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!(context.l10n)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _subscribe();
              },
              child: Text(context.l10n.retry),
            ),
          ],
        ),
      );
    }

    return Chat(
      currentUserId: widget.fbUser.id,
      chatController: _chatController,
      resolveUser: _resolveUser,
      onMessageSend: _handleMessageSend,
      theme: ChatTheme.fromThemeData(Theme.of(context)),
      // flutter_chat_ui hard-codes its English placeholders, so the empty
      // state and the composer hint stay untranslated unless they are built
      // here (every other string on this screen comes from the ARBs).
      builders: Builders(
        emptyChatListBuilder: (context) =>
            EmptyChatList(text: context.l10n.chatEmpty),
        composerBuilder: (context) =>
            Composer(hintText: context.l10n.chatComposerHint),
      ),
    );
  }

  static String _displayName(sb.User user, String fallback) {
    final n = user.userMetadata?['name'];
    return (n is String && n.trim().isNotEmpty) ? n : fallback;
  }
}
