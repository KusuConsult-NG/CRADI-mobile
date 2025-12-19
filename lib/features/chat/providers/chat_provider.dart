import 'package:flutter/material.dart';
import 'package:climate_app/core/services/appwrite_service.dart';
import 'package:appwrite/appwrite.dart';
import 'dart:async';
import 'dart:developer' as developer;

/// Custom exception for chat-related errors
class ChatException implements Exception {
  final String message;
  ChatException(this.message);

  @override
  String toString() => message;
}

class ChatProvider extends ChangeNotifier {
  final AppwriteService _appwrite = AppwriteService();

  /// Check if user is authenticated
  Future<bool> get isAuthenticated async {
    final user = await _appwrite.getCurrentUser();
    return user != null;
  }

  /// Send a message
  Future<void> sendMessage(String text, {String chatId = 'general'}) async {
    if (text.trim().isEmpty) return;

    final user = await _appwrite.getCurrentUser();
    if (user == null) {
      throw ChatException(
        'You must be logged in to send messages. Please login and try again.',
      );
    }

    final messageData = {
      'chatId': chatId,
      'senderId': user.$id,
      'senderName': user.name,
      'message': text,
      'type': 'text',
      'sentAt': DateTime.now().toIso8601String(),
      'read': false,
    };

    try {
      await _appwrite.createDocument(
        collectionId: AppwriteService.messagesCollectionId,
        data: messageData,
      );
      developer.log('Message sent successfully', name: 'ChatProvider');
    } on AppwriteException catch (e) {
      developer.log('Error sending message: ${e.message}');
      throw ChatException('Failed to send message: ${e.message}');
    }
  }

  /// Get messages stream using Realtime
  Stream<List<Map<String, dynamic>>> getMessages({String chatId = 'general'}) {
    final controller = StreamController<List<Map<String, dynamic>>>();
    final List<Map<String, dynamic>> messages = [];
    RealtimeSubscription? subscription;

    void updateMessages() async {
      try {
        final docs = await _appwrite.listDocuments(
          collectionId: AppwriteService.messagesCollectionId,
          queries: [
            Query.equal('chatId', chatId),
            Query.orderDesc('sentAt'),
            Query.limit(50),
          ],
        );
        messages.clear();
        messages.addAll(docs.documents.map((doc) => doc.data));
        if (!controller.isClosed) {
          controller.add(List.from(messages));
        }
      } on Exception catch (e) {
        developer.log('Error updating messages: $e');
      }
    }

    // Initial fetch
    updateMessages();

    // Subscribe to realtime updates
    const channel =
        'databases.${AppwriteService.databaseId}.collections.${AppwriteService.messagesCollectionId}.documents';

    subscription = _appwrite.subscribe(
      channels: [channel],
      callback: (event) {
        final data = event.payload;
        if (data['chatId'] == chatId) {
          // Instead of manually handling creates/updates/deletes which can be complex
          // for ordering and syncing, we trigger a re-fetch when anything changes.
          // This ensures the list is always perfectly synced with server ordering.
          updateMessages();
        }
      },
    );

    controller.onCancel = () {
      subscription?.close();
      controller.close();
    };

    return controller.stream;
  }
}
