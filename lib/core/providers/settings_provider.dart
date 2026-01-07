import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  static final SettingsProvider _instance = SettingsProvider._internal();
  factory SettingsProvider() => _instance;
  SettingsProvider._internal();

  bool _wifiOnly = false;
  bool _lowData = false;
  bool _isInitialized = false;

  bool get wifiOnly => _wifiOnly;
  bool get lowData => _lowData;
  bool get isInitialized => _isInitialized;

  Future<void> init() async {
    if (_isInitialized) return;
    final prefs = await SharedPreferences.getInstance();
    _wifiOnly = prefs.getBool('wifi_only') ?? false;
    _lowData = prefs.getBool('low_data') ?? false;
    _hasSeenOnboarding = prefs.getBool('onboarding_seen') ?? false;
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> setWifiOnly(bool value) async {
    _wifiOnly = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('wifi_only', value);
    notifyListeners();
  }

  bool _hasSeenOnboarding = false;

  bool get hasSeenOnboarding => _hasSeenOnboarding;

  Future<void> setLowData(bool value) async {
    _lowData = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('low_data', value);
    notifyListeners();
  }

  Future<void> setOnboardingSeen(bool value) async {
    _hasSeenOnboarding = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_seen', value);
    notifyListeners();
  }
}
