import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:climate_app/core/services/firebase_service.dart';
import 'package:climate_app/features/contacts/models/emergency_contact_model.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'dart:developer' as developer;

class EmergencyContactsProvider extends ChangeNotifier {
  final FirebaseService _firebase = FirebaseService();

  Future<List<EmergencyContact>> getContacts() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return [];

      final docs = await _firebase.listDocuments(
        collectionId: AppConfig.contactsCollection,
        queries: [FQuery.orderAsc('name')],
      );

      return docs
          .map(
            (data) =>
                EmergencyContact.fromFirestore(data, data['\$id'] as String),
          )
          .toList();
    } on Exception catch (e) {
      developer.log('Error getting contacts: $e');
      return [];
    }
  }

  Future<void> addContact(EmergencyContact contact) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not logged in');

      final data = contact.toFirestore();
      data['userId'] = user.uid;

      await _firebase.createDocument(
        collectionId: AppConfig.contactsCollection,
        data: data,
      );
      developer.log('Contact added: ${contact.name}');
      notifyListeners();
    } on Exception catch (e) {
      developer.log('Error adding contact: $e');
      rethrow;
    }
  }

  Future<void> updateContact(String id, EmergencyContact contact) async {
    try {
      await _firebase.updateDocument(
        collectionId: AppConfig.contactsCollection,
        documentId: id,
        data: contact.toFirestore(),
      );
      developer.log('Contact updated: $id');
      notifyListeners();
    } on Exception catch (e) {
      developer.log('Error updating contact: $e');
      rethrow;
    }
  }

  Future<void> deleteContact(String id) async {
    try {
      await _firebase.deleteDocument(
        collectionId: AppConfig.contactsCollection,
        documentId: id,
      );
      developer.log('Contact deleted: $id');
      notifyListeners();
    } on Exception catch (e) {
      developer.log('Error deleting contact: $e');
      rethrow;
    }
  }

  Future<List<EmergencyContact>> searchContacts(String query) async {
    try {
      final contacts = await getContacts();
      final lowercaseQuery = query.toLowerCase();
      return contacts
          .where(
            (c) =>
                c.name.toLowerCase().contains(lowercaseQuery) ||
                c.phone.toLowerCase().contains(lowercaseQuery),
          )
          .toList();
    } on Exception catch (e) {
      developer.log('Error searching contacts: $e');
      return [];
    }
  }

  /// Real-time stream via Firestore snapshots (replaces polling loop).
  Stream<List<EmergencyContact>> getContactsStream() {
    return _firebase
        .subscribeToCollection(
          collectionId: AppConfig.contactsCollection,
          queries: [FQuery.orderAsc('name')],
        )
        .map(
          (docs) => docs
              .map(
                (data) => EmergencyContact.fromFirestore(
                  data,
                  data['\$id'] as String,
                ),
              )
              .toList(),
        );
  }

  Stream<List<EmergencyContact>> getContactsByCategory(String category) {
    return _firebase
        .subscribeToCollection(
          collectionId: AppConfig.contactsCollection,
          queries: [
            FQuery.equal('category', category),
            FQuery.orderAsc('name'),
          ],
        )
        .map(
          (docs) => docs
              .map(
                (data) => EmergencyContact.fromFirestore(
                  data,
                  data['\$id'] as String,
                ),
              )
              .toList(),
        );
  }
}
