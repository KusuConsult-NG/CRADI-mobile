import 'package:climate_app/core/services/appwrite_service.dart';
import 'package:climate_app/core/services/emergency_guides_service.dart'; // Keep for fallback
import 'package:climate_app/core/services/offline_storage_service.dart';
import 'package:appwrite/appwrite.dart';
import 'package:flutter/material.dart';
import 'dart:developer' as developer;

class KnowledgeProvider extends ChangeNotifier {
  final AppwriteService _appwrite = AppwriteService();
  final EmergencyGuidesService _fallbackService = EmergencyGuidesService();
  final OfflineStorageService _offlineStorage = OfflineStorageService();

  List<Map<String, dynamic>> _guides = [];
  bool _isLoading = false;
  String? _error;

  List<Map<String, dynamic>> get guides => _guides;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Fetch guides from Appwrite with fallback to offline curated content
  Future<void> fetchGuides({String? category}) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // 1. Try fetching from Appwrite
      try {
        final List<String> queries = [];
        if (category != null && category != 'All') {
          // Query by hazardType since UI filters by 'Flood', 'Fire', etc.
          // We convert to lowercase to match Admin Portal values (e.g. 'flood')
          queries.add(Query.equal('hazardType', category.toLowerCase()));
        }
        queries.add(Query.limit(100));

        final response = await _appwrite.listDocuments(
          collectionId: AppwriteService.knowledgeCollectionId,
          queries: queries,
        );

        if (response.documents.isNotEmpty) {
          _guides = response.documents.map((doc) {
            return {
              'id': doc.$id,
              'title': doc.data['title'] ?? '',
              'subtitle': doc.data['category'] ?? 'Manual',
              'content': doc.data['content'] ?? '',
              'category': doc.data['category'] ?? 'General',
              'hazardType': doc.data['hazardType'],
              // Map hazardType to tag for the UI badge
              'tag':
                  (doc.data['hazardType'] as String?)?.toUpperCase() ?? 'GUIDE',
              // Use a default placeholder or specific images based on type
              'imageUrl': _getImageForType(doc.data['hazardType']),
              'source': 'CRADI Admin',
              'updatedAt': doc.$updatedAt,
              'isOffline': false, // fetched from cloud
            };
          }).toList();

          // Cache the fresh data
          await _offlineStorage.cacheGuides(_guides);

          developer.log(
            'Fetched ${_guides.length} guides from Appwrite and cached',
            name: 'KnowledgeProvider',
          );
        } else {
          // Fallback if empty (or maybe we want to mix them?)
          // For now, if Appwrite is empty, show curated.
          final fallbackData = await _fallbackService.fetchGuides(
            hazardType: category,
          );
          _guides = fallbackData.map((doc) {
            return {
              ...doc,
              'imageUrl':
                  doc['imageUrl'] ??
                  _getImageForType(doc['hazardType'] ?? doc['category']),
              'isOffline': true,
            };
          }).toList();
        }
      } on Exception catch (e) {
        developer.log(
          'Appwrite fetch failed, using fallback: $e',
          name: 'KnowledgeProvider',
        );
        // 2. Fallback to cached content on error
        final cached = _offlineStorage.getCachedGuides();
        if (cached.isNotEmpty) {
          _guides = cached;
          developer.log(
            'Loaded ${_guides.length} guides from local cache',
            name: 'KnowledgeProvider',
          );
        } else {
          // 3. Fallback to hardcoded content if cache empty
          final fallbackData = await _fallbackService.fetchGuides(
            hazardType: category,
          );
          _guides = fallbackData.map((doc) {
            return {
              ...doc,
              'imageUrl':
                  doc['imageUrl'] ??
                  _getImageForType(doc['hazardType'] ?? doc['category']),
              'isOffline': true,
            };
          }).toList();
        }
      }

      _isLoading = false;
      notifyListeners();
    } on Exception catch (e) {
      _error = 'Failed to fetch guides: $e';
      _isLoading = false;
      notifyListeners();
      developer.log('Error in fetchGuides: $e', name: 'KnowledgeProvider');
    }
  }

  /// Search guides
  List<Map<String, dynamic>> searchGuides(String query) {
    if (query.isEmpty) return _guides;

    final lowerQuery = query.toLowerCase();
    return _guides.where((guide) {
      final title = (guide['title'] as String?)?.toLowerCase() ?? '';
      final content = (guide['content'] as String?)?.toLowerCase() ?? '';
      // Handle both list of strings or string for tags
      final tag = guide['tag']?.toString().toLowerCase() ?? '';

      return title.contains(lowerQuery) ||
          content.contains(lowerQuery) ||
          tag.contains(lowerQuery);
    }).toList();
  }

  List<String> getDisasterTypes() {
    return _fallbackService.getDisasterTypes();
  }

  String _getImageForType(String? type) {
    // Return appropriate placeholder images based on hazard type
    switch (type?.toLowerCase()) {
      case 'flood':
        return 'https://images.unsplash.com/photo-1547683905-f686c993aae5?auto=format&fit=crop&q=80&w=800';
      case 'fire':
        return 'https://images.unsplash.com/photo-1497911270199-1c552ee64aa4?auto=format&fit=crop&q=80&w=800';
      case 'accident':
        return 'https://images.unsplash.com/photo-1563820258-090c2e68449c?auto=format&fit=crop&q=80&w=800';
      case 'erosion':
        return 'https://images.unsplash.com/photo-1532884989635-c350639906d2?auto=format&fit=crop&q=80&w=800';
      case 'disease':
        return 'https://images.unsplash.com/photo-1584036561566-b93a50208c3c?auto=format&fit=crop&q=80&w=800';
      case 'conflict':
        return 'https://images.unsplash.com/photo-1555627685-7977a4216833?auto=format&fit=crop&q=80&w=800';
      default:
        return 'https://images.unsplash.com/photo-1581091226825-a6a2a5aee158?auto=format&fit=crop&q=80&w=800';
    }
  }
}
