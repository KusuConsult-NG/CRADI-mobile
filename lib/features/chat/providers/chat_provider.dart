import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:developer' as developer;

class ChatProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Send a message
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _firestore.collection('chats').add({
        'text': text,
        'senderId': user.uid,
        'senderName': user.displayName ?? user.phoneNumber ?? 'User',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } on Exception catch (e) {
      developer.log('Error sending message: $e');
      rethrow;
    }
  }

  /// Get messages stream
  Stream<QuerySnapshot> getMessages() {
    return _firestore
        .collection('chats')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }
}
