import 'package:climate_app/core/services/secure_storage_service.dart';
import 'package:climate_app/core/services/appwrite_service.dart';
import 'package:climate_app/core/services/offline_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:io';
import 'dart:async';
import 'dart:developer' as developer;
import 'package:appwrite/appwrite.dart';

/// Provider for managing user profile data with Appwrite
class ProfileProvider extends ChangeNotifier {
  ProfileProvider({
    AppwriteService? appwriteService,
    Connectivity? connectivity,
  }) : _appwrite = appwriteService ?? AppwriteService(),
       _connectivity = connectivity ?? Connectivity() {
    loadProfile();
  }

  final SecureStorageService _storage = SecureStorageService();
  final AppwriteService _appwrite;
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

  /// Get current user's reports stream using Realtime
  Stream<List<Map<String, dynamic>>> getUserReportsStream() {
    final controller = StreamController<List<Map<String, dynamic>>>();
    RealtimeSubscription? subscription;

    void updateReports() async {
      try {
        final user = await _appwrite.getCurrentUser();
        if (user == null) {
          if (!controller.isClosed) controller.add([]);
          return;
        }

        final reports = await _appwrite.listDocuments(
          collectionId: AppwriteService.reportsCollectionId,
          queries: [Query.equal('userId', user.$id)],
        );

        if (!controller.isClosed) {
          controller.add(reports.documents.map((doc) => doc.data).toList());
        }
      } on Exception catch (e) {
        developer.log('Error updating user reports: $e');
      }
    }

    // Initial fetch
    updateReports();

    // Subscribe to realtime updates
    const channel =
        'databases.${AppwriteService.databaseId}.collections.${AppwriteService.reportsCollectionId}.documents';

    subscription = _appwrite.subscribe(
      channels: [channel],
      callback: (event) {
        updateReports();
      },
    );

    controller.onCancel = () {
      subscription?.close();
      controller.close();
    };

    return controller.stream;
  }

