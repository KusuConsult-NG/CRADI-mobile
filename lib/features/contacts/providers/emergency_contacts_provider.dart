import 'package:flutter/material.dart';
import 'package:climate_app/core/services/appwrite_service.dart';
import 'package:climate_app/features/contacts/models/emergency_contact_model.dart';
import 'package:appwrite/appwrite.dart';
import 'dart:developer' as developer;

class EmergencyContactsProvider extends ChangeNotifier {
  final AppwriteService _appwrite = AppwriteService();

  /// Get all emergency contacts
  Future<List<EmergencyContact>> getContacts() async {
    try {
      final user = await _appwrite.getCurrentUser();
      if (user == null) return [];

      final docs = await _appwrite.listDocuments(
        collectionId: AppwriteService.contactsCollectionId,
        queries: [Query.equal('userId', user.$id), Query.orderAsc('name')],
      );

      return docs.documents
          .map((doc) => EmergencyContact.fromAppwrite(doc.data, doc.$id))
          .toList();
    } on Exception catch (e) {
      developer.log('Error getting contacts: $e');
      return [];
    }
  }

  /// Add new contact
  Future<void> addContact(EmergencyContact contact) async {
    try {
      final user = await _appwrite.getCurrentUser();
      if (user == null) throw Exception('User not logged in');

      final data = contact.toAppwrite();
      data['userId'] = user.$id;
      data['createdAt'] = DateTime.now().toIso8601String();

      await _appwrite.createDocument(
        collectionId: AppwriteService.contactsCollectionId,
        data: data,
      );
      developer.log('Contact added: ${contact.name}');
      notifyListeners();
    } on Exception catch (e) {
      developer.log('Error adding contact: $e');
      rethrow;
    }
  }

  /// Update existing contact
  Future<void> updateContact(String id, EmergencyContact contact) async {
    try {
      await _appwrite.updateDocument(
        collectionId: AppwriteService.contactsCollectionId,
        documentId: id,
        data: contact.toAppwrite(),
      );
      developer.log('Contact updated: $id');
      notifyListeners();
    } on Exception catch (e) {
      developer.log('Error updating contact: $e');
      rethrow;
    }
  }

  /// Delete contact
  Future<void> deleteContact(String id) async {
    try {
      await _appwrite.deleteDocument(
        collectionId: AppwriteService.contactsCollectionId,
        documentId: id,
      );
      developer.log('Contact deleted: $id');
      notifyListeners();
    } on Exception catch (e) {
      developer.log('Error deleting contact: $e');
      rethrow;
    }
  }

  /// Search contacts
  Future<List<EmergencyContact>> searchContacts(String query) async {
    try {
      final contacts = await getContacts();
      final lowercaseQuery = query.toLowerCase();

      return contacts
          .where(
            (contact) =>
                contact.name.toLowerCase().contains(lowercaseQuery) ||
                contact.phone.toLowerCase().contains(lowercaseQuery),
          )
          .toList();
    } on Exception catch (e) {
      developer.log('Error searching contacts: $e');
      return [];
    }
  }

  /// Get all emergency contacts stream (polling-based since Appwrite doesn't have native streams)
  Stream<List<EmergencyContact>> getContactsStream() async* {
    while (true) {
      yield await getContacts();
      await Future.delayed(const Duration(seconds: 5));
    }
  }

  /// Get contacts by category stream
  Stream<List<EmergencyContact>> getContactsByCategory(String category) async* {
    while (true) {
      final all = await getContacts();
      yield all.where((c) => c.category == category).toList();
      await Future.delayed(const Duration(seconds: 5));
    }
  }
}
