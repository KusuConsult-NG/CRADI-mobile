import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart';
import 'package:climate_app/core/services/appwrite_service.dart';
import 'package:climate_app/core/services/offline_storage_service.dart';
import 'dart:developer' as developer;
import 'package:climate_app/core/utils/error_handler.dart';

class AlertsProvider extends ChangeNotifier {
  final AppwriteService _appwrite = AppwriteService();
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
      // 1. Try fetching from Appwrite
      final response = await _appwrite.listDocuments(
        collectionId: AppwriteService.alertsCollectionId,
        queries: [Query.orderDesc('\$createdAt'), Query.limit(20)],
      );

      // 2. Cache successful response
      final documents = response.documents.map((doc) => doc.data).toList();
      await _offlineStorage.cacheAlerts(documents);
      _alerts = documents;

      developer.log(
        'Fetched ${_alerts.length} alerts and cached',
        name: 'AlertsProvider',
      );
    } on Exception catch (e) {
      ErrorHandler.logError(e, context: 'AlertsProvider.fetchAlerts');
      _error = 'Failed to load alerts';

      // 3. Fallback to offline cache
      final cached = _offlineStorage.getCachedAlerts();
      if (cached.isNotEmpty) {
        _alerts = cached;
        _error = null; // Clear error if we have cached data
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
}
