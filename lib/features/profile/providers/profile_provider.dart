import 'package:climate_app/core/services/secure_storage_service.dart';
import 'package:climate_app/core/services/appwrite_service.dart';
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
  final Connectivity _connectivity;

  String _name = 'User';
  String _email = '';
  String _phone = '';
  String? _profileImagePath;
  String? _state;
  String? _lga;
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

            // Update local state from Appwrite
            _name = data['name'] ?? 'User';
            _email = data['email'] ?? user.email;
            _phone = data['phone'] ?? user.phone ?? '';
            _state = data['state'];
            _lga = data['lga'];

            // Only overwrite monitoring zone if remote value is not null/empty
            final remoteZone = data['monitoringZone'] as String?;
            if (remoteZone != null && remoteZone.isNotEmpty) {
              _monitoringZone = remoteZone;
              await _storage.write('monitoring_zone', remoteZone);
            } else {
              // Try to load from local storage if remote is empty
              _monitoringZone =
                  await _storage.read('monitoring_zone') ?? 'Benue State';
            }

            _registrationCode = data['registrationCode'];
            _biometricsEnabled = data['biometricsEnabled'] ?? false;

            if (data['profileImage'] != null) {
              _profileImagePath = data['profileImage'];
            }

            // Secure cache to local storage
            await _storage.write('profile_name', _name);
            await _storage.write('profile_email', _email);
            await _storage.write('profile_phone', _phone);

            if (_state != null) await _storage.write('profile_state', _state!);
            if (_lga != null) await _storage.write('profile_lga', _lga!);
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
        _monitoringZone =
            await _storage.read('monitoring_zone') ?? 'Benue State';
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
  void clearProfile() {
    _name = 'User';
    _email = '';
    _phone = '';
    _profileImagePath = null;
    _state = null;
    _lga = null;
    _monitoringZone = 'Benue State';
    _registrationCode = null;
    _registrationDate = null;
    _biometricsEnabled = false;
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

  Future<void> updateName(String name) async {
    _name = name;
    await _storage.write('profile_name', name);
    notifyListeners();
    await _syncToAppwrite({'name': name});
  }

  Future<void> updateEmail(String email) async {
    _email = email;
    await _storage.write('profile_email', email);
    notifyListeners();
    await _syncToAppwrite({'email': email});
  }

  Future<void> updatePhone(String phone) async {
    _phone = phone;
    await _storage.write('profile_phone', phone);
    notifyListeners();
    await _syncToAppwrite({'phone': phone});
  }

  Future<void> updateProfileImage(String imagePath) async {
    _profileImagePath = imagePath;
    await _storage.write('profile_image', imagePath);
    notifyListeners();
    await _syncToAppwrite({'profileImage': imagePath});
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

      // Sync to Appwrite Database
      await _syncToAppwrite({'profileImage': fileUrl});

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
    await _syncToAppwrite({'state': state, 'lga': lga});
  }

  Future<void> updateMonitoringZone(String zone) async {
    _monitoringZone = zone;
    await _storage.write('monitoring_zone', zone);
    notifyListeners();
    await _syncToAppwrite({'monitoringZone': zone});
  }

  Future<void> setBiometricsEnabled(bool enabled) async {
    _biometricsEnabled = enabled;
    await _storage.write('biometric_enabled', enabled.toString());
    notifyListeners();
    await _syncToAppwrite({'biometricsEnabled': enabled});
  }

  Future<void> updateFCMToken(String token) async {
    await _syncToAppwrite({'fcmToken': token});
  }
}
