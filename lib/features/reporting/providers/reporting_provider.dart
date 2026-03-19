import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:climate_app/core/services/firebase_service.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:climate_app/core/services/offline_storage_service.dart';
import 'package:climate_app/core/services/peer_verification_service.dart';
import 'package:climate_app/core/data/mvp_locations_data.dart';
import 'package:climate_app/core/providers/connectivity_provider.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:developer' as developer;
import 'package:provider/provider.dart';
import 'package:climate_app/core/utils/string_extensions.dart';
import 'package:uuid/uuid.dart';

enum HazardType { flood, drought, temp, wind, erosion, fire, pest }

enum SeverityLevel { low, medium, high, critical }

class ReportingProvider extends ChangeNotifier {
  ReportingProvider();

  final FirebaseService _firebase = FirebaseService();
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
    _severity = level;
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

  /// Submit report using Firestore (with offline support).
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

      // Get current Firebase user
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser == null) {
        throw Exception('User must be logged in to submit a report');
      }

      final String docId = const Uuid().v4();

      // Upload images to Firebase Storage
      final List<String> imageUrls = [];
      for (int i = 0; i < _photos.length; i++) {
        final photo = _photos[i];
        final file = File(photo.path);
        final fileName = photo.name;
        final url = await _firebase.uploadFileFromPath(
          storagePath:
              '${AppConfig.reportImagesBucket}/${firebaseUser.uid}/${docId}_${i}_$fileName',
          file: file,
        );
        imageUrls.add(url);
      }

      final reportData = {
        'userId': firebaseUser.uid,
        'hazardType': _hazardType,
        'severity': _severity,
        'latitude': _latitude,
        'longitude': _longitude,
        'locationDetails': _locationDetails,
        'location': _locationDetails,
        'address': _locationDetails,
        'ward': _ward,
        'lga': _lga,
        'state': MVPLocationsData.getStateForLGA(_lga!),
        'description': _description ?? '',
        'submittedAt': DateTime.now().toIso8601String(),
        'imageUrls': imageUrls,
        'status': 'pending',
        'isAlert': _severity == 'critical' || _severity == 'high',
        'verificationCount': 0,
      };

      try {
        developer.log('Checking network connectivity for submission...');
        final doc = await _firebase
            .createDocument(
              collectionId: AppConfig.reportsCollection,
              documentId: docId,
              data: reportData,
            )
            .timeout(const Duration(seconds: 10));
        final reportId = doc['\$id'] as String;

        // Send peer verification requests
        try {
          await PeerVerificationService().sendVerificationRequests(
            reportId: reportId,
            ward: _ward!,
            lga: _lga!,
            reporterId: firebaseUser.uid,
          );
        } on Exception catch (e) {
          developer.log(
            'Warning: Verification requests failed: $e',
            name: 'ReportingProvider',
          );
        }

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
        return {
          'success': false,
          'message':
              '⚠️ Submission failed: ${e.toString()}. Added to sync queue.',
          'queued': true,
        };
      }
    } on Exception catch (e) {
      _isLoading = false;
      notifyListeners();
      developer.log('Error submitting report: $e');
      return {'success': false, 'message': ErrorHandler.handleError(e, context: 'Report Submission')};
    }
  }

  /// Sync pending drafts and failed submissions to Firestore.
  Future<Map<String, dynamic>> syncPendingReports(BuildContext context) async {
    _isLoading = true;
    notifyListeners();
    int successCount = 0, failCount = 0;

    try {
      final offlineService = OfflineStorageService();
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser == null) throw Exception('User not logged in');

      // Process sync queue (failed submissions)
      final queue = offlineService.getSyncQueue();
      for (final item in queue) {
        if (item['status'] == 'synced') continue;
        try {
          final docId = item['docId'] as String?;
          await _firebase.createDocument(
            collectionId: AppConfig.reportsCollection,
            documentId: docId,
            data: {...item, 'status': 'pending'}
              ..remove('docId')
              ..remove('queueId')
              ..remove('addedToQueueAt')
              ..remove('retryCount')
              ..remove('lastError'),
          );
          await offlineService.markAsSynced(item['queueId']);
          successCount++;
        } on Exception catch (e) {
          await offlineService.markAsFailed(item['queueId'], e.toString());
          failCount++;
        }
      }

      // Process drafts
      final drafts = offlineService.getAllDrafts();
      for (final draft in drafts) {
        try {
          final draftId = draft['id'] as String;
          final List<String> imageUrls = [];
          if (draft['imagePaths'] != null) {
            final paths = (draft['imagePaths'] as List).cast<String>();
            for (int i = 0; i < paths.length; i++) {
              final path = paths[i];
              if (File(path).existsSync()) {
                final fileName = path.split('/').last;
                final url = await _firebase.uploadFileFromPath(
                  storagePath:
                      '${AppConfig.reportImagesBucket}/${firebaseUser.uid}/${draftId}_${i}_$fileName',
                  file: File(path),
                );
                imageUrls.add(url);
              }
            }
          }

          await _firebase.createDocument(
            collectionId: AppConfig.reportsCollection,
            documentId: draftId,
            data: {
              'userId': firebaseUser.uid,
              'hazardType': draft['hazardType'],
              'severity': draft['severity'],
              'latitude': draft['latitude'],
              'longitude': draft['longitude'],
              'locationDetails': draft['locationDetails'],
              'ward': (draft['ward'] ?? 'Unknown')
                  .toString()
                  .normalizeForBackend(),
              'lga': (draft['lga'] ?? 'Makurdi')
                  .toString()
                  .normalizeForBackend(),
              'state': MVPLocationsData.getStateForLGA(
                (draft['lga'] ?? 'Makurdi').toString(),
              ).normalizeForBackend(),
              'description': draft['description'],
              'submittedAt': DateTime.now().toIso8601String(),
              'imageUrls': imageUrls,
              'status': 'pending',
              'isAlert':
                  draft['severity'] == 'critical' ||
                  draft['severity'] == 'high',
              'verificationCount': 0,
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
