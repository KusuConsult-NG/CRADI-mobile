import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:climate_app/core/services/firebase_service.dart';
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
  final FirebaseService _firebase = FirebaseService();

  /// Check if user is authenticated
  bool get isAuthenticated => FirebaseAuth.instance.currentUser != null;

  /// Send a message
  Future<void> sendMessage(String text, {String chatId = 'general'}) async {
    if (text.trim().isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw ChatException(
        'You must be logged in to send messages. Please login and try again.',
      );
    }

    final messageData = {
      'chatId': chatId,
      'senderId': user.uid,
      'senderName': user.displayName ?? 'Anonymous',
      'message': text,
      'type': 'text',
      'sentAt': DateTime.now().toIso8601String(),
      'read': false,
    };

    try {
      await _firebase.createDocument(
        collectionId: AppConfig.messagesCollection,
        data: messageData,
      );
      developer.log('Message sent successfully', name: 'ChatProvider');
    } on Exception catch (e) {
      developer.log('Error sending message: $e');
      throw ChatException('Failed to send message: $e');
    }
  }

  /// Get messages stream using Firestore snapshots — replaces Appwrite Realtime.
  Stream<List<Map<String, dynamic>>> getMessages({String chatId = 'general'}) {
    return _firebase.subscribeToCollection(
      collectionId: AppConfig.messagesCollection,
      queries: [
        FQuery.equal('chatId', chatId),
        FQuery.orderDesc('sentAt'),
        FQuery.limit(50),
      ],
    );
  }
}
