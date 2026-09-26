import 'package:flutter/material.dart';
import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/core/constants/app_config.dart';

/// Chat data access. Messages are sent by the chat screen itself (it
/// inserts optimistically with a client-generated id).
class ChatProvider extends ChangeNotifier {
  final SupabaseService _db = SupabaseService();

  /// Check if user is authenticated
  bool get isAuthenticated => _db.getCurrentUser() != null;

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
