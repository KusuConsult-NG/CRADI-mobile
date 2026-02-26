import 'package:climate_app/core/services/firebase_service.dart';
import 'package:climate_app/core/services/emergency_guides_service.dart';
import 'package:climate_app/core/services/offline_storage_service.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:flutter/material.dart';
import 'dart:developer' as developer;

class KnowledgeProvider extends ChangeNotifier {
  final FirebaseService _firebase = FirebaseService();
  final EmergencyGuidesService _fallbackService = EmergencyGuidesService();
  final OfflineStorageService _offlineStorage = OfflineStorageService();

  List<Map<String, dynamic>> _guides = [];
  bool _isLoading = false;
  String? _error;

  List<Map<String, dynamic>> get guides => _guides;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> fetchGuides({String? category}) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      try {
        final queries = <QueryFilter>[];
        if (category != null && category != 'All') {
          queries.add(FQuery.equal('hazardType', category.toLowerCase()));
        }

        final docs = await _firebase.listDocuments(
          collectionId: AppConfig.knowledgeBaseCollection,
          queries: queries,
          limitCount: 100,
        );

        if (docs.isNotEmpty) {
          _guides = docs
              .map(
                (data) => <String, dynamic>{
                  'id': data['\$id'],
                  'title': data['title'] ?? '',
                  'subtitle': data['category'] ?? 'Manual',
                  'content': data['content'] ?? '',
                  'category': data['category'] ?? 'General',
                  'hazardType': data['hazardType'],
                  'tag':
                      (data['hazardType'] as String?)?.toUpperCase() ?? 'GUIDE',
                  'imageUrl': _getImageForType(data['hazardType']),
                  'source': 'EWER Admin',
                  'updatedAt': data['\$updatedAt'],
                  'isOffline': false,
                },
              )
              .toList();

          await _offlineStorage.cacheGuides(_guides);
          developer.log(
            'Fetched ${_guides.length} guides from Firestore',
            name: 'KnowledgeProvider',
          );
        } else {
          final fallbackData = await _fallbackService.fetchGuides(
            hazardType: category,
          );
          _guides = fallbackData
              .map(
                (doc) => <String, dynamic>{
                  ...doc,
                  'imageUrl':
                      doc['imageUrl'] ??
                      _getImageForType(doc['hazardType'] ?? doc['category']),
                  'isOffline': true,
                },
              )
              .toList();
        }
      } on Exception catch (e) {
        developer.log(
          'Firestore fetch failed, using fallback: $e',
          name: 'KnowledgeProvider',
        );
        final cached = _offlineStorage.getCachedGuides();
        if (cached.isNotEmpty) {
          _guides = cached;
          developer.log(
            'Loaded ${_guides.length} guides from cache',
            name: 'KnowledgeProvider',
          );
        } else {
          final fallbackData = await _fallbackService.fetchGuides(
            hazardType: category,
          );
          _guides = fallbackData
              .map(
                (doc) => <String, dynamic>{
                  ...doc,
                  'imageUrl':
                      doc['imageUrl'] ??
                      _getImageForType(doc['hazardType'] ?? doc['category']),
                  'isOffline': true,
                },
              )
              .toList();
        }
      }

      _isLoading = false;
      notifyListeners();
    } on Exception catch (e) {
      _error = 'Failed to fetch guides: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Search guides by title, content, tag, or seeded searchKeywords.
  /// Pass [language] to restrict to 'en' or 'ha' guides.
  List<Map<String, dynamic>> searchGuides(String query, {String? language}) {
    var results = _guides;

    // Filter by language if specified
    if (language != null && language.isNotEmpty) {
      results = results
          .where((g) => (g['language'] as String?)?.toLowerCase() == language)
          .toList();
    }

    if (query.isEmpty) return results;
    final lowerQuery = query.toLowerCase();

    return results.where((guide) {
      final title = (guide['title'] as String?)?.toLowerCase() ?? '';
      final content = (guide['content'] as String?)?.toLowerCase() ?? '';
      final tag = guide['tag']?.toString().toLowerCase() ?? '';
      final keywords =
          (guide['searchKeywords'] as List<dynamic>?)
              ?.join(' ')
              .toLowerCase() ??
          '';
      return title.contains(lowerQuery) ||
          content.contains(lowerQuery) ||
          tag.contains(lowerQuery) ||
          keywords.contains(lowerQuery);
    }).toList();
  }

  /// Fetch guides for a specific language ('en' or 'ha').
  Future<void> fetchGuidesByLanguage(
    String language, {
    String? category,
  }) async {
    await fetchGuides(category: category);
    _guides = _guides
        .where((g) => (g['language'] as String?)?.toLowerCase() == language)
        .toList();
    notifyListeners();
  }

  List<String> getDisasterTypes() => _fallbackService.getDisasterTypes();

  String _getImageForType(String? type) {
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
      case 'storm':
        return 'https://images.unsplash.com/photo-1527482797697-8798539dae07?auto=format&fit=crop&q=80&w=800';
      case 'earthquake':
        return 'https://images.unsplash.com/photo-1521295121757-bb09b2e259b1?auto=format&fit=crop&q=80&w=800';
      default:
        return 'https://images.unsplash.com/photo-1581091226825-a6a2a5aee158?auto=format&fit=crop&q=80&w=800';
    }
  }
}
