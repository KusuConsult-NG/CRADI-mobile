import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/core/services/emergency_guides_service.dart';
import 'package:climate_app/core/services/offline_storage_service.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/features/knowledge_base/knowledge_categories.dart';
import 'package:flutter/material.dart';
import 'dart:developer' as developer;

class KnowledgeProvider extends ChangeNotifier {
  final SupabaseService _db = SupabaseService();
  final EmergencyGuidesService _fallbackService = EmergencyGuidesService();
  final OfflineStorageService _offlineStorage = OfflineStorageService();

  /// Guides per category key ('All' = unfiltered). Kept separately so opening
  /// a category tab never replaces the featured (unfiltered) list.
  final Map<String, List<Map<String, dynamic>>> _guidesByCategory = {};
  final Set<String> _loading = {};
  final Map<String, String?> _errors = {};

  static String _key(String? category) {
    if (category == null || category == allKnowledgeCategories) {
      return allKnowledgeCategories;
    }
    return knowledgeCategoryFor(category)?.label ?? category;
  }

  /// All (unfiltered) guides.
  List<Map<String, dynamic>> get guides =>
      _guidesByCategory[allKnowledgeCategories] ?? const [];

  /// Guides loaded for [category] (label or hazard type).
  List<Map<String, dynamic>> guidesFor(String? category) =>
      _guidesByCategory[_key(category)] ?? const [];

  /// Whether the unfiltered list is loading.
  bool get isLoading => _loading.contains(allKnowledgeCategories);

  bool isLoadingCategory(String? category) => _loading.contains(_key(category));

  String? get error => _errors[allKnowledgeCategories];

  String? errorFor(String? category) => _errors[_key(category)];

  Future<void> fetchGuides({String? category}) async {
    final key = _key(category);
    final cat = key == allKnowledgeCategories
        ? null
        : knowledgeCategoryFor(key);
    _loading.add(key);
    _errors[key] = null;
    notifyListeners();

    try {
      List<Map<String, dynamic>> result;
      try {
        final queries = <QueryFilter>[
          if (key != allKnowledgeCategories)
            FQuery.equal('hazardType', cat?.hazardType ?? key.toLowerCase()),
          FQuery.orderDesc('updatedAt'),
        ];

        final docs = await _db.listDocuments(
          collectionId: AppConfig.knowledgeBaseCollection,
          queries: queries,
          limitCount: 100,
        );

        if (docs.isNotEmpty) {
          result = docs.map(_fromRow).toList();
          // Only the unfiltered list is cached, so the offline fallback can
          // serve every category from it.
          if (key == allKnowledgeCategories) {
            try {
              await _offlineStorage.cacheGuides(result);
            } on Object catch (e) {
              developer.log(
                'Guide cache failed: $e',
                name: 'KnowledgeProvider',
              );
            }
          }
          developer.log(
            'Fetched ${result.length} guides ($key) from Supabase',
            name: 'KnowledgeProvider',
          );
        } else {
          result = await _bundledGuides(key);
        }
      } on Exception catch (e) {
        developer.log(
          'Guide fetch failed, using fallback: $e',
          name: 'KnowledgeProvider',
        );
        List<Map<String, dynamic>> cached = const [];
        try {
          cached = _offlineStorage
              .getCachedGuides()
              .where((g) => guideMatchesCategory(g, key))
              .toList();
        } on Object catch (_) {
          // Cache unavailable; use the bundled guides.
        }
        result = cached.isNotEmpty ? cached : await _bundledGuides(key);
      }
      _guidesByCategory[key] = result;
    } on Exception catch (e) {
      _errors[key] = 'Failed to fetch guides: $e';
    } finally {
      _loading.remove(key);
      notifyListeners();
    }
  }

  Map<String, dynamic> _fromRow(Map<String, dynamic> data) {
    final rawUrl = data['imageUrl']?.toString() ?? '';
    final imageUrl = (rawUrl.isNotEmpty && rawUrl.startsWith('http'))
        ? rawUrl
        : _getImageForType(data['hazardType'] ?? data['category']);
    final category = knowledgeCategoryFor(data['hazardType']);
    return <String, dynamic>{
      'id': data[r'$id'],
      'title': data['title'] ?? '',
      'subtitle': data['category'] ?? 'Manual',
      'content': data['content'] ?? '',
      'category': data['category'] ?? category?.label ?? 'General',
      'hazardType': data['hazardType'],
      'tag':
          (category?.label ?? data['hazardType'] as String?)?.toUpperCase() ??
          'GUIDE',
      'imageUrl': imageUrl,
      'source': data['source'] ?? 'EWER Admin',
      'updatedAt': data['updatedAt'],
      'isOffline': false,
    };
  }

  /// Curated guides bundled with the app, filtered to [key].
  Future<List<Map<String, dynamic>>> _bundledGuides(String key) async {
    final fallbackData = await _fallbackService.fetchGuides(limit: 100);
    return fallbackData
        .where((doc) => guideMatchesCategory(doc, key))
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

  /// Search guides (of [category], default all) by title, content, tag, or
  /// seeded searchKeywords.
  List<Map<String, dynamic>> searchGuides(String query, {String? category}) {
    final results = guidesFor(category);
    if (query.trim().isEmpty) return results;
    final lowerQuery = query.trim().toLowerCase();

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

  List<String> getDisasterTypes() => knowledgeCategoryFilters;

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
      case 'extreme_heat':
      case 'drought':
        // Cracked dry earth / drought landscape
        return 'https://images.unsplash.com/photo-1504192010706-dd7f569ee2be?auto=format&fit=crop&q=80&w=800';
      default:
        // Emergency preparedness / general safety
        return 'https://images.unsplash.com/photo-1496247749665-49cf5b1022e9?auto=format&fit=crop&q=80&w=800';
    }
  }
}
