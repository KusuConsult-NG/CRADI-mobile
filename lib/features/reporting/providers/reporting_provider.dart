import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:climate_app/core/services/backend.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:climate_app/core/services/offline_storage_service.dart';
import 'package:climate_app/core/data/mvp_locations_data.dart';
import 'package:climate_app/core/providers/connectivity_provider.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/core/utils/image_url_resolver.dart';
import 'dart:developer' as developer;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:climate_app/core/l10n/l10n.dart';

enum SeverityLevel { low, medium, high, critical }

/// Normalizes any stored/legacy severity value (e.g. 'High Severity', 'HIGH',
/// 'critical') to the canonical lowercase value: 'low' | 'medium' | 'high' |
/// 'critical'. Returns null when the value is missing or unrecognised.
String? normalizeSeverity(Object? raw) {
  if (raw == null) return null;
  final value = raw.toString().trim().toLowerCase().replaceAll(
    RegExp(r'\s*severity$'),
    '',
  );
  for (final level in SeverityLevel.values) {
    if (value == level.name) return level.name;
  }
  if (value == 'moderate') return SeverityLevel.medium.name;
  if (value == 'severe' || value == 'extreme') {
    return SeverityLevel.critical.name;
  }
  return null;
}

/// Whether a severity (canonical or legacy label) should raise an alert.
bool isAlertSeverity(Object? raw) {
  final s = normalizeSeverity(raw);
  return s == SeverityLevel.high.name || s == SeverityLevel.critical.name;
}

class ReportingProvider extends ChangeNotifier {
  ReportingProvider({DataBackend? db, OfflineStorageService? offlineStorage})
    : _db = db ?? backend,
      _offline = offlineStorage ?? OfflineStorageService();

  /// Upper bound for one photo upload; a stalled upload is treated like a
  /// lost connection (the report is kept for offline sync).
  static const Duration photoUploadTimeout = Duration(seconds: 60);

  /// Storage object path of photo [index] of report [reportId]. Deterministic
  /// so a retried upload (online retry or offline sync) reuses an object an
  /// earlier attempt already stored instead of orphaning it.
  static String reportPhotoStoragePath(
    String uid,
    String reportId,
    int index,
    String fileName,
  ) => '$uid/${reportId}_${index}_$fileName';

  /// Storage path for photo [index] of [draft] when synced as [uid]: the
  /// path recorded by an interrupted online submission (so already uploaded
  /// photos are reused), else the default for [reportId].
  static String draftPhotoStoragePath(
    Map<String, dynamic> draft, {
    required String uid,
    required String reportId,
    required int index,
    required String fileName,
  }) {
    final recorded = draft['imageStoragePaths'];
    if (recorded is List && index < recorded.length) {
      final path = recorded[index];
      // Storage RLS only allows the uploader's own folder.
      if (path is String && path.startsWith('$uid/')) return path;
    }
    return reportPhotoStoragePath(uid, reportId, index, fileName);
  }

  /// Longest-edge target and JPEG quality of the thumbnail uploaded next to
  /// every report photo. List and grid views render a box of at most ~200
  /// logical pixels, so ~320px covers it on a 1.5x screen at a fraction of
  /// the bytes of the 1024px original.
  static const int thumbnailMaxDimension = 320;
  static const int thumbnailQuality = 70;

  /// Uploads the small preview that goes next to the photo at
  /// [storagePath] (same folder, `_thumb.jpg` — see
  /// [ImageUrlResolver.thumbStoragePath], which is also how display code
  /// finds it again).
  ///
  /// Best effort: a report is never rejected because its thumbnail failed,
  /// and views fall back to the full-size image. Idempotent — the path is
  /// deterministic and an object an earlier attempt already stored is
  /// reused (upsert is off; storage has no update policy for evidence).
  Future<void> _uploadThumbnail(File file, String storagePath) async {
    try {
      await _db
          .uploadFileFromPath(
            bucketId: AppConfig.reportImagesBucket,
            storagePath: ImageUrlResolver.thumbStoragePath(storagePath),
            file: file,
            maxDimension: thumbnailMaxDimension,
            quality: thumbnailQuality,
          )
          .timeout(photoUploadTimeout);
    } on Exception catch (e) {
      developer.log('Thumbnail upload failed for $storagePath: $e');
    }
  }

