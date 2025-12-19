import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import 'dart:developer' as developer;

/// Provider for monitoring network connectivity status
///
/// Tracks online/offline state and notifies listeners when connection changes
class ConnectivityProvider extends ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool _isOnline = true;
  bool _manualOffline = false;
  bool _initialCheckDone = false;

  /// Whether the device is currently online (considering manual override)
  bool get isOnline => _isOnline && !_manualOffline;

  /// Whether the device is currently offline
  bool get isOffline => !isOnline;

  /// Whether manual offline mode is enabled
  bool get manualOffline => _manualOffline;

  /// Whether the initial connectivity check has been completed
  bool get initialCheckDone => _initialCheckDone;

  ConnectivityProvider() {
    _initConnectivity();
    _startMonitoring();
  }

  /// Perform initial connectivity check
  Future<void> _initConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      _updateConnectionStatus(result);
      _initialCheckDone = true;
      notifyListeners();
    } on Exception catch (e) {
      developer.log(
        'Error checking connectivity: $e',
        name: 'ConnectivityProvider',
      );
      // Assume online if we can't check
      _isOnline = true;
      _initialCheckDone = true;
      notifyListeners();
    }
  }

  /// Start monitoring connectivity changes
  void _startMonitoring() {
    _subscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        _updateConnectionStatus(results);
      },
      onError: (error) {
        developer.log(
          'Connectivity stream error: $error',
          name: 'ConnectivityProvider',
        );
      },
    );
  }

  /// Update connection status based on connectivity result
  void _updateConnectionStatus(List<ConnectivityResult> results) {
    final wasOnline = _isOnline;

    // Consider online if ANY connection is available
    _isOnline = results.any((result) => result != ConnectivityResult.none);

    developer.log(
      'Connectivity changed: ${_isOnline ? "Online" : "Offline"}',
      name: 'ConnectivityProvider',
    );

    // Only notify if status actually changed
    if (wasOnline != _isOnline) {
      notifyListeners();
    }
  }

  /// Manually check current connectivity status
  Future<bool> checkConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      _updateConnectionStatus(result);
      return _isOnline;
    } on Exception catch (e) {
      developer.log(
        'Error checking connectivity: $e',
        name: 'ConnectivityProvider',
      );
      return _isOnline; // Return cached status
    }
  }

  /// Toggle manual offline mode
  void setManualOffline(bool value) {
    if (_manualOffline != value) {
      _manualOffline = value;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
