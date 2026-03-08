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
                  'updatedAt': data['updatedAt'],
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
        // Flooded street / submerged homes
        return 'https://images.unsplash.com/photo-1504701954957-2010ec3bcec1?auto=format&fit=crop&q=80&w=800';
      case 'fire':
      case 'wildfires':
        // Active wildfire / burning landscape
        return 'https://images.unsplash.com/photo-1516912481808-3406841bd33c?auto=format&fit=crop&q=80&w=800';
      case 'accident':
        // Road accident / emergency response scene
        return 'https://images.unsplash.com/photo-1544636331-e26879cd4d9b?auto=format&fit=crop&q=80&w=800';
      case 'erosion':
        // Severe soil erosion / cracked ground
        return 'https://images.unsplash.com/photo-1591700608620-4cdcf1d47898?auto=format&fit=crop&q=80&w=800';
      case 'disease':
      case 'epidemic':
        // Healthcare / disease response
        return 'https://images.unsplash.com/photo-1584036561566-b93a50208c3c?auto=format&fit=crop&q=80&w=800';
      case 'conflict':
        // Crisis / security emergency scene
        return 'https://images.unsplash.com/photo-1599059813005-11265ba4b4ce?auto=format&fit=crop&q=80&w=800';
      case 'storm':
        // Dark storm clouds / severe weather
        return 'https://images.unsplash.com/photo-1535350356005-fd52b3b524fb?auto=format&fit=crop&q=80&w=800';
      case 'earthquake':
        // Collapsed building / earthquake damage
        return 'https://images.unsplash.com/photo-1548337138-e87d889cc369?auto=format&fit=crop&q=80&w=800';
      case 'extreme heat':
      case 'drought':
        // Cracked dry earth / drought landscape
        return 'https://images.unsplash.com/photo-1504192010706-dd7f569ee2be?auto=format&fit=crop&q=80&w=800';
      default:
        // Emergency preparedness / general safety
        return 'https://images.unsplash.com/photo-1496247749665-49cf5b1022e9?auto=format&fit=crop&q=80&w=800';
    }
  }
}
