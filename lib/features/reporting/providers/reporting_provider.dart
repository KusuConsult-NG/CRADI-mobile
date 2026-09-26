import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:climate_app/core/services/offline_storage_service.dart';
import 'package:climate_app/core/data/mvp_locations_data.dart';
import 'package:climate_app/core/providers/connectivity_provider.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'dart:developer' as developer;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

enum HazardType { flood, drought, temp, wind, erosion, fire, pest }

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
  ReportingProvider();

  final SupabaseService _db = SupabaseService();
  final ImagePicker _picker = ImagePicker();

  String? _hazardType;
  String? _severity;
  String? _locationDetails;
  String? _description;
  String? _ward;
  String? _lga;
  DateTime _reportDateTime = DateTime.now();
  List<XFile> _photos = [];
  double? _latitude;
  double? _longitude;

  bool _isLoading = false;

  String? get hazardType => _hazardType;
  String? get severity => _severity;
  String? get locationDetails => _locationDetails;
  String? get description => _description;
  String? get ward => _ward;
  String? get lga => _lga;
  DateTime get reportDateTime => _reportDateTime;
  List<XFile> get photos => _photos;
  bool get isLoading => _isLoading;
  double? get latitude => _latitude;
  double? get longitude => _longitude;

  void setHazardType(String type) {
    _hazardType = type;
    notifyListeners();
  }

  void setSeverity(String level) {
    _severity = normalizeSeverity(level) ?? level;
    notifyListeners();
  }

  void setLocationDetails(String details) {
    _locationDetails = details;
    notifyListeners();
  }

  void setLocation(double lat, double lng) {
    _latitude = lat;
    _longitude = lng;
    notifyListeners();
  }

  void setDescription(String desc) {
    _description = desc;
    notifyListeners();
  }

  void setReportDateTime(DateTime dateTime) {
    _reportDateTime = dateTime;
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

  Future<void> pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1024,
      );
      if (image != null) {
        if (_photos.length >= 3) throw Exception('Maximum 3 images allowed');
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
    _reportDateTime = DateTime.now();
    _photos = [];
    _latitude = null;
    _longitude = null;
    notifyListeners();
  }

  /// Submit a report (with offline support).
  Future<Map<String, dynamic>> submitReport(BuildContext context) async {
    try {
      _isLoading = true;
      notifyListeners();

      if (_hazardType == null) throw Exception('Hazard Type is missing');
      if (_severity == null || _severity == 'Unknown') {
        throw Exception('Severity Level is missing');
      }
      if (_locationDetails == null) {
        throw Exception('Location Details are missing');
      }
      if (_ward == null) throw Exception('Ward is missing');
      if (_lga == null) throw Exception('LGA is missing');
      if (_latitude == null || _longitude == null) {
        throw Exception(
          'GPS coordinates are missing. Please refresh location or enable GPS.',
        );
      }

      final hasInternet = context.read<ConnectivityProvider>().isOnline;

      if (!hasInternet) {
        final draftId = await OfflineStorageService().saveDraft(
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
        );
        reset();
        _isLoading = false;
        notifyListeners();
        return {
          'success': true,
          'message': '📴 Saved as draft. Will sync when online.',
          'draftId': draftId,
          'offline': true,
        };
      }

      final uid = _db.currentUserId;
      if (uid == null) {
        throw Exception('User must be logged in to submit a report');
      }

      final String docId = const Uuid().v4();

      // Upload images to the report-images bucket (path must start with the
      // user id — storage RLS).
      final List<String> imageUrls = [];
      for (int i = 0; i < _photos.length; i++) {
        final photo = _photos[i];
        final file = File(photo.path);
        final fileName = photo.name;
        final url = await _db.uploadFileFromPath(
          bucketId: AppConfig.reportImagesBucket,
          storagePath: '$uid/${docId}_${i}_$fileName',
          file: file,
        );
        imageUrls.add(url);
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
        'state': MVPLocationsData.getStateForLGA(_lga!),
        'description': _description ?? '',
        'submittedAt': DateTime.now().toUtc().toIso8601String(),
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
          'message':
              'Report submitted successfully! Verification requests sent to peers.',
          'reportId': reportId,
        };
      } on Exception catch (e) {
        // Submission failed or timed out — add to sync queue
        await OfflineStorageService().addToSyncQueue({
          ...reportData,
          'docId': docId,
        });
        reset();
        _isLoading = false;
        notifyListeners();
        developer.log('Submission failed, queued for sync: $e');
        return {
          'success': false,
          'message': 'Could not reach the server. Saved and will sync later.',
          'queued': true,
        };
      }
    } on Exception catch (e) {
      _isLoading = false;
      notifyListeners();
      developer.log('Error submitting report: $e');
      return {
        'success': false,
        'message': ErrorHandler.handleError(e, context: 'Report Submission'),
      };
    }
  }

  Future<Map<String, dynamic>>? _syncInFlight;

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
      final offlineService = OfflineStorageService();
      final uid = _db.currentUserId;
      if (uid == null) throw Exception('User not logged in');

      // Process sync queue (failed submissions) — single implementation
      // lives in OfflineStorageService (keeps status 'pending', retries
      // failed items up to a cap).
      final queueResult = await offlineService.syncPendingReports();
      successCount += queueResult['synced'] ?? 0;
      failCount += queueResult['failed'] ?? 0;

      // Process drafts
      final drafts = offlineService.getAllDrafts();
      for (final draft in drafts) {
        try {
          final draftId = draft['id'] as String;
          // Drafts have millisecond ids; derive a stable UUID so a retried
          // sync of the same draft never creates a duplicate report.
          final reportId = const Uuid().v5(
            Namespace.url.value,
            'draft:$uid:$draftId',
          );
          final List<String> imageUrls = [];
          if (draft['imagePaths'] != null) {
            final paths = (draft['imagePaths'] as List).cast<String>();
            for (int i = 0; i < paths.length; i++) {
              final path = paths[i];
              if (File(path).existsSync()) {
                final fileName = path.split('/').last;
                final url = await _db.uploadFileFromPath(
                  bucketId: AppConfig.reportImagesBucket,
                  storagePath: '$uid/${reportId}_${i}_$fileName',
                  file: File(path),
                );
                imageUrls.add(url);
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
              'ward': draft['ward'] ?? 'Unknown',
              'lga': draft['lga'] ?? 'Makurdi',
              'state': MVPLocationsData.getStateForLGA(
                (draft['lga'] ?? 'Makurdi').toString(),
              ),
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
          failCount++;
        }
      }

      _isLoading = false;
      notifyListeners();
      return {
        'success': true,
        'synced': successCount,
        'failed': failCount,
        'message': 'Synced $successCount items. $failCount failed.',
      };
    } on Exception catch (e) {
      _isLoading = false;
      notifyListeners();
      return {'success': false, 'message': 'Sync failed: $e'};
    }
  }
}
