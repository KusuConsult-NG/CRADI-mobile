import 'package:flutter/material.dart';
import 'package:climate_app/core/services/firebase_service.dart';
import 'package:climate_app/core/services/offline_storage_service.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'dart:developer' as developer;
import 'package:climate_app/core/utils/error_handler.dart';

class AlertsProvider extends ChangeNotifier {
  final FirebaseService _firebase = FirebaseService();
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
      final documents = await _firebase.listDocuments(
        collectionId: AppConfig.alertsCollection,
        queries: [FQuery.orderDesc('createdAt')],
        limitCount: 20,
      );

      await _offlineStorage.cacheAlerts(documents);
      _alerts = documents;

      developer.log(
        'Fetched ${_alerts.length} alerts and cached',
        name: 'AlertsProvider',
      );
    } on Exception catch (e) {
      ErrorHandler.logError(e, context: 'AlertsProvider.fetchAlerts');
      _error = 'Failed to load alerts';

      final cached = _offlineStorage.getCachedAlerts();
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
}
