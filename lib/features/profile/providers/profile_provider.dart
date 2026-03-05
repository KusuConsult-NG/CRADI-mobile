import 'package:climate_app/core/services/secure_storage_service.dart';
import 'package:climate_app/core/services/firebase_service.dart';
import 'package:climate_app/core/services/offline_storage_service.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:io';
import 'dart:developer' as developer;

/// Provider for managing user profile data with Firebase + Firestore
class ProfileProvider extends ChangeNotifier {
  ProfileProvider({
    FirebaseService? firebaseService,
    Connectivity? connectivity,
  }) : _firebase = firebaseService ?? FirebaseService(),
       _connectivity = connectivity ?? Connectivity() {
    loadProfile();
  }

  final SecureStorageService _storage = SecureStorageService();
  final FirebaseService _firebase;
  final OfflineStorageService _offlineStorage = OfflineStorageService();
  Map<String, dynamic>? _userProfile;
  final Connectivity _connectivity;

  String _name = 'User';
  String _email = '';
  String _phone = '';
  String? _profileImagePath;
  String? _state;
  String? _lga;
  String? _ward;
  String? _monitoringZone;
  String? _registrationCode;
  DateTime? _registrationDate;
  bool _biometricsEnabled = false;
  bool _isLoading = false;

  // Getters
  String get name => _name;
  String get email => _email;
  String get phone => _phone;
  String? get profileImagePath => _profileImagePath;
  String? get state => _state;
  String? get lga => _lga;
  String? get ward => _ward;
  String? get monitoringZone => _monitoringZone;
  String? get registrationCode => _registrationCode;
  DateTime? get registrationDate => _registrationDate;
  bool get biometricsEnabled => _biometricsEnabled;
  bool get isLoading => _isLoading;

  /// Get current user's reports as a real-time Firestore stream.
  Stream<List<Map<String, dynamic>>> getUserReportsStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();

