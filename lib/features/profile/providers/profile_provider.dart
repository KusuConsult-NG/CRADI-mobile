import 'package:climate_app/core/services/secure_storage_service.dart';
import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/core/services/offline_storage_service.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/core/utils/input_sanitizer.dart';
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

  /// Bumped by [clearProfile] and by every [loadProfile]: a load that was
  /// superseded (or outlived a sign-out) drops its results instead of
  /// writing another user's data into this provider or the device cache.
  int _loadGen = 0;

  /// Secure-storage keys caching the signed-in user's profile.
  static const List<String> _profileStorageKeys = [
    'profile_name',
    'profile_email',
    'profile_phone',
    'profile_image',
    'profile_state',
    'profile_lga',
    'profile_ward',
    'monitoring_zone',
  ];

  Future<void> loadProfile() async {
    final gen = ++_loadGen;
    final user = _db.getCurrentUser();
    final uid = user?.id;
    bool stale() => gen != _loadGen || _db.currentUserId != uid;

    _isLoading = true;
    notifyListeners();

    try {
      if (user != null) {
        _email = user.email ?? '';
        // ── Fast path: load from secure-storage cache immediately ──────────
        // This ensures the name is correct on the very first frame,
        // without waiting for the network round-trip.
        final cachedEmail = await _storage.read('profile_email');
        if (stale()) return;
        if (cachedEmail == user.email) {
          final cachedName = await _storage.read('profile_name');
          final phone = await _storage.read('profile_phone');
          final image = await _storage.read('profile_image');
          final state = await _storage.read('profile_state');
          final lga = await _storage.read('profile_lga');
          final ward = await _storage.read('profile_ward');
          final storedZone = await _storage.read('monitoring_zone');
          final bioEnabled = await _storage.isBiometricEnabled();
          if (stale()) return;
          _name = (cachedName != null && cachedName.isNotEmpty)
              ? cachedName
              : _metadataName(user);
          _phone = phone ?? '';
          _profileImagePath = image;
          _state = state;
          _lga = lga;
          _ward = ward;
          _monitoringZone = (storedZone != null && storedZone.isNotEmpty)
              ? storedZone
              : null;
          _biometricsEnabled = bioEnabled;
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
          if (stale()) return;

          if (doc.isNotEmpty) {
            // Rows are plain JSON (timestamps are ISO strings), so they can
            // be cached in Hive as-is.
            _userProfile = Map<String, dynamic>.from(doc);

            _name = doc['name'] ?? _name;
            _email = doc['email'] ?? _email;
            _phone = doc['phone'] ?? '';
            _state = doc['state'];
            _lga = doc['lga'];
            _ward = doc['ward'];
            _registrationCode = doc['registrationCode'];
            // The row's biometricsEnabled is informational only: the
            // device lock is per device and is read from local storage,
            // never overwritten from the server (a device without
            // biometrics would lock the user out).
            _biometricsEnabled = await _storage.isBiometricEnabled();
            if (stale()) return;

            // The row is the truth: '' (the column default) means "all
            // zones", so a zone cached on this device (possibly by another
            // account) must not be used instead.
            final remoteZone = (doc['monitoringZone'] as String?)?.trim();
            final zoneBefore = _monitoringZone;
            _monitoringZone = (remoteZone != null && remoteZone.isNotEmpty)
                ? remoteZone
                : null;
            // Lists may already have loaded with the previous (or no) zone,
            // e.g. when an overlapping load was superseded; refetch them.
            if (_monitoringZone != zoneBefore) {
              onMonitoringZoneChanged?.call(_monitoringZone);
            }

            final imageUrl = doc['profileImageUrl'] as String?;
            if (imageUrl != null && imageUrl.isNotEmpty) {
              _profileImagePath = imageUrl;
            }
            notifyListeners();

            // Cache locally; stop as soon as the load became stale so the
            // cache never receives another account's profile.
            try {
              await _offlineStorage.cacheUserProfile(_userProfile!);
            } on Object catch (e) {
              developer.log('Could not cache profile: $e');
            }
            final cache = <String, String?>{
              'profile_name': _name,
              'profile_email': _email,
              'profile_phone': _phone,
              'profile_state': _state,
              'profile_lga': _lga,
              'profile_ward': _ward,
              'profile_image': _profileImagePath,
              'monitoring_zone': _monitoringZone ?? '',
            };
            for (final entry in cache.entries) {
              if (stale()) return;
              final value = entry.value;
              if (value == null) {
                await _storage.delete(entry.key);
              } else {
                await _storage.write(entry.key, value);
              }
            }

            developer.log('Profile loaded: ${user.id}');
          }
        } on Exception catch (e) {
          if (stale()) return;
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
      // A newer load or a clear owns the loading flag now.
      if (gen == _loadGen) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Resets all profile data to default values (called on logout).
  ///
  /// The cached profile (Hive and secure storage) is removed so the next
  /// account on a shared device never starts from it. Offline drafts and
  /// the sync queue are owner-tagged and filtered per user, so they are
  /// kept: wiping them here would destroy reports that have not been
  /// uploaded yet.
  Future<void> clearProfile() async {
    _loadGen++;
    _isLoading = false;
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
    notifyListeners();
    try {
      for (final key in _profileStorageKeys) {
        await _storage.delete(key);
      }
    } on Object catch (e) {
      developer.log('Could not clear cached profile keys: $e');
    }
    try {
      await _offlineStorage.clearUserProfile();
    } on Object catch (e) {
      // Hive may not be initialised yet (e.g. signed-out cold start); a
      // HiveError is an Error, not an Exception.
      developer.log('Could not clear cached profile: $e');
    }
  }

  /// Message shown when a profile edit could not be saved while offline.
  static const String offlineNotSavedMessage =
      "You're offline — changes not saved.";

  /// Push profile changes to the `profiles` row.
  ///
  /// Returns null when the server accepted the change, otherwise a
  /// user-facing message (offline, signed out, server error). There is no
  /// retry queue for profile edits, so callers must report the failure.
  Future<String?> _syncToServer(Map<String, dynamic> data) async {
    try {
      final user = _db.getCurrentUser();
      if (user == null) return 'You must be signed in to update your profile.';

      final connectivityResults = await _connectivity.checkConnectivity();
      final hasConnection = connectivityResults.any(
        (result) => result != ConnectivityResult.none,
      );

      if (!hasConnection) {
        developer.log('Offline - profile update not saved');
        return offlineNotSavedMessage;
      }

      await _db.updateDocument(
        collectionId: AppConfig.usersCollection,
        documentId: user.id,
        data: data,
      );

      developer.log('Profile synced', name: 'ProfileProvider');
      return null;
    } on Exception catch (e) {
      developer.log('Error syncing profile: $e', name: 'ProfileProvider');
      return 'Could not save your changes. Please check your connection '
          'and try again.';
    }
  }

  Future<void> _updateLocalState(Map<String, dynamic> updates) async {
    _userProfile ??= {};
    _userProfile!.addAll(updates);
    // Best effort: the change is already saved on the server.
    try {
      await _offlineStorage.cacheUserProfile(_userProfile!);
    } on Object catch (e) {
      developer.log('Could not cache profile: $e', name: 'ProfileProvider');
    }
  }

  /// Cleans a display name for storage; returns '' when nothing is left.
  static String cleanName(String name) =>
      InputSanitizer.cleanForStorage(name).trim();

  /// Updates the display name. Returns null when saved, otherwise a
  /// user-facing message (the local name is then left unchanged).
  Future<String?> updateName(String name) async {
    final cleaned = cleanName(name);
    if (cleaned.isEmpty) return 'Please enter your name.';
    if (cleaned == _name) return null;
    final error = await _syncToServer({'name': cleaned});
    if (error != null) return error;
    _name = cleaned;
    await _storage.write('profile_name', cleaned);
    await _updateLocalState({'name': cleaned});
    notifyListeners();
    return null;
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

  /// Updates the phone number. Returns null when saved, otherwise a
  /// user-facing message (the local value is then left unchanged).
  Future<String?> updatePhone(String phone) async {
    final error = await _syncToServer({'phone': phone});
    if (error != null) return error;
    _phone = phone;
    await _storage.write('profile_phone', phone);
    await _updateLocalState({'phone': phone});
    notifyListeners();
    return null;
  }

  /// Updates the profile image URL. Returns null when saved, otherwise a
  /// user-facing message (the local value is then left unchanged).
  Future<String?> updateProfileImage(String imagePath) async {
    final error = await _syncToServer({'profileImageUrl': imagePath});
    if (error != null) return error;
    _profileImagePath = imagePath;
    await _storage.write('profile_image', imagePath);
    await _updateLocalState({'profileImageUrl': imagePath});
    notifyListeners();
    return null;
  }

  /// Upload profile image to the `profile-images` bucket and store its URL.
  ///
  /// Throws a [ProfileSaveException] (with a user-facing message) when the
  /// device is offline or the profile row could not be updated.
  Future<void> uploadProfileImage(XFile imageFile) async {
    try {
      _isLoading = true;
      notifyListeners();

      final user = _db.getCurrentUser();
      if (user == null) {
        throw Exception('User must be logged in to upload profile image');
      }

      final connectivityResults = await _connectivity.checkConnectivity();
      if (!connectivityResults.any((r) => r != ConnectivityResult.none)) {
        throw const ProfileSaveException(offlineNotSavedMessage);
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

      final error = await _syncToServer({'profileImageUrl': fileUrl});
      if (error != null) throw ProfileSaveException(error);
      _profileImagePath = fileUrl;
      await _storage.write('profile_image', fileUrl);
      await _updateLocalState({'profileImageUrl': fileUrl});

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
  ///
  /// The zone is applied on this device right away (it filters local
  /// lists). Returns null when it was also saved to the account, otherwise
  /// a user-facing message.
  Future<String?> updateMonitoringZone(String zone) async {
    final trimmed = zone.trim();
    final String? effectiveZone = trimmed.isEmpty ? null : trimmed;
    final changed = effectiveZone != _monitoringZone;
    _monitoringZone = effectiveZone;
    await _storage.write('monitoring_zone', effectiveZone ?? '');
    // The column is NOT NULL (default ''): "all zones" is stored as ''.
    await _updateLocalState({'monitoringZone': effectiveZone ?? ''});
    notifyListeners();
    if (changed) onMonitoringZoneChanged?.call(effectiveZone);
    return _syncToServer({'monitoringZone': effectiveZone ?? ''});
  }

  /// Re-reads the device's biometric lock flag for display. The flag is
  /// written only by AuthProvider.setBiometricEnabled.
  Future<void> refreshBiometricsEnabled() async {
    _biometricsEnabled = await _storage.isBiometricEnabled();
    notifyListeners();
  }

  static String _metadataName(sb.User user) {
    final n = user.userMetadata?['name'];
    return (n is String && n.trim().isNotEmpty) ? n : 'User';
  }
}

/// A profile edit that was not saved to the server; [message] is
/// user-facing.
class ProfileSaveException implements Exception {
  const ProfileSaveException(this.message);
  final String message;

  @override
  String toString() => message;
}
