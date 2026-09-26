import 'package:flutter/material.dart';
import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'dart:developer' as developer;

/// Custom exception for chat-related errors
class ChatException implements Exception {
  final String message;
  ChatException(this.message);

  @override
  String toString() => message;
}

class ChatProvider extends ChangeNotifier {
  final SupabaseService _db = SupabaseService();

  /// Check if user is authenticated
  bool get isAuthenticated => _db.getCurrentUser() != null;

  /// Send a message
  Future<void> sendMessage(String text, {String chatId = 'general'}) async {
    if (text.trim().isEmpty) return;

    final user = _db.getCurrentUser();
    if (user == null) {
      throw ChatException(
        'You must be logged in to send messages. Please login and try again.',
      );
    }

    final messageData = {
      'chatId': chatId,
      'senderId': user.id,
      'senderName': (user.userMetadata?['name'] as String?) ?? 'Anonymous',
      'message': text,
      'type': 'text',
      'read': false,
    };

    try {
      await _db.createDocument(
        collectionId: AppConfig.messagesCollection,
        data: messageData,
      );
      developer.log('Message sent successfully', name: 'ChatProvider');
    } on Exception catch (e) {
      developer.log('Error sending message: $e');
      throw ChatException('Failed to send message: $e');
    }
  }

  /// Realtime stream of the latest messages in [chatId].
  Stream<List<Map<String, dynamic>>> getMessages({String chatId = 'general'}) {
    return _db.subscribeToCollection(
      collectionId: AppConfig.messagesCollection,
      queries: [
        FQuery.equal('chatId', chatId),
        FQuery.orderDesc('sentAt'),
        FQuery.limit(50),
      ],
    );
  }
}
