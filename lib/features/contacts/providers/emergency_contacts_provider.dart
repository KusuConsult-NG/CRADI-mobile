import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/features/contacts/models/emergency_contact_model.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'dart:developer' as developer;

class EmergencyContactsProvider extends ChangeNotifier {
  final SupabaseService _supabase = SupabaseService();

  Future<List<EmergencyContact>> getContacts() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return [];

      final docs = await _supabase.listDocuments(
        collectionId: AppConfig.contactsCollection,
        queries: [SQuery.orderAsc('name')],
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
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('User not logged in');

      final data = contact.toFirestore();
      data['user_id'] = user.id;

      await _supabase.createDocument(
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
      await _supabase.updateDocument(
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
      await _supabase.deleteDocument(
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

  /// Real-time stream via Supabase Realtime.
  Stream<List<EmergencyContact>> getContactsStream() {
    return _supabase
        .subscribeToCollection(
          collectionId: AppConfig.contactsCollection,
          queries: [SQuery.orderAsc('name')],
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
    return _supabase
        .subscribeToCollection(
          collectionId: AppConfig.contactsCollection,
          queries: [
            SQuery.equal('category', category),
            SQuery.orderAsc('name'),
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