  /// Maximum length of the free-text description.
  static const int maxDescriptionLength = 500;

  /// Maximum length of the location text (the database caps location /
  /// address fields at 500 characters).
  static const int maxLocationDetailsLength = 500;

  final DataBackend _db;
  final OfflineStorageService _offline;
  final ImagePicker _picker = ImagePicker();

  String? _hazardType;
  String? _severity;
  String? _locationDetails;
  String? _description;
  String? _ward;
  String? _lga;
  String? _state;
  DateTime _reportDateTime = DateTime.now();
  List<XFile> _photos = [];
  double? _latitude;
  double? _longitude;
  bool _locationIsApproximate = false;

  bool _isLoading = false;

  String? get hazardType => _hazardType;
  String? get severity => _severity;
  String? get locationDetails => _locationDetails;
  String? get description => _description;
  String? get ward => _ward;
  String? get lga => _lga;

  /// State chosen in the location picker. LGA names are not unique across
  /// states ('Obi'), so the state is never inferred from the LGA when the
  /// user picked one.
  String? get state => _state;
  DateTime get reportDateTime => _reportDateTime;
  List<XFile> get photos => _photos;
  bool get isLoading => _isLoading;
  double? get latitude => _latitude;
  double? get longitude => _longitude;

  /// True when the coordinates are not a GPS fix (e.g. the geocoded centre of
  /// the chosen state/LGA, or a point tapped on the map).
  bool get locationIsApproximate => _locationIsApproximate;

  void setHazardType(String type) {
    _hazardType = type;
    notifyListeners();
  }

  void setSeverity(String level) {
    _severity = normalizeSeverity(level) ?? level;
    notifyListeners();
  }

  void setLocationDetails(String details) {
    _locationDetails = details.length > maxLocationDetailsLength
        ? details.substring(0, maxLocationDetailsLength)
        : details;
    notifyListeners();
  }

  void setLocation(double lat, double lng, {bool approximate = false}) {
    _latitude = lat;
    _longitude = lng;
    _locationIsApproximate = approximate;
    notifyListeners();
  }

  /// Forget the coordinates (the report is then located by state/LGA/ward).
  void clearLocation() {
    _latitude = null;
    _longitude = null;
    _locationIsApproximate = false;
    notifyListeners();
  }

  void setDescription(String desc) {
    _description = desc;
    notifyListeners();
  }

  /// Sets the incident time; a time in the future is clamped to now.
  void setReportDateTime(DateTime dateTime) {
    final now = DateTime.now();
    _reportDateTime = dateTime.isAfter(now) ? now : dateTime;
    notifyListeners();
  }

  void setWard(String ward) {
    _ward = ward;
    notifyListeners();
  }

  void setLGA(String lga) {
    _lga = lga;
    notifyListeners();
  }

  void setReportState(String state) {
    _state = state;
    notifyListeners();
  }

  /// The report's state: the picked one, else inferred from an unambiguous
  /// LGA. Null when it cannot be determined.
  String? get resolvedState {
    final picked = _state?.trim();
    if (picked != null && picked.isNotEmpty) return picked;
    final lga = _lga;
    return lga == null ? null : MVPLocationsData.resolveStateForLGA(lga);
  }

