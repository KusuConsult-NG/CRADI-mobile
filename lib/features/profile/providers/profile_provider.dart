import 'package:climate_app/core/services/secure_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:developer' as developer;

/// Provider for managing user profile data with persistent storage and Cloud Sync
class ProfileProvider extends ChangeNotifier {
  final SecureStorageService _storage = SecureStorageService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String _name = 'Musa Ibrahim';
  String _email = '';
  String _phone = '';
  String? _profileImagePath;
  String? _state;
  String? _lga;
  String? _monitoringZone;
  bool _biometricsEnabled = false;
  bool _isLoading = false;

  // Getters
  String get name => _name;
  String get email => _email;
  String get phone => _phone;
  String? get profileImagePath => _profileImagePath;
  String? get state => _state;
  String? get lga => _lga;
  String? get monitoringZone => _monitoringZone;
  bool get biometricsEnabled => _biometricsEnabled;
  bool get isLoading => _isLoading;

  ProfileProvider() {
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    _isLoading = true;
    notifyListeners();

    try {
      // 1. Load from Local Storage (Fast/Offline)
      _name = await _storage.read('profile_name') ?? 'Musa Ibrahim';
      _email = await _storage.read('profile_email') ?? '';
      _phone = await _storage.read('profile_phone') ?? '';
      _profileImagePath = await _storage.read('profile_image');
      _state = await _storage.read('profile_state');
      _lga = await _storage.read('profile_lga');
      _monitoringZone = await _storage.read('monitoring_zone') ?? 'Benue State';
      final bioEnabled = await _storage.read('biometric_enabled');
      _biometricsEnabled = bioEnabled == 'true';

      // 2. Load from Firestore (Source of Truth) if valid user
      final user = _auth.currentUser;
      if (user != null) {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          _name = data['name'] ?? _name;
          _email = data['email'] ?? _email;
          _phone = data['phone'] ?? _phone;
          _state = data['state'] ?? _state;
          _lga = data['lga'] ?? _lga;
          _monitoringZone = data['monitoringZone'] ?? _monitoringZone;
          // Profile Image Path might be local or remote URL.
          // If remote, we should handle it. Assuming local path for now or URL string.
          if (data['profileImage'] != null) {
            _profileImagePath = data['profileImage'];
          }

          // Update local storage to match remote
          await _storage.write('profile_name', _name);
          await _storage.write('profile_email', _email);
          await _storage.write('profile_phone', _phone);
          if (_state != null) await _storage.write('profile_state', _state!);
          if (_lga != null) await _storage.write('profile_lga', _lga!);
          if (_monitoringZone != null) {
            await _storage.write('monitoring_zone', _monitoringZone!);
          }
        }
      }
    } on Exception catch (e) {
      developer.log('Error loading profile: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Helper to sync changes to Firestore
  Future<void> _syncToFirestore(Map<String, dynamic> data) async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore
            .collection('users')
            .doc(user.uid)
            .set(data, SetOptions(merge: true));
      }
    } on Exception catch (e) {
      developer.log('Error syncing to Firestore: $e');
      // Silently fail for UI but log it. Ideally queue for retry.
    }
  }

  Future<void> updateName(String name) async {
    _name = name;
    await _storage.write('profile_name', name);
    notifyListeners();
    await _syncToFirestore({'name': name});
  }

  Future<void> updateEmail(String email) async {
    _email = email;
    await _storage.write('profile_email', email);
    notifyListeners();
    await _syncToFirestore({'email': email});
  }

  Future<void> updatePhone(String phone) async {
    _phone = phone;
    await _storage.write('profile_phone', phone);
    notifyListeners();
    await _syncToFirestore({'phone': phone});
  }

  Future<void> updateProfileImage(String imagePath) async {
    _profileImagePath = imagePath;
    await _storage.write('profile_image', imagePath);
    notifyListeners();
    // Assuming imagePath is local, we might need to upload it first.
    // For now, syncing the path/url as string.
    await _syncToFirestore({'profileImage': imagePath});
  }

  Future<void> updateLocation(String? state, String? lga) async {
    _state = state;
    _lga = lga;
    if (state != null) {
      await _storage.write('profile_state', state);
    }
    if (lga != null) {
      await _storage.write('profile_lga', lga);
    }
    notifyListeners();
    await _syncToFirestore({'state': state, 'lga': lga});
  }

  Future<void> updateMonitoringZone(String zone) async {
    _monitoringZone = zone;
    await _storage.write('monitoring_zone', zone);
    notifyListeners();
    await _syncToFirestore({'monitoringZone': zone});
  }

  Future<void> setBiometricsEnabled(bool enabled) async {
    _biometricsEnabled = enabled;
    await _storage.write('biometric_enabled', enabled.toString());
    notifyListeners();
    // Biometrics setting is usually local-device specific, so maybe NOT sync?
    // Or sync as user preference. Let's sync it for now.
    await _syncToFirestore({'biometricsEnabled': enabled});
  }

  Future<void> updateFCMToken(String token) async {
    await _syncToFirestore({'fcmToken': token});
  }
}
