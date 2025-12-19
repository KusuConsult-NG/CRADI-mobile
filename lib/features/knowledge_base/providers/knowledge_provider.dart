import 'package:appwrite/appwrite.dart';
import 'package:climate_app/core/services/appwrite_service.dart';
import 'package:flutter/material.dart';
import 'dart:developer' as developer;

class KnowledgeProvider extends ChangeNotifier {
  KnowledgeProvider({AppwriteService? appwriteService})
    : _appwrite = appwriteService ?? AppwriteService();

  final AppwriteService _appwrite;
  List<Map<String, dynamic>> _guides = [];
  bool _isLoading = false;
  String? _error;
  RealtimeSubscription? _subscription;

  List<Map<String, dynamic>> get guides => _guides;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> fetchGuides({String? category}) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      List<String> queries = [];
      if (category != null && category != 'All') {
        queries.add(Query.equal('category', category));
      }

      // Order by latest
      queries.add(Query.orderDesc('\$createdAt'));

      final result = await _appwrite.listDocuments(
        collectionId: AppwriteService.knowledgeCollectionId,
        queries: queries,
      );

      _guides = result.documents.map((doc) => doc.data).toList();
      _isLoading = false;
      notifyListeners();

      // Subscribe to updates if not already subscribed
      _subscribeGuides();

      developer.log('Fetched ${_guides.length} guides for category: $category');
    } on Exception catch (e) {
      _error = 'Failed to fetch guides: $e';
      _isLoading = false;
      notifyListeners();
      developer.log('Error fetching guides: $e', name: 'KnowledgeProvider');
    }
  }

  void _subscribeGuides() {
    if (_subscription != null) return;

    const channel =
        'databases.${AppwriteService.databaseId}.collections.${AppwriteService.knowledgeCollectionId}.documents';

    _subscription = _appwrite.subscribe(
      channels: [channel],
      callback: (event) {
        developer.log(
          'Knowledge Base update received',
          name: 'KnowledgeProvider',
        );
        // Re-fetch to apply current filters and ensure ordering
        fetchGuides();
      },
    );
  }

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }

  /// Search guides locally or remotely
  void searchGuides(String query) {
    if (query.isEmpty) {
      fetchGuides();
      return;
    }

    // Simple local search for responsiveness
    _guides = _guides.where((guide) {
      final title = guide['title']?.toString().toLowerCase() ?? '';
      final description = guide['description']?.toString().toLowerCase() ?? '';
      return title.contains(query.toLowerCase()) ||
          description.contains(query.toLowerCase());
    }).toList();
    notifyListeners();
  }
}
