import 'package:climate_app/core/services/emergency_guides_service.dart';
import 'package:flutter/material.dart';
import 'dart:developer' as developer;

class KnowledgeProvider extends ChangeNotifier {
  KnowledgeProvider({EmergencyGuidesService? emergencyGuidesService})
    : _guidesService = emergencyGuidesService ?? EmergencyGuidesService();

  final EmergencyGuidesService _guidesService;
  List<Map<String, dynamic>> _guides = [];
  bool _isLoading = false;
  String? _error;

  List<Map<String, dynamic>> get guides => _guides;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Fetch guides from Emergency Guides Service
  Future<void> fetchGuides({String? category}) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Fetch guides directly from curated service (no authentication needed)
      final apiGuides = await _guidesService.fetchGuides(
        hazardType: category,
        limit: 20,
      );

      developer.log(
        'Fetched ${apiGuides.length} guides from Emergency Guides Service',
        name: 'KnowledgeProvider',
      );

      // Update UI with fresh data
      _guides = apiGuides;
      _isLoading = false;
      notifyListeners();
    } on Exception catch (e) {
      _error = 'Failed to fetch guides: $e';
      _isLoading = false;
      notifyListeners();
      developer.log('Error fetching guides: $e', name: 'KnowledgeProvider');
    }
  }

  /// Search guides by query string
  List<Map<String, dynamic>> searchGuides(String query) {
    if (query.isEmpty) return _guides;

    final lowerQuery = query.toLowerCase();
    return _guides.where((guide) {
      final title = (guide['title'] as String?)?.toLowerCase() ?? '';
      final content = (guide['content'] as String?)?.toLowerCase() ?? '';
      final tags = (guide['tags'] as List?)?.join(' ').toLowerCase() ?? '';

      return title.contains(lowerQuery) ||
          content.contains(lowerQuery) ||
          tags.contains(lowerQuery);
    }).toList();
  }

  /// Get available disaster types for filtering
  List<String> getDisasterTypes() {
    return _guidesService.getDisasterTypes();
  }

  @override
  void dispose() {
    // No realtime subscription to cancel anymore
    super.dispose();
  }
}
