import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/core/services/offline_storage_service.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/features/knowledge_base/knowledge_categories.dart';
import 'package:flutter/material.dart';
import 'dart:developer' as developer;
import 'package:climate_app/core/l10n/l10n.dart';

/// Loads knowledge_base rows (app-shaped maps) for a hazard type, or all rows
/// when [hazardType] is null.
typedef GuideRowsFetcher =
    Future<List<Map<String, dynamic>>> Function(String? hazardType);

/// Guides are admin-managed in the `knowledge_base` table. The last
/// successful unfiltered list is cached on the device (Hive) and served,
/// marked `isOffline`, when the server cannot be reached.
class KnowledgeProvider extends ChangeNotifier {
  KnowledgeProvider({
    GuideRowsFetcher? fetchRows,
    Future<void> Function(List<Map<String, dynamic>> guides)? writeCache,
    List<Map<String, dynamic>>? Function()? readCache,
  }) : _fetchRows = fetchRows ?? _fetchFromSupabase,
       _writeCache = writeCache ?? OfflineStorageService().cacheGuides,
       _readCache = readCache ?? OfflineStorageService().getCachedGuides;

  final GuideRowsFetcher _fetchRows;
  final Future<void> Function(List<Map<String, dynamic>> guides) _writeCache;
  final List<Map<String, dynamic>>? Function() _readCache;

  static Future<List<Map<String, dynamic>>> _fetchFromSupabase(
    String? hazardType,
  ) {
    return SupabaseService().listDocuments(
      collectionId: AppConfig.knowledgeBaseCollection,
      queries: <QueryFilter>[
        if (hazardType != null) FQuery.equal('hazardType', hazardType),
        FQuery.orderDesc('updatedAt'),
      ],
      limitCount: 100,
    );
  }

  /// Guides per category key ('All' = unfiltered). Kept separately so opening
  /// a category tab never replaces the featured (unfiltered) list.
  final Map<String, List<Map<String, dynamic>>> _guidesByCategory = {};
  final Set<String> _loading = {};

  /// Load failures per category key, resolved in the current language by
  /// the UI.
  final Map<String, LocalizedText?> _errors = {};

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

  LocalizedText? get error => _errors[allKnowledgeCategories];

  LocalizedText? errorFor(String? category) => _errors[_key(category)];

  Future<void> fetchGuides({String? category}) async {
    final key = _key(category);
    final cat = key == allKnowledgeCategories
        ? null
        : knowledgeCategoryFor(key);
    _loading.add(key);
    _errors[key] = null;
    notifyListeners();

    try {
      final docs = await _fetchRows(
        key == allKnowledgeCategories
            ? null
            : (cat?.hazardType ?? key.toLowerCase()),
      );
      final result = docs.map(_fromRow).toList();
      // Only the unfiltered list is cached (so the offline fallback can
      // serve every category from it). An empty result is cached too, so
      // guides an admin deleted also disappear offline.
      if (key == allKnowledgeCategories) {
        try {
          await _writeCache(result);
        } on Object catch (e) {
          developer.log('Guide cache failed: $e', name: 'KnowledgeProvider');
        }
      }
      developer.log(
        'Fetched ${result.length} guides ($key) from Supabase',
        name: 'KnowledgeProvider',
      );
      _guidesByCategory[key] = result;
    } on Exception catch (e) {
      developer.log(
        'Guide fetch failed, trying the offline cache: $e',
        name: 'KnowledgeProvider',
      );
      List<Map<String, dynamic>>? cached;
      try {
        cached = _readCache();
      } on Object catch (e) {
        developer.log('Guide cache unavailable: $e', name: 'KnowledgeProvider');
      }
      if (cached != null) {
        _guidesByCategory[key] = cached
            .where((g) => guideMatchesCategory(g, key))
            .map((g) => <String, dynamic>{...g, 'isOffline': true})
            .toList();
      } else {
        _errors[key] = (l) => l.knowledgeLoadError;
      }
    } finally {
      _loading.remove(key);
      notifyListeners();
    }
  }

  Map<String, dynamic> _fromRow(Map<String, dynamic> data) {
    final rawUrl = data['imageUrl']?.toString().trim() ?? '';
    // No image: the UI shows a placeholder with the category icon.
    final imageUrl = rawUrl.startsWith('http') ? rawUrl : null;
    final category = knowledgeCategoryFor(data['hazardType']);
    return <String, dynamic>{
      'id': data[r'$id'],
      'title': data['title'] ?? '',
      // Display text is derived in the UI (knowledgeCategoryDisplay).
      'subtitle': data['category'],
      'content': data['content'] ?? '',
      'category': data['category'] ?? category?.label ?? 'General',
      'hazardType': data['hazardType'],
      'tag':
          (category?.label ?? data['hazardType'] as String?)?.toUpperCase() ??
          'GUIDE',
      'imageUrl': imageUrl,
      'source': data['source'] ?? '',
      'updatedAt': data['updatedAt'],
      'isOffline': false,
    };
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
}
