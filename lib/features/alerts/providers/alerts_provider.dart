import 'package:flutter/material.dart';
import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/core/services/offline_storage_service.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'dart:developer' as developer;
import 'package:climate_app/core/utils/error_handler.dart';

class AlertsProvider extends ChangeNotifier {
  final SupabaseService _db = SupabaseService();
  final OfflineStorageService _offlineStorage = OfflineStorageService();

  List<Map<String, dynamic>> _alerts = [];
  bool _isLoading = false;
  String? _error;

  List<Map<String, dynamic>> get alerts => _alerts;
  bool get isLoading => _isLoading;
  String? get error => _error;

  AlertsProvider() {
    fetchAlerts();
  }

  Future<void> fetchAlerts() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final documents = await _db.listDocuments(
        collectionId: AppConfig.alertsCollection,
        queries: [FQuery.orderDesc('createdAt')],
        limitCount: 20,
      );

      _alerts = documents;

      // Caching is best-effort: a cache failure (e.g. HiveError, which is an
      // Error rather than an Exception) must never prevent alerts loading.
      try {
        await _offlineStorage.cacheAlerts(documents);
      } on Object catch (e) {
        ErrorHandler.logError(e, context: 'AlertsProvider.cacheAlerts');
      }

      developer.log(
        'Fetched ${_alerts.length} alerts and cached',
        name: 'AlertsProvider',
      );
    } on Exception catch (e) {
      ErrorHandler.logError(e, context: 'AlertsProvider.fetchAlerts');
      _error = 'Failed to load alerts';

      List<Map<String, dynamic>> cached = const [];
      try {
        cached = _offlineStorage.getCachedAlerts();
      } on Object catch (_) {
        // Cache unavailable (not initialized or unreadable); ignore.
      }
      if (cached.isNotEmpty) {
        _alerts = cached;
        _error = null;
        developer.log(
          'Loaded ${_alerts.length} alerts from cache',
          name: 'AlertsProvider',
        );
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Loads one alert by id (deep links / notification taps). Returns null
  /// when it does not exist or is not readable.
  Future<Map<String, dynamic>?> fetchAlertById(String alertId) async {
    try {
      return await _db.getDocument(
        collectionId: AppConfig.alertsCollection,
        documentId: alertId,
      );
    } on DocumentNotFoundException catch (_) {
      return null;
    } on Exception catch (_) {
      // Offline / transient failure: fall back to the loaded or cached list.
      List<Map<String, dynamic>> known = _alerts;
      if (known.isEmpty) {
        try {
          known = _offlineStorage.getCachedAlerts();
        } on Object catch (_) {}
      }
      for (final a in known) {
        if ((a['id'] ?? a[r'$id'])?.toString() == alertId) return a;
      }
      rethrow;
    }
  }
}
