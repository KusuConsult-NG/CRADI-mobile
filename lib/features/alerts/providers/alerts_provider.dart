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

  static bool _isActive(Map<String, dynamic> a) {
    final v = a['isActive'] ?? a['is_active'];
    return v != false;
  }

  /// Whether [alert] targets [lga] (alerts for 'All' reach everyone).
  ///
  /// Alerts carry only `target_lga` (an LGA name; the table has no state
  /// column), so matching is by exact (case-insensitive) name.
  static bool targetsLga(Map<String, dynamic> alert, String? lga) {
    String norm(Object? v) => (v ?? '').toString().trim().toLowerCase();
    final target = norm(alert['targetLga'] ?? alert['target_lga'] ?? 'All');
    if (target.isEmpty || target == 'all') return true;
    final mine = norm(lga);
    return mine.isNotEmpty && mine == target;
  }

  /// Active alerts addressed to [lga] or to everyone.
  List<Map<String, dynamic>> alertsForLga(String? lga) =>
      _alerts.where((a) => targetsLga(a, lga)).toList();

  Future<void> fetchAlerts() async {
    // Alerts are only readable when signed in: a fetch before sign-in would
    // return nothing and overwrite the offline cache with an empty list.
    // The sign-in hook in main.dart fetches again once a session exists.
    if (_db.currentUserId == null) return;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final documents = await _db.listDocuments(
        collectionId: AppConfig.alertsCollection,
        queries: [
          FQuery.equal('isActive', true),
          FQuery.orderDesc('createdAt'),
        ],
        limitCount: 50,
      );

      _alerts = documents.where(_isActive).toList();

      // Caching is best-effort: a cache failure (e.g. HiveError, which is an
      // Error rather than an Exception) must never prevent alerts loading.
      try {
        await _offlineStorage.cacheAlerts(_alerts);
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
        cached = _offlineStorage.getCachedAlerts().where(_isActive).toList();
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