  Future<void> pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1024,
      );
      if (image != null) {
        if (_photos.length >= 3) {
          throw ValidationException((l) => l.reportErrorMaxPhotos(3));
        }
        _photos.add(image);
        notifyListeners();
      }
    } on Exception catch (e) {
      developer.log('Error picking image: $e');
      rethrow;
    }
  }

  void removeImage(int index) {
    if (index >= 0 && index < _photos.length) {
      _photos.removeAt(index);
      notifyListeners();
    }
  }

  void reset() {
    _hazardType = null;
    _severity = null;
    _locationDetails = null;
    _description = null;
    _ward = null;
    _lga = null;
    _state = null;
    _reportDateTime = DateTime.now();
    _photos = [];
    _latitude = null;
    _longitude = null;
    _locationIsApproximate = false;
    notifyListeners();
  }

  /// Submit a report (with offline support). The result's `'message'` is a
  /// [LocalizedText].
  Future<Map<String, dynamic>> submitReport(BuildContext context) async {
    try {
      _isLoading = true;
      notifyListeners();

      if (_hazardType == null) {
        throw ValidationException((l) => l.reportErrorMissingHazard);
      }
      if (_severity == null || _severity == 'Unknown') {
        throw ValidationException((l) => l.reportErrorMissingSeverity);
      }
      if (_locationDetails == null) {
        throw ValidationException((l) => l.reportErrorMissingLocation);
      }
      if (_ward == null || _lga == null) {
        throw ValidationException((l) => l.pleaseSelectStateLgaWard);
      }
      final state = resolvedState;
      if (state == null) {
        throw ValidationException((l) => l.pleaseSelectStateLgaWard);
      }
      // GPS coordinates are optional (reports.latitude/longitude are
      // nullable): without a fix the report is located by state/LGA/ward
      // only and the UI labels the location as approximate/unknown.
      if (_latitude == null || _longitude == null) {
        _latitude = null;
        _longitude = null;
      }

      // Drafts and uploads are owner-tagged; an ownerless draft could never
      // be synced (or would be attributed to whoever signs in next).
      final uid = _db.currentUserId;
      if (uid == null) {
        throw AuthException((l) => l.reportErrorSignedOut);
      }

      final hasInternet = context.read<ConnectivityProvider>().isOnline;

      if (!hasInternet) {
        final draftId = await _offline.saveDraft(
          userId: uid,
          hazardType: _hazardType!,
          severity: _severity!,
          locationDetails: _locationDetails!,
          latitude: _latitude,
          longitude: _longitude,
          description: _description,
          reportDateTime: _reportDateTime,
          imagePaths: _photos.map((p) => p.path).toList(),
          ward: _ward,
          lga: _lga,
          state: state,
        );
        reset();
        _isLoading = false;
        notifyListeners();
        return {
          'success': true,
          'message': (AppLocalizations l) => l.reportSavedAsDraft,
          'draftId': draftId,
          'offline': true,
        };
      }

      final String docId = const Uuid().v4();

      // Upload images to the report-images bucket (path must start with the
      // user id — storage RLS).
      final List<String> imageUrls = [];
      final storagePaths = [
        for (int i = 0; i < _photos.length; i++)
          reportPhotoStoragePath(uid, docId, i, _photos[i].name),
      ];
      try {
        for (int i = 0; i < _photos.length; i++) {
          final url = await _db
              .uploadFileFromPath(
                bucketId: AppConfig.reportImagesBucket,
                storagePath: storagePaths[i],
                file: File(_photos[i].path),
              )
              .timeout(photoUploadTimeout);
          imageUrls.add(url);
          await _uploadThumbnail(File(_photos[i].path), storagePaths[i]);
        }
      } on Exception catch (e) {
        // The connection dropped while uploading photos: keep the report
        // with its local photos for offline sync (like an offline
        // submission). The draft keeps this report's id and storage paths,
        // so the sync reuses photos uploaded before the failure (no orphans)
        // and a retried sync never creates a second report.
        if (!isTransientNetworkError(e)) rethrow;
        developer.log('Photo upload failed, saved for sync: $e');
        await _offline.saveDraft(
          userId: uid,
          reportId: docId,
          hazardType: _hazardType!,
          severity: _severity!,
          locationDetails: _locationDetails!,
          latitude: _latitude,
          longitude: _longitude,
          description: _description,
          reportDateTime: _reportDateTime,
          imagePaths: _photos.map((p) => p.path).toList(),
          imageStoragePaths: storagePaths,
          ward: _ward,
          lga: _lga,
          state: state,
        );
        reset();
        _isLoading = false;
        notifyListeners();
        return {
          'success': false,
          'message': (AppLocalizations l) => l.reportQueuedServerUnreachable,
          'queued': true,
        };
      }

      final reportData = {
        'userId': uid,
        'hazardType': _hazardType,
        'severity': normalizeSeverity(_severity) ?? _severity,
        'latitude': _latitude,
        'longitude': _longitude,
        'locationDetails': _locationDetails,
        'location': _locationDetails,
        'address': _locationDetails,
        'ward': _ward,
        'lga': _lga,
        'state': state,
        'description': _description ?? '',
        // The incident time the user picked (not the upload time).
        'submittedAt': _reportDateTime.toUtc().toIso8601String(),
        'imageUrls': imageUrls,
        'status': 'pending',
      };

      try {
        developer.log('Checking network connectivity for submission...');
        final doc = await _db
            .createDocument(
              collectionId: AppConfig.reportsCollection,
              documentId: docId,
              data: reportData,
            )
            .timeout(const Duration(seconds: 10));
        final reportId = doc['\$id'] as String;
        // Peer verification requests and escalation scheduling are handled
        // by database triggers + the backend on insert.

        developer.log('Report submitted: $reportId');
        reset();
        _isLoading = false;
        notifyListeners();
        return {
          'success': true,
          'message': (AppLocalizations l) => l.reportSubmittedWithPeers,
          'reportId': reportId,
        };
      } on Exception catch (e) {
        // Only connectivity failures are queued; a refusal by the server
        // (RLS, constraint violation, bad value) would fail again on every
        // retry, so it is reported to the user instead.
        if (!isTransientNetworkError(e)) rethrow;
        await _offline.addToSyncQueue({...reportData, 'docId': docId});
        reset();
        _isLoading = false;
        notifyListeners();
        developer.log('Submission failed, queued for sync: $e');
        return {
          'success': false,
          'message': (AppLocalizations l) => l.reportQueuedServerUnreachable,
          'queued': true,
        };
      }
    } on Exception catch (e) {
      _isLoading = false;
      notifyListeners();
      developer.log('Error submitting report: $e');
      return {
        'success': false,
        // Rate-limit refusals carry a readable reason written by the
        // database (not translated); everything else is localised.
        'message': (AppLocalizations l) =>
            backendFailureOf(e) == BackendFailure.rateLimited
            ? (backendMessageOf(e) ??
                  ErrorHandler.handleError(e, l, context: 'Report Submission'))
            : ErrorHandler.handleError(e, l, context: 'Report Submission'),
      };
    }
  }

  Future<Map<String, dynamic>>? _syncInFlight;

  /// Called after a sync uploaded at least one report (from any entry
  /// point: reconnect, dashboard, offline screen), e.g. to refresh the
  /// report lists that do not include them yet.
  VoidCallback? onReportsSynced;

  /// Sync pending drafts and failed submissions to the backend.
  ///
  /// This is the single entry point for offline sync. Concurrent calls share
  /// the same in-flight run so items are never uploaded twice.
  Future<Map<String, dynamic>> syncPendingReports(BuildContext context) {
    return _syncInFlight ??= _doSyncPendingReports().whenComplete(() {
      _syncInFlight = null;
    });
  }

  Future<Map<String, dynamic>> _doSyncPendingReports() async {
    _isLoading = true;
    notifyListeners();
    int successCount = 0, failCount = 0;

    try {
      final offlineService = _offline;
      final uid = _db.currentUserId;
      if (uid == null) throw AuthException((l) => l.authErrorNotLoggedIn);

      // Process sync queue (failed submissions) — single implementation
      // lives in OfflineStorageService (keeps status 'pending', retries
      // failed items up to a cap).
      final queueResult = await offlineService.syncPendingReports();
      successCount += queueResult['synced'] ?? 0;
      failCount +=
          (queueResult['failed'] ?? 0) + (queueResult['rejected'] ?? 0);

      // Process drafts. Only the signed-in user's own drafts are uploaded:
      // drafts of another account and ownerless drafts of older builds wait
      // for their author / an explicit choice, and drafts refused
      // permanently by the server wait for the user to retry or discard.
      final drafts = offlineService.getAllDrafts().where(
        (d) => OfflineStorageService.isAutoSyncableDraft(d, uid),
      );
      for (final draft in drafts) {
        try {
          final draftId = draft['id'] as String;
          // A draft saved by an interrupted online submission keeps that
          // report's id. Other drafts have millisecond ids; derive a stable
          // UUID so a retried sync of the same draft never creates a
          // duplicate report.
          final savedReportId = draft['reportId'];
          final reportId = savedReportId is String && savedReportId.isNotEmpty
              ? savedReportId
              : const Uuid().v5(Namespace.url.value, 'draft:$uid:$draftId');
          final List<String> imageUrls = [];
          if (draft['imagePaths'] != null) {
            final paths = (draft['imagePaths'] as List).cast<String>();
            for (int i = 0; i < paths.length; i++) {
              final path = paths[i];
              if (File(path).existsSync()) {
                final fileName = path.split('/').last;
                final storagePath = draftPhotoStoragePath(
                  draft,
                  uid: uid,
                  reportId: reportId,
                  index: i,
                  fileName: fileName,
                );
                final url = await _db.uploadFileFromPath(
                  bucketId: AppConfig.reportImagesBucket,
                  storagePath: storagePath,
                  file: File(path),
                );
                imageUrls.add(url);
                await _uploadThumbnail(File(path), storagePath);
              }
            }
          }

          await _db.upsertDocument(
            collectionId: AppConfig.reportsCollection,
            documentId: reportId,
            ignoreDuplicates: true,
            data: {
              'userId': uid,
              'hazardType': draft['hazardType'],
              'severity':
                  normalizeSeverity(draft['severity']) ?? draft['severity'],
              'latitude': draft['latitude'],
              'longitude': draft['longitude'],
              'locationDetails': draft['locationDetails'] ?? '',
              'location': draft['locationDetails'] ?? '',
              'address': draft['locationDetails'] ?? '',
              'ward': draft['ward'] ?? '',
              'lga': draft['lga'] ?? '',
              'state':
                  draft['state'] ??
                  MVPLocationsData.resolveStateForLGA(
                    (draft['lga'] ?? '').toString(),
                  ) ??
                  '',
              'description': draft['description'] ?? '',
              'submittedAt':
                  (parseTimestamp(draft['reportDateTime']) ?? DateTime.now())
                      .toUtc()
                      .toIso8601String(),
              'imageUrls': imageUrls,
              'status': 'pending',
            },
          );
          await offlineService.deleteDraft(draft['id']);
          successCount++;
        } on Exception catch (e) {
          developer.log('Failed to sync draft ${draft['id']}: $e');
          if (isPermanentSyncError(e)) {
            await offlineService.updateDraft(draft['id'] as String, {
              'status': OfflineStorageService.statusRejected,
              'lastError': e.toString(),
            });
          }
          failCount++;
        }
      }

      _isLoading = false;
      notifyListeners();
      if (successCount > 0) {
        try {
          onReportsSynced?.call();
        } on Exception catch (e) {
          developer.log('onReportsSynced error: $e');
        }
      }
      return {
        'success': true,
        'synced': successCount,
        'failed': failCount,
        'message': (AppLocalizations l) =>
            l.syncResultSummary(successCount, failCount),
      };
    } on Exception catch (e) {
      _isLoading = false;
      notifyListeners();
      developer.log('Sync failed: $e');
      return {
        'success': false,
        'message': (AppLocalizations l) => ErrorHandler.getUserMessage(e, l),
      };
    }
  }
}