    return _firebase.subscribeToCollection(
      collectionId: AppConfig.reportsCollection,
      queries: [
        FQuery.equal('userId', user.uid),
        FQuery.orderDesc('createdAt'),
      ],
    );
  }

  Future<void> loadProfile() async {
    _isLoading = true;
    notifyListeners();

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        _email = user.email ?? '';
        _name = user.displayName ?? 'User';
        _registrationDate = user.metadata.creationTime;

        // Load from Firestore (source of truth)
        try {
          final doc = await _firebase.getDocument(
            collectionId: AppConfig.usersCollection,
            documentId: user.uid,
          );

          if (doc.isNotEmpty) {
            _userProfile = doc;
            await _offlineStorage.cacheUserProfile(_userProfile!);

            _name = doc['name'] ?? _name;
            _email = doc['email'] ?? _email;
            _phone = doc['phone'] ?? '';
            _state = doc['state'];
            _lga = doc['lga'];
            _ward = doc['ward'];
            _registrationCode = doc['registrationCode'];
            _biometricsEnabled = doc['biometricsEnabled'] ?? false;

            final remoteZone = doc['monitoringZone'] as String?;
            if (remoteZone != null && remoteZone.isNotEmpty) {
              _monitoringZone = remoteZone;
              await _storage.write('monitoring_zone', remoteZone);
            } else {
              _monitoringZone = await _storage.read('monitoring_zone');
            }

            if (doc['profileImageUrl'] != null) {
              _profileImagePath = doc['profileImageUrl'] as String;
            }

            // Cache to secure storage
            await _storage.write('profile_name', _name);
            await _storage.write('profile_email', _email);
            await _storage.write('profile_phone', _phone);
            if (_state != null) await _storage.write('profile_state', _state!);
            if (_lga != null) await _storage.write('profile_lga', _lga!);
            if (_ward != null) await _storage.write('profile_ward', _ward!);
            if (_profileImagePath != null) {
              await _storage.write('profile_image', _profileImagePath!);
            }
            await _storage.write(
              'biometric_enabled',
              _biometricsEnabled.toString(),
            );

            developer.log('Profile loaded from Firestore: ${user.uid}');
          }
        } on Exception catch (e) {
          developer.log('Firestore error, using local fallback: $e');
          final cached = _offlineStorage.getCachedUserProfile();
          if (cached != null) {
            _userProfile = cached;
          }
        }

        // Fallback to secure storage if email matches
        final cachedEmail = await _storage.read('profile_email');
        if (cachedEmail == user.email) {
          _name = await _storage.read('profile_name') ?? _name;
          _phone = await _storage.read('profile_phone') ?? _phone;
          _profileImagePath = await _storage.read('profile_image');
          _state ??= await _storage.read('profile_state');
          _lga ??= await _storage.read('profile_lga');
          _ward ??= await _storage.read('profile_ward');
          _monitoringZone ??= await _storage.read('monitoring_zone');
          final bioEnabled = await _storage.read('biometric_enabled');
          _biometricsEnabled = bioEnabled == 'true';
        }
      } else {
        clearProfile();
      }
    } on Exception catch (e) {
      developer.log('Error loading profile: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Resets all profile data to default values (called on logout)
  Future<void> clearProfile() async {
    _name = 'User';
    _email = '';
    _phone = '';
    _profileImagePath = null;
    _state = null;
    _lga = null;
    _ward = null;
    _monitoringZone = null;
    _registrationCode = null;
    _registrationDate = null;
    _biometricsEnabled = false;
    _userProfile = null;
    await _offlineStorage.clearUserData();
    notifyListeners();
  }

  /// Sync changes to Firestore
  Future<void> _syncToFirestore(Map<String, dynamic> data) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final connectivityResults = await _connectivity.checkConnectivity();
      final hasConnection = connectivityResults.any(
        (result) => result != ConnectivityResult.none,
      );

      if (!hasConnection) {
        developer.log('Offline - profile update will be cached locally');
        return;
      }

      await _firebase.updateDocument(
        collectionId: AppConfig.usersCollection,
        documentId: user.uid,
        data: data,
      );

      developer.log('Profile synced to Firestore', name: 'ProfileProvider');
    } on Exception catch (e) {
      developer.log('Error syncing to Firestore: $e', name: 'ProfileProvider');
    }
  }

  Future<void> _updateLocalState(Map<String, dynamic> updates) async {
    _userProfile ??= {};
    _userProfile!.addAll(updates);
    await _offlineStorage.cacheUserProfile(_userProfile!);
  }

  Future<void> updateName(String name) async {
    _name = name;
    await _storage.write('profile_name', name);
    await _updateLocalState({'name': name});
    notifyListeners();
    await _syncToFirestore({'name': name});
  }

  Future<void> updateEmail(String email) async {
    _email = email;
    await _storage.write('profile_email', email);
    await _updateLocalState({'email': email});
    notifyListeners();
    await _syncToFirestore({'email': email});
  }

  Future<void> updatePhone(String phone) async {
    _phone = phone;
    await _storage.write('profile_phone', phone);
    await _updateLocalState({'phone': phone});
    notifyListeners();
    await _syncToFirestore({'phone': phone});
  }

  Future<void> updateProfileImage(String imagePath) async {
    _profileImagePath = imagePath;
    await _storage.write('profile_image', imagePath);
    await _updateLocalState({'profileImageUrl': imagePath});
    notifyListeners();
    await _syncToFirestore({'profileImageUrl': imagePath});
  }

  /// Upload profile image to Firebase Storage and update Firestore
  Future<void> uploadProfileImage(XFile imageFile) async {
    try {
      _isLoading = true;
      notifyListeners();

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User must be logged in to upload profile image');
      }

      final file = File(imageFile.path);
      final ext = imageFile.path.split('.').last.toLowerCase();
      final validExt = (ext == 'png' || ext == 'jpg' || ext == 'jpeg')
          ? ext
          : 'jpg';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storagePath = 'profile_images/${user.uid}_$timestamp.$validExt';

      developer.log(
        'Uploading profile image to Firebase Storage: $storagePath',
        name: 'ProfileProvider',
      );

      final fileUrl = await _firebase.uploadFileFromPath(
        storagePath: storagePath,
        file: file,
        contentType: 'image/$validExt',
      );

      _profileImagePath = fileUrl;
      await _storage.write('profile_image', fileUrl);
      await _updateLocalState({'profileImageUrl': fileUrl});
      await _syncToFirestore({'profileImageUrl': fileUrl});

      developer.log('Profile image uploaded: $fileUrl');
    } on Exception catch (e) {
      developer.log('Error uploading profile image: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateLocation(String? state, String? lga, String? ward) async {
    _state = state;
    _lga = lga;
    _ward = ward;
    if (state != null) await _storage.write('profile_state', state);
    if (lga != null) await _storage.write('profile_lga', lga);
    if (ward != null) await _storage.write('profile_ward', ward);
    await _updateLocalState({'state': state, 'lga': lga, 'ward': ward});
    notifyListeners();
    await _syncToFirestore({'state': state, 'lga': lga, 'ward': ward});
  }

  Future<void> updateMonitoringZone(String zone) async {
    _monitoringZone = zone;
    await _storage.write('monitoring_zone', zone);
    await _updateLocalState({'monitoringZone': zone});
    notifyListeners();
    await _syncToFirestore({'monitoringZone': zone});
  }

  Future<void> setBiometricsEnabled(bool enabled) async {
    _biometricsEnabled = enabled;
    await _storage.write('biometric_enabled', enabled.toString());
    await _updateLocalState({'biometricsEnabled': enabled});
    notifyListeners();
    await _syncToFirestore({'biometricsEnabled': enabled});
  }

  Future<void> updateFCMToken(String token) async {
    await _updateLocalState({'fcmToken': token});
    await _syncToFirestore({'fcmToken': token});
  }
}
