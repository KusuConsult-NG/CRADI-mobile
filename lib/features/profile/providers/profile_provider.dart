import 'package:climate_app/core/services/secure_storage_service.dart';
import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/core/services/offline_storage_service.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:io';
import 'dart:developer' as developer;

/// Provider for managing user profile data (Supabase `profiles` row).
class ProfileProvider extends ChangeNotifier {
  ProfileProvider({
    SupabaseService? supabaseService,
    Connectivity? connectivity,
  }) : _db = supabaseService ?? SupabaseService(),
       _connectivity = connectivity ?? Connectivity() {
    loadProfile();
  }

  final SecureStorageService _storage = SecureStorageService();
  final SupabaseService _db;
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

  /// Get current user's reports as a realtime stream.
  Stream<List<Map<String, dynamic>>> getUserReportsStream() {
    final user = _db.getCurrentUser();
    if (user == null) return const Stream.empty();

    return _db.subscribeToCollection(
      collectionId: AppConfig.reportsCollection,
      queries: [FQuery.equal('userId', user.id), FQuery.orderDesc('createdAt')],
    );
  }

  Future<void> loadProfile() async {
    _isLoading = true;
    notifyListeners();

    try {
      final user = _db.getCurrentUser();

      if (user != null) {
        _email = user.email ?? '';
        // ── Fast path: load from secure-storage cache immediately ──────────
        // This ensures the name is correct on the very first frame,
        // without waiting for the network round-trip.
        final cachedEmail = await _storage.read('profile_email');
        if (cachedEmail == user.email) {
          final cachedName = await _storage.read('profile_name');
          if (cachedName != null && cachedName.isNotEmpty) {
            _name = cachedName;
          } else {
            _name = _metadataName(user);
          }
          _phone = await _storage.read('profile_phone') ?? '';
          _profileImagePath = await _storage.read('profile_image');
          _state = await _storage.read('profile_state');
          _lga = await _storage.read('profile_lga');
          _ward = await _storage.read('profile_ward');
          final storedZone = await _storage.read('monitoring_zone');
          _monitoringZone = (storedZone != null && storedZone.isNotEmpty)
              ? storedZone
              : null;
          final bioEnabled = await _storage.read('biometric_enabled');
          _biometricsEnabled = bioEnabled == 'true';
          // Notify immediately so the UI shows cached data, then continue
          // fetching from the server to refresh.
          notifyListeners();
        } else {
          _name = _metadataName(user);
        }
        _registrationDate = parseTimestamp(user.createdAt);

        // Load the profiles row (source of truth)
        try {
          final doc = await _db.getDocument(
            collectionId: AppConfig.usersCollection,
            documentId: user.id,
          );

          if (doc.isNotEmpty) {
            // Rows are plain JSON (timestamps are ISO strings), so they can
            // be cached in Hive as-is.
            _userProfile = Map<String, dynamic>.from(doc);
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
              final storedZone = await _storage.read('monitoring_zone');
              _monitoringZone = (storedZone != null && storedZone.isNotEmpty)
                  ? storedZone
                  : null;
            }

            final imageUrl = doc['profileImageUrl'] as String?;
            if (imageUrl != null && imageUrl.isNotEmpty) {
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

            developer.log('Profile loaded: ${user.id}');
          }
        } on Exception catch (e) {
          developer.log('Profile fetch error, using local fallback: $e');
          final cached = _offlineStorage.getCachedUserProfile();
          if (cached != null) {
            _userProfile = cached;
          }
        }
      } else {
        await clearProfile();
      }
    } on Exception catch (e) {
      developer.log('Error loading profile: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Resets all profile data to default values (called on logout).
  ///
  /// Only the cached profile is removed. Offline drafts and the sync queue
  /// are owner-tagged and filtered per user, so they are kept: wiping them
  /// here would destroy reports that have not been uploaded yet.
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
    try {
      await _offlineStorage.clearUserProfile();
    } on Exception catch (e) {
      // Hive may not be initialised yet (e.g. signed-out cold start).
      developer.log('Could not clear cached profile: $e');
    }
    notifyListeners();
  }

  /// Push profile changes to the `profiles` row.
  Future<void> _syncToServer(Map<String, dynamic> data) async {
    try {
      final user = _db.getCurrentUser();
      if (user == null) return;

      final connectivityResults = await _connectivity.checkConnectivity();
      final hasConnection = connectivityResults.any(
        (result) => result != ConnectivityResult.none,
      );

      if (!hasConnection) {
        developer.log('Offline - profile update will be cached locally');
        return;
      }

      await _db.updateDocument(
        collectionId: AppConfig.usersCollection,
        documentId: user.id,
        data: data,
      );

      developer.log('Profile synced', name: 'ProfileProvider');
    } on Exception catch (e) {
      developer.log('Error syncing profile: $e', name: 'ProfileProvider');
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
    await _syncToServer({'name': name});
  }

  /// Request an email change.
  ///
  /// The sign-in email lives in Supabase Auth: `updateUser(email:)` makes
  /// Supabase send a confirmation link to the new address. The change only
  /// takes effect once it is confirmed; a database trigger then mirrors the
  /// new email into the `profiles` row.
  ///
  /// Returns a user-facing message describing the outcome, or `null` when
  /// [email] is unchanged. Never throws.
  Future<String?> updateEmail(String email) async {
    final newEmail = email.trim();
    final user = _db.getCurrentUser();
    if (newEmail.isEmpty ||
        newEmail.toLowerCase() == (user?.email ?? _email).toLowerCase()) {
      return null;
    }
    if (user == null) {
      return 'You must be signed in to change your email.';
    }

    try {
      await _db.auth.updateUser(sb.UserAttributes(email: newEmail));
      developer.log(
        'Email change confirmation sent to $newEmail',
        name: 'ProfileProvider',
      );
      return 'A confirmation link has been sent to $newEmail. Your email '
          'will change after you confirm it.';
    } on sb.AuthException catch (e) {
      developer.log(
        'updateEmail error: ${e.code} ${e.message}',
        name: 'ProfileProvider',
      );
      switch (e.code) {
        case 'reauthentication_needed':
          return 'For security, please log out and sign in again before '
              'changing your email.';
        case 'validation_failed':
        case 'email_address_invalid':
          return 'Please enter a valid email address.';
        case 'email_exists':
          return 'That email is already in use by another account.';
        default:
          return 'Could not update email. Please try again.';
      }
    } on Exception catch (e) {
      developer.log('updateEmail error: $e', name: 'ProfileProvider');
      return 'Could not update email. Please try again.';
    }
  }

  Future<void> updatePhone(String phone) async {
    _phone = phone;
    await _storage.write('profile_phone', phone);
    await _updateLocalState({'phone': phone});
    notifyListeners();
    await _syncToServer({'phone': phone});
  }

  Future<void> updateProfileImage(String imagePath) async {
    _profileImagePath = imagePath;
    await _storage.write('profile_image', imagePath);
    await _updateLocalState({'profileImageUrl': imagePath});
    notifyListeners();
    await _syncToServer({'profileImageUrl': imagePath});
  }

  /// Upload profile image to the `profile-images` bucket and store its URL.
  Future<void> uploadProfileImage(XFile imageFile) async {
    try {
      _isLoading = true;
      notifyListeners();

      final user = _db.getCurrentUser();
      if (user == null) {
        throw Exception('User must be logged in to upload profile image');
      }

      final file = File(imageFile.path);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      // Images are re-encoded as JPEG before upload. The first path segment
      // must be the user id (storage RLS).
      final storagePath = '${user.id}/profile_$timestamp.jpg';

      developer.log(
        'Uploading profile image: $storagePath',
        name: 'ProfileProvider',
      );

      final fileUrl = await _db.uploadFileFromPath(
        bucketId: AppConfig.profileImagesBucket,
        storagePath: storagePath,
        file: file,
        contentType: 'image/jpeg',
      );

      _profileImagePath = fileUrl;
      await _storage.write('profile_image', fileUrl);
      await _updateLocalState({'profileImageUrl': fileUrl});
      await _syncToServer({'profileImageUrl': fileUrl});

      developer.log('Profile image uploaded: $fileUrl');
    } on Exception catch (e) {
      developer.log('Error uploading profile image: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Updates the profile location. Returns a user-facing message when the
  /// change was not saved, otherwise null.
  ///
  /// The columns are NOT NULL, so all three parts must be present. The
  /// local state only changes once the server accepted the update (there is
  /// no retry queue for profile edits, so an offline change is not kept).
  Future<String?> updateLocation(
    String? state,
    String? lga,
    String? ward,
  ) async {
    final s = state?.trim() ?? '';
    final l = lga?.trim() ?? '';
    final w = ward?.trim() ?? '';
    if (s == (_state ?? '') && l == (_lga ?? '') && w == (_ward ?? '')) {
      return null;
    }
    if (s.isEmpty || l.isEmpty || w.isEmpty) {
      return 'Please select your state, LGA and ward to update your location.';
    }

    final user = _db.getCurrentUser();
    if (user == null) return 'You must be signed in to change your location.';
    try {
      await _db.updateDocument(
        collectionId: AppConfig.usersCollection,
        documentId: user.id,
        data: {'state': s, 'lga': l, 'ward': w},
      );
    } on Exception catch (e) {
      if (SupabaseService.isPermissionDenied(e) ||
          e is DocumentNotFoundException) {
        return 'Your location is managed by an administrator. '
            'Please ask an admin to change the location of a staff account.';
      }
      developer.log('Location sync failed: $e', name: 'ProfileProvider');
      return 'Could not update your location. Please check your connection '
          'and try again.';
    }

    _state = s;
    _lga = l;
    _ward = w;
    await _storage.write('profile_state', s);
    await _storage.write('profile_lga', l);
    await _storage.write('profile_ward', w);
    await _updateLocalState({'state': s, 'lga': l, 'ward': w});
    notifyListeners();
    return null;
  }

  /// Called after the monitoring zone changed (e.g. to refresh zone-filtered
  /// report lists). Wired in `main.dart`.
  void Function(String? zone)? onMonitoringZoneChanged;

  /// Sets the monitoring zone; an empty [zone] means "all zones" (null).
  Future<void> updateMonitoringZone(String zone) async {
    final trimmed = zone.trim();
    final String? effectiveZone = trimmed.isEmpty ? null : trimmed;
    final changed = effectiveZone != _monitoringZone;
    _monitoringZone = effectiveZone;
    await _storage.write('monitoring_zone', effectiveZone ?? '');
    // The column is NOT NULL (default ''): "all zones" is stored as ''.
    await _updateLocalState({'monitoringZone': effectiveZone ?? ''});
    notifyListeners();
    if (changed) onMonitoringZoneChanged?.call(effectiveZone);
    await _syncToServer({'monitoringZone': effectiveZone ?? ''});
  }

  Future<void> setBiometricsEnabled(bool enabled) async {
    _biometricsEnabled = enabled;
    await _storage.write('biometric_enabled', enabled.toString());
    await _updateLocalState({'biometricsEnabled': enabled});
    notifyListeners();
    await _syncToServer({'biometricsEnabled': enabled});
  }

  static String _metadataName(sb.User user) {
    final n = user.userMetadata?['name'];
    return (n is String && n.trim().isNotEmpty) ? n : 'User';
  }
}
