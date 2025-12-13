import 'package:climate_app/core/services/secure_storage_service.dart';
import 'package:flutter/material.dart';

/// Provider for managing user profile data with persistent storage
class ProfileProvider extends ChangeNotifier {
  final SecureStorageService _storage = SecureStorageService();

  String _name = 'Musa Ibrahim';
  String _email = '';
  String _phone = '';
  String? _profileImagePath;
  String? _state;
  String? _lga;
  String? _monitoringZone;
  bool _biometricsEnabled = false;

  // Getters
  String get name => _name;
  String get email => _email;
  String get phone => _phone;
  String? get profileImagePath => _profileImagePath;
  String? get state => _state;
  String? get lga => _lga;
  String? get monitoringZone => _monitoringZone;
  bool get biometricsEnabled => _biometricsEnabled;

  ProfileProvider() {
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    _name = await _storage.read('profile_name') ?? 'Musa Ibrahim';
    _email = await _storage.read('profile_email') ?? '';
    _phone = await _storage.read('profile_phone') ?? '';
    _profileImagePath = await _storage.read('profile_image');
    _state = await _storage.read('profile_state');
    _lga = await _storage.read('profile_lga');
    _monitoringZone = await _storage.read('monitoring_zone') ?? 'Benue State';
    final bioEnabled = await _storage.read('biometric_enabled');
    _biometricsEnabled = bioEnabled == 'true';
    notifyListeners();
  }

  Future<void> updateName(String name) async {
    _name = name;
    await _storage.write('profile_name', name);
    notifyListeners();
  }

  Future<void> updateEmail(String email) async {
    _email = email;
    await _storage.write('profile_email', email);
    notifyListeners();
  }

  Future<void> updatePhone(String phone) async {
    _phone = phone;
    await _storage.write('profile_phone', phone);
    notifyListeners();
  }

  Future<void> updateProfileImage(String imagePath) async {
    _profileImagePath = imagePath;
    await _storage.write('profile_image', imagePath);
    notifyListeners();
  }

  Future<void> updateLocation(String? state, String? lga) async {
    _state = state;
    _lga = lga;
    if (state != null) await _storage.write('profile_state', state);
    if (lga != null) await _storage.write('profile_lga', lga);
    notifyListeners();
  }

  Future<void> updateMonitoringZone(String zone) async {
    _monitoringZone = zone;
    await _storage.write('monitoring_zone', zone);
    notifyListeners();
  }

  Future<void> setBiometricsEnabled(bool enabled) async {
    _biometricsEnabled = enabled;
    await _storage.write('biometric_enabled', enabled.toString());
    notifyListeners();
  }
}
