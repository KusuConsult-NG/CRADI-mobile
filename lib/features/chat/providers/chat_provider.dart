import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  final SupabaseService _supabase = SupabaseService();

  /// Check if user is authenticated
  bool get isAuthenticated =>
      Supabase.instance.client.auth.currentUser != null;

  /// Send a message
  Future<void> sendMessage(String text, {String chatId = 'general'}) async {
    if (text.trim().isEmpty) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      throw ChatException(
        'You must be logged in to send messages. Please login and try again.',
      );
    }

    final messageData = {
      'chat_id': chatId,
      'sender_id': user.id,
      'sender_name': user.userMetadata?['full_name'] as String? ?? 'Anonymous',
      'message': text,
      'type': 'text',
      'sent_at': DateTime.now().toUtc().toIso8601String(),
      'read': false,
    };

    try {
      await _supabase.createDocument(
        collectionId: AppConfig.messagesCollection,
        data: messageData,
      );
      developer.log('Message sent successfully', name: 'ChatProvider');
    } on Exception catch (e) {
      developer.log('Error sending message: $e');
      throw ChatException('Failed to send message: $e');
    }
  }

  /// Get messages stream via Supabase Realtime.
  Stream<List<Map<String, dynamic>>> getMessages({String chatId = 'general'}) {
    return _supabase.subscribeToCollection(
      collectionId: AppConfig.messagesCollection,
      queries: [
        SQuery.equal('chat_id', chatId),
        SQuery.orderDesc('sent_at'),
        SQuery.limit(50),
      ],
    );
  }
}