  Future<void> loadProfile() async {
    _isLoading = true;
    notifyListeners();

    try {
      final user = await _appwrite.getCurrentUser();

      if (user != null) {
        _registrationDate = DateTime.tryParse(user.registration);
        _email = user.email; // Source of truth

        // Load from Appwrite Database FIRST (Source of Truth)
        try {
          final doc = await _appwrite.getDocument(
            collectionId: AppwriteService.usersCollectionId,
            documentId: user.$id,
          );

          if (doc.data.isNotEmpty) {
            final data = doc.data;
            _userProfile = data;

            // Cache the fresh profile
            await _offlineStorage.cacheUserProfile(_userProfile!);

            // Update local state from Appwrite
            _name = data['name'] ?? 'User';
            _email = data['email'] ?? user.email;
            _phone = data['phone'] ?? user.phone ?? '';
            _state = data['state'];
            _lga = data['lga'];
            _ward = data['ward'];

            // Only overwrite monitoring zone if remote value is not null/empty
            final remoteZone = data['monitoringZone'] as String?;
            if (remoteZone != null && remoteZone.isNotEmpty) {
              _monitoringZone = remoteZone;
              await _storage.write('monitoring_zone', remoteZone);
            } else {
              // Try to load from local storage if remote is empty
              _monitoringZone = await _storage.read('monitoring_zone');
            }

            _registrationCode = data['registrationCode'];
            _biometricsEnabled = data['biometricsEnabled'] ?? false;

            if (data['profileImageId'] != null) {
              _profileImagePath = data['profileImageId'];
            }

            // Secure cache to local storage
            await _storage.write('profile_name', _name);
            await _storage.write('profile_email', _email);
            await _storage.write('profile_phone', _phone);

            if (_state != null) await _storage.write('profile_state', _state!);
            if (_lga != null) await _storage.write('profile_lga', _lga!);
            if (_ward != null) await _storage.write('profile_ward', _ward!);
            if (_monitoringZone != null) {
              await _storage.write('monitoring_zone', _monitoringZone!);
            }
            if (_profileImagePath != null) {
              await _storage.write('profile_image', _profileImagePath!);
            }
            await _storage.write(
              'biometric_enabled',
              _biometricsEnabled.toString(),
            );

            developer.log('Profile loaded from Appwrite: ${user.$id}');
          }
        } on AppwriteException catch (e) {
          developer.log('Appwrite error, sliding to local fallback: $e');
          // Fallback to offline cache
          final cached = _offlineStorage.getCachedUserProfile();
          if (cached != null) {
            _userProfile = cached;
            developer.log(
              'Loaded profile from offline cache',
              name: 'ProfileProvider',
            );
          }
        }
      }

      // Fallback: ONLY load from local storage if it belongs to the current user
      final cachedEmail = await _storage.read('profile_email');
      if (user != null && cachedEmail == user.email) {
        _name = await _storage.read('profile_name') ?? 'User';
        _phone = await _storage.read('profile_phone') ?? '';
        _profileImagePath = await _storage.read('profile_image');
        _state = await _storage.read('profile_state');
        _lga = await _storage.read('profile_lga');
        _ward = await _storage.read('profile_ward');
        _monitoringZone = await _storage.read('monitoring_zone');
        final bioEnabled = await _storage.read('biometric_enabled');
        _biometricsEnabled = bioEnabled == 'true';
        developer.log('Profile loaded from local storage for current user');
      } else if (user == null) {
        // No session, ensure state is clear
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
    _monitoringZone = null; // Let user select their actual zone
    _registrationCode = null;
    _registrationDate = null;
    _biometricsEnabled = false;
    _userProfile = null; // Clear local memory cache

    // Clear offline storage cache (including drafts and sync queue)
    await _offlineStorage.clearUserData();

    notifyListeners();
  }

  /// Helper to sync changes to Appwrite Database
  Future<void> _syncToAppwrite(Map<String, dynamic> data) async {
    try {
      final user = await _appwrite.getCurrentUser();
      if (user == null) return;

      // Check connectivity
      final connectivityResults = await _connectivity.checkConnectivity();
      final hasConnection = connectivityResults.any(
        (result) => result != ConnectivityResult.none,
      );

      if (!hasConnection) {
        developer.log('Offline - profile update will be cached locally');
        return;
      }

      // Online: sync directly to Appwrite
      await _appwrite.updateDocument(
        collectionId: AppwriteService.usersCollectionId,
        documentId: user.$id,
        data: data,
      );

      developer.log('Profile synced to Appwrite', name: 'ProfileProvider');
    } on AppwriteException catch (e) {
      developer.log(
        'Appwrite error syncing profile: ${e.message}',
        name: 'ProfileProvider',
      );
    } on Exception catch (e) {
      developer.log('Error syncing to Appwrite: $e', name: 'ProfileProvider');
    }
  }

  /// Helper to update local state and cache
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
    await _syncToAppwrite({'name': name});
  }

  Future<void> updateEmail(String email) async {
    _email = email;
    await _storage.write('profile_email', email);
    await _updateLocalState({'email': email});
    notifyListeners();
    await _syncToAppwrite({'email': email});
  }

  Future<void> updatePhone(String phone) async {
    _phone = phone;
    await _storage.write('profile_phone', phone);
    await _updateLocalState({'phone': phone});
    notifyListeners();
    await _syncToAppwrite({'phone': phone});
  }

  Future<void> updateProfileImage(String imagePath) async {
    _profileImagePath = imagePath;
    await _storage.write('profile_image', imagePath);
    await _updateLocalState({'profileImageId': imagePath});
    notifyListeners();
    await _syncToAppwrite({'profileImageId': imagePath});
  }

  /// Upload profile image to Appwrite Storage and update Database
  Future<void> uploadProfileImage(XFile imageFile) async {
    try {
      _isLoading = true;
      notifyListeners();

      final user = await _appwrite.getCurrentUser();
      if (user == null) {
        throw Exception('User must be logged in to upload profile image');
      }

      final file = File(imageFile.path);
      final fileBytes = await file.readAsBytes();

      // Upload to Appwrite Storage
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ext = imageFile.path.split('.').last.toLowerCase();
      final validExt = (ext == 'png' || ext == 'jpg' || ext == 'jpeg')
          ? ext
          : 'jpg';

      final fileName = 'profile_${user.$id}_$timestamp.$validExt';

      developer.log(
        'Starting upload to Appwrite Storage: $fileName',
        name: 'ProfileProvider',
      );

      final uploadedFile = await _appwrite.uploadFile(
        bucketId: AppwriteService.profileImagesBucketId,
        filePath: file.path,
        fileBytes: fileBytes,
      );

      // Get file view URL
      final fileUrl = _appwrite.getFileView(
        bucketId: AppwriteService.profileImagesBucketId,
        fileId: uploadedFile.$id,
      );

      // Update local state and storage
      _profileImagePath = fileUrl;
      await _storage.write('profile_image', fileUrl);
      await _updateLocalState({'profileImageId': fileUrl});

      // Sync to Appwrite Database
      await _syncToAppwrite({'profileImageId': fileUrl});

      developer.log('Profile image uploaded successfully: $fileUrl');
    } on AppwriteException catch (e) {
      developer.log('Appwrite Storage Error: ${e.message}', error: e);
      throw Exception('Upload failed: ${e.message}');
    } catch (e) {
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
    if (state != null) {
      await _storage.write('profile_state', state);
    }
    if (lga != null) {
      await _storage.write('profile_lga', lga);
    }
    if (ward != null) {
      await _storage.write('profile_ward', ward);
    }
    await _updateLocalState({'state': state, 'lga': lga, 'ward': ward});
    notifyListeners();
    await _syncToAppwrite({'state': state, 'lga': lga, 'ward': ward});
  }

  Future<void> updateMonitoringZone(String zone) async {
    _monitoringZone = zone;
    await _storage.write('monitoring_zone', zone);
    await _updateLocalState({'monitoringZone': zone});
    notifyListeners();
    await _syncToAppwrite({'monitoringZone': zone});
  }

  Future<void> setBiometricsEnabled(bool enabled) async {
    _biometricsEnabled = enabled;
    await _storage.write('biometric_enabled', enabled.toString());
    await _updateLocalState({'biometricsEnabled': enabled});
    notifyListeners();
    await _syncToAppwrite({'biometricsEnabled': enabled});
  }

  Future<void> updateFCMToken(String token) async {
    await _updateLocalState({'fcmToken': token});
    await _syncToAppwrite({'fcmToken': token});
  }
}
