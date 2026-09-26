import 'package:climate_app/core/services/secure_storage_service.dart';
import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/core/services/offline_storage_service.dart';
import 'package:climate_app/core/services/onesignal_service.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'dart:developer' as developer;

/// Provider for managing user profile data with Supabase.
class ProfileProvider extends ChangeNotifier {
  ProfileProvider({
    SupabaseService? supabaseService,
    Connectivity? connectivity,
  }) : _supabase = supabaseService ?? SupabaseService(),
       _connectivity = connectivity ?? Connectivity() {
    loadProfile();
  }

  final SecureStorageService _storage = SecureStorageService();
  final SupabaseService _supabase;
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
  String? get role => _userProfile?['role'] as String?;

  /// Get current user's reports as a real-time Supabase Realtime stream.
  Stream<List<Map<String, dynamic>>> getUserReportsStream() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return const Stream.empty();

    return _supabase.subscribeToCollection(
      collectionId: AppConfig.reportsCollection,
      queries: [
        SQuery.equal('user_id', user.id),
        SQuery.orderDesc('submitted_at'),
      ],
    );
  }

  Future<void> loadProfile() async {
    _isLoading = true;
    notifyListeners();

    try {
      final user = Supabase.instance.client.auth.currentUser;

      if (user != null) {
        _email = user.email ?? '';

        // ── Fast path: load from secure-storage cache immediately ──────────
        final cachedEmail = await _storage.read('profile_email');
        if (cachedEmail == user.email) {
          final cachedName = await _storage.read('profile_name');
          if (cachedName != null && cachedName.isNotEmpty) {
            _name = cachedName;
          } else {
            _name =
                user.userMetadata?['full_name'] as String? ?? 'User';
          }
          _phone = await _storage.read('profile_phone') ?? '';
          _profileImagePath = await _storage.read('profile_image');
          _state = await _storage.read('profile_state');
          _lga = await _storage.read('profile_lga');
          _ward = await _storage.read('profile_ward');
          final storedZone = await _storage.read('monitoring_zone');
          _monitoringZone =
              (storedZone != null && storedZone.isNotEmpty)
                  ? storedZone
                  : null;
          final bioEnabled = await _storage.read('biometric_enabled');
          _biometricsEnabled = bioEnabled == 'true';
          // Notify immediately so the UI shows cached data, then continue
          // fetching from Supabase to refresh.
          notifyListeners();
        } else {
          _name = user.userMetadata?['full_name'] as String? ?? 'User';
        }

        // Parse account creation time from JWT
        _registrationDate = user.createdAt.isNotEmpty
            ? DateTime.tryParse(user.createdAt)
            : null;

        // Load from Supabase (source of truth)
        try {
          final doc = await _supabase.getDocument(
            collectionId: AppConfig.usersCollection,
            documentId: user.id,
          );

          if (doc.isNotEmpty) {
            // Sanitize before storing: Supabase returns plain Dart types,
            // but dates come as Strings which Hive handles fine.
            _userProfile = _sanitizeDoc(doc);
            await _offlineStorage.cacheUserProfile(_userProfile!);

            _name = doc['full_name'] as String? ?? _name;
            _email = doc['email'] as String? ?? _email;
            _phone = doc['phone'] as String? ?? '';
            _state = doc['state'] as String?;
            _lga = doc['lga'] as String?;
            _ward = doc['ward'] as String?;
            _registrationCode = doc['registration_code'] as String?;
            _biometricsEnabled = doc['biometrics_enabled'] as bool? ?? false;

            final remoteZone = doc['monitoring_zone'] as String?;
            if (remoteZone != null && remoteZone.isNotEmpty) {
              _monitoringZone = remoteZone;
              await _storage.write('monitoring_zone', remoteZone);
            } else {
              _monitoringZone = await _storage.read('monitoring_zone');
            }

            if (doc['avatar_url'] != null &&
                (doc['avatar_url'] as String).isNotEmpty) {
              _profileImagePath = doc['avatar_url'] as String;
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

            developer.log('Profile loaded from Supabase: ${user.id}');
            // Link user ID and sync tags to OneSignal
            await OneSignalService().login(user.id);
            await OneSignalService().setUserTags(
              state: _state,
              lga: _lga,
              ward: _ward,
              role: role,
            );
          }
        } on Exception catch (e) {
          developer.log('Supabase error, using local fallback: $e');
          final cached = _offlineStorage.getCachedUserProfile();
          if (cached != null) {
            _userProfile = cached;
          }
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
    await OneSignalService().logout();
    notifyListeners();
  }

  /// Sync changes to Supabase
  Future<void> _syncToSupabase(Map<String, dynamic> data) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final connectivityResults = await _connectivity.checkConnectivity();
      final hasConnection = connectivityResults.any(
        (result) => result != ConnectivityResult.none,
      );

      if (!hasConnection) {
        developer.log('Offline - profile update will be cached locally');
        return;
      }

      await _supabase.updateDocument(
        collectionId: AppConfig.usersCollection,
        documentId: user.id,
        data: data,
      );

      developer.log('Profile synced to Supabase', name: 'ProfileProvider');
    } on Exception catch (e) {
      developer.log('Error syncing to Supabase: $e', name: 'ProfileProvider');
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
    await _updateLocalState({'full_name': name});
    notifyListeners();
    await _syncToSupabase({'full_name': name});
  }

  Future<void> updateEmail(String email) async {
    _email = email;
    await _storage.write('profile_email', email);
    await _updateLocalState({'email': email});
    notifyListeners();
    await _syncToSupabase({'email': email});
  }

  Future<void> updatePhone(String phone) async {
    _phone = phone;
    await _storage.write('profile_phone', phone);
    await _updateLocalState({'phone': phone});
    notifyListeners();
    await _syncToSupabase({'phone': phone});
  }

  Future<void> updateProfileImage(String imagePath) async {
    _profileImagePath = imagePath;
    await _storage.write('profile_image', imagePath);
    await _updateLocalState({'avatar_url': imagePath});
    notifyListeners();
    await _syncToSupabase({'avatar_url': imagePath});
  }

  /// Upload profile image to Supabase Storage and update profile row.
  Future<void> uploadProfileImage(XFile imageFile) async {
    try {
      _isLoading = true;
      notifyListeners();

      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        throw Exception('User must be logged in to upload profile image');
      }

      final file = File(imageFile.path);
      final ext = imageFile.path.split('.').last.toLowerCase();
      final validExt =
          (ext == 'png' || ext == 'jpg' || ext == 'jpeg') ? ext : 'jpg';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storagePath =
          'profile_images/${user.id}/profile_$timestamp.$validExt';

      developer.log(
        'Uploading profile image to Supabase Storage: $storagePath',
        name: 'ProfileProvider',
      );

      final fileUrl = await _supabase.uploadFileFromPath(
        storagePath: storagePath,
        file: file,
        contentType: 'image/$validExt',
      );

      _profileImagePath = fileUrl;
      await _storage.write('profile_image', fileUrl);
      await _updateLocalState({'avatar_url': fileUrl});
      await _syncToSupabase({'avatar_url': fileUrl});

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
    await _syncToSupabase({'state': state, 'lga': lga, 'ward': ward});
    await OneSignalService().setUserTags(
      state: state,
      lga: lga,
      ward: ward,
      role: role,
    );
  }

  Future<void> updateMonitoringZone(String zone) async {
    final effectiveZone = zone.isEmpty ? null : zone;
    _monitoringZone = effectiveZone;
    await _storage.write('monitoring_zone', effectiveZone ?? '');
    await _updateLocalState({'monitoring_zone': effectiveZone ?? ''});
    notifyListeners();
    await _syncToSupabase({'monitoring_zone': effectiveZone ?? ''});
    await OneSignalService().setUserTags(
      state: _state,
      lga: _lga,
      ward: _ward,
      role: role,
    );
  }

  Future<void> setBiometricsEnabled(bool enabled) async {
    _biometricsEnabled = enabled;
    await _storage.write('biometric_enabled', enabled.toString());
    await _updateLocalState({'biometrics_enabled': enabled});
    notifyListeners();
    await _syncToSupabase({'biometrics_enabled': enabled});
  }

  Future<void> updateFCMToken(String token) async {
    await _updateLocalState({'fcm_token': token});
    await _syncToSupabase({'fcm_token': token});
  }

  /// Sanitizes document maps before storing in Hive.
  /// Supabase returns plain Dart types; only DateTime and nested
  /// maps/lists need conversion.
  Map<String, dynamic> _sanitizeDoc(Map<String, dynamic> data) {
    final result = <String, dynamic>{};
    data.forEach((key, value) {
      if (value is DateTime) {
        result[key] = value.toIso8601String();
      } else if (value is Map<String, dynamic>) {
        result[key] = _sanitizeDoc(value);
      } else if (value is List) {
        result[key] = value.map((e) {
          if (e is DateTime) return e.toIso8601String();
          if (e is Map<String, dynamic>) return _sanitizeDoc(e);
          return e;
        }).toList();
      } else {
        result[key] = value;
      }
    });
    return result;
  }
}
