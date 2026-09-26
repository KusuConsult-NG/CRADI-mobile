import 'package:flutter/material.dart';
import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/features/contacts/models/emergency_contact_model.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'dart:developer' as developer;

class EmergencyContactsProvider extends ChangeNotifier {
  final SupabaseService _db = SupabaseService();

  /// The signed-in user's contacts; [] on error. Use [fetchContacts] when a
  /// load failure must be told apart from "no contacts".
  Future<List<EmergencyContact>> getContacts() async {
    try {
      return await fetchContacts();
    } on Exception catch (e) {
      developer.log('Error getting contacts: $e');
      return [];
    }
  }

  /// Like [getContacts] but throws when the contacts could not be loaded
  /// (e.g. offline). Returns [] only when there really are none (or no one
  /// is signed in).
  Future<List<EmergencyContact>> fetchContacts() async {
    final user = _db.getCurrentUser();
    if (user == null) return [];

    // Only the signed-in user's own contacts (RLS enforces this too).
    final docs = await _db.listDocuments(
      collectionId: AppConfig.contactsCollection,
      queries: [FQuery.equal('userId', user.id)],
    );

    return _toSortedContacts(docs);
  }

  Future<void> addContact(EmergencyContact contact) async {
    try {
      final user = _db.getCurrentUser();
      if (user == null) throw Exception('User not logged in');

      final data = contact.toMap();
      data['userId'] = user.id;

      await _db.createDocument(
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
      await _db.updateDocument(
        collectionId: AppConfig.contactsCollection,
        documentId: id,
        data: contact.toMap(),
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
      await _db.deleteDocument(
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

  /// Real-time stream of the signed-in user's contacts.
  Stream<List<EmergencyContact>> getContactsStream() {
    final user = _db.getCurrentUser();
    if (user == null) return Stream.value(const []);
    return _db
        .subscribeToCollection(
          collectionId: AppConfig.contactsCollection,
          queries: [FQuery.equal('userId', user.id)],
        )
        .map(_toSortedContacts);
  }

  Stream<List<EmergencyContact>> getContactsByCategory(String category) {
    final user = _db.getCurrentUser();
    if (user == null) return Stream.value(const []);
    return _db
        .subscribeToCollection(
          collectionId: AppConfig.contactsCollection,
          queries: [
            FQuery.equal('userId', user.id),
            FQuery.equal('category', category),
          ],
        )
        .map(_toSortedContacts);
  }

  List<EmergencyContact> _toSortedContacts(List<Map<String, dynamic>> docs) {
    return docs
        .map((data) => EmergencyContact.fromMap(data, data['\$id'] as String))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }
}
