import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-level app preferences (SharedPreferences), restored on start.
class SettingsProvider extends ChangeNotifier {
  static final SettingsProvider _instance = SettingsProvider._internal();
  factory SettingsProvider() => _instance;
  SettingsProvider._internal();

  /// Separate instance for tests (the app uses the singleton).
  @visibleForTesting
  factory SettingsProvider.forTesting() => SettingsProvider._internal();

  static const String pushNotificationsKey = 'push_notifications_enabled';
  static const String criticalAlertsKey = 'critical_alerts_enabled';

  bool _pushNotifications = true;
  bool _criticalAlerts = true;
  bool _isInitialized = false;

  /// Whether this device receives push notifications (OneSignal push
  /// subscription opted in). Applied by NotificationService.
  bool get pushNotifications => _pushNotifications;

  /// The user's Critical Alert Override preference.
  bool get criticalAlerts => _criticalAlerts;

  bool get isInitialized => _isInitialized;

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _pushNotifications = prefs.getBool(pushNotificationsKey) ?? true;
      _criticalAlerts = prefs.getBool(criticalAlertsKey) ?? true;
    } on Exception catch (e) {
      debugPrint('Could not load settings: $e');
    }
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> setPushNotifications(bool value) async {
    _pushNotifications = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(pushNotificationsKey, value);
  }

  Future<void> setCriticalAlerts(bool value) async {
    _criticalAlerts = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(criticalAlertsKey, value);
  }
}
