import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:climate_app/core/services/appwrite_service.dart';
import 'package:climate_app/core/services/offline_storage_service.dart';
import 'package:climate_app/core/services/peer_verification_service.dart';
import 'package:climate_app/core/data/mvp_locations_data.dart';
import 'package:climate_app/core/providers/connectivity_provider.dart';
import 'package:uuid/uuid.dart';
import 'dart:developer' as developer;
import 'package:appwrite/appwrite.dart';
import 'package:provider/provider.dart';

enum HazardType { flood, drought, temp, wind, erosion, fire, pest }

enum SeverityLevel { low, medium, high, critical }

class ReportingProvider extends ChangeNotifier {
  ReportingProvider();

  final AppwriteService _appwrite = AppwriteService();
  final ImagePicker _picker = ImagePicker();
  final Uuid _uuid = const Uuid();

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

  /// Pick an image from gallery or camera
  Future<void> pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1024,
      );

      if (image != null) {
        if (_photos.length >= 3) {
          throw Exception('Maximum 3 images allowed');
        }
        _photos.add(image);
        notifyListeners();
      }
    } on Exception catch (e) {
      developer.log('Error picking image: $e');
      rethrow;
    }
  }

  /// Remove selected image
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

  /// Submit report using Appwrite (with offline support)
  Future<Map<String, dynamic>> submitReport(BuildContext context) async {
    try {
      _isLoading = true;
      notifyListeners();

      // Validation (no async operations here)
      if (_hazardType == null) {
        throw Exception('Hazard Type is missing');
      }
      if (_severity == null || _severity == 'Unknown') {
        throw Exception('Severity Level is missing');
      }
      if (_locationDetails == null) {
        throw Exception('Location Details are missing');
      }
      if (_ward == null) {
        throw Exception('Ward is missing');
      }
      if (_lga == null) {
        throw Exception('LGA is missing');
      }

      // Check connectivity FIRST (synchronous, no async gap)
      final hasInternet = context.read<ConnectivityProvider>().isOnline;

      if (!hasInternet) {
        // OFFLINE MODE - SAVE AS DRAFT (no user needed for drafts)
        final draftId = await OfflineStorageService().saveDraft(
          hazardType: _hazardType!,
          severity: _severity!,
          locationDetails: _locationDetails!,
          latitude: _latitude,
          longitude: _longitude,
          description: _description,
          reportDateTime: _reportDateTime,
          imagePaths: _photos.map((p) => p.path).toList(),
        );

        reset();
        _isLoading = false;
        notifyListeners();

        return {
          'success': true,
          'message': ' 📴 Saved as draft. Will sync when online.',
          'draftId': draftId,
          'offline': true,
        };
      }

      // ONLINE MODE - Get user and proceed with submission
      final user = await _appwrite.getCurrentUser();
      if (user == null) {
        throw Exception('User must be logged in to submit a report');
      }

      // Generate unique ID for this report
      final reportId = _uuid.v4();

      // Upload images to Appwrite Storage
      List<String> imageIds = [];
      if (_photos.isNotEmpty) {
        for (final photo in _photos) {
          final fileBytes = await File(photo.path).readAsBytes();
          final uploadedFile = await _appwrite.uploadFile(
            bucketId: AppwriteService.reportImagesBucketId,
            filePath: photo.path,
            fileBytes: fileBytes,
          );
          imageIds.add(uploadedFile.$id);
        }
      }

      // Create report document in Appwrite Database
      final reportData = {
        'userId': user.$id,
        'hazardType': _hazardType,
        'severity': _severity,
        'latitude': _latitude ?? 0.0,
        'longitude': _longitude ?? 0.0,
        'locationDetails': _locationDetails,
        'ward': _ward,
        'lga': _lga,
        'state': MVPLocationsData.getStateForLGA(_lga!),
        'description': _description ?? '',
        'submittedAt': DateTime.now().toIso8601String(),
        'imageIds': imageIds,
        'status': 'pending',
        'isAlert': _severity == 'critical' || _severity == 'high',
        'verificationCount': 0,
      };

      try {
        await _appwrite.createDocument(
          collectionId: AppwriteService.reportsCollectionId,
          documentId: reportId,
          data: reportData,
        );

        // ✨ SEND VERIFICATION REQUESTS TO PEERS ✨
        await PeerVerificationService().sendVerificationRequests(
          reportId: reportId,
          ward: _ward!,
          lga: _lga!,
          reporterId: user.$id,
        );

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
      } on AppwriteException {
        // Submission failed - ADD TO SYNC QUEUE
        await OfflineStorageService().addToSyncQueue(reportData);

        reset();
        _isLoading = false;
        notifyListeners();

        return {
          'success': false,
          'message':
              '⚠️ Submission failed. Added to sync queue. Will retry automatically.',
          'queued': true,
        };
      }
    } on Exception catch (e) {
      _isLoading = false;
      notifyListeners();
      developer.log('Error submitting report: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Sync pending reports (drafts and queue)
  Future<Map<String, dynamic>> syncPendingReports(BuildContext context) async {
    _isLoading = true;
    notifyListeners();

    int successCount = 0;
    int failCount = 0;

    try {
      final offlineService = OfflineStorageService();

      // 1. Process Sync Queue (Failed submissions)
      final queue = offlineService.getSyncQueue();
      for (final item in queue) {
        if (item['status'] == 'synced') continue;

        try {
          // Retry submission
          await _appwrite.createDocument(
            collectionId: AppwriteService.reportsCollectionId,
            documentId:
                item['queueId'], // Use original ID or queue ID? queue item has report data
            data:
                {
                    ...item,
                    'status': 'pending', // Reset status
                  }
                  ..remove('queueId')
                  ..remove('addedToQueueAt')
                  ..remove('retryCount')
                  ..remove('lastError'), // Remove queue metadata
          );

          await offlineService.markAsSynced(item['queueId']);
          successCount++;
        } on Exception catch (e) {
          await offlineService.markAsFailed(item['queueId'], e.toString());
          failCount++;
        }
      }

      // 2. Process Drafts (Saved offline)
      // Note: For now, we only sync drafts that have all required fields.
      // In a real app, we might want user confirmation for each.
      final drafts = offlineService.getAllDrafts();
      for (final draft in drafts) {
        try {
          // Sign in check
          final user = await _appwrite.getCurrentUser();
          if (user == null) throw Exception('User not logged in');

          // Upload images if paths exist
          List<String> imageIds = [];
          if (draft['imagePaths'] != null) {
            final paths = (draft['imagePaths'] as List).cast<String>();
            for (final path in paths) {
              if (File(path).existsSync()) {
                final fileBytes = await File(path).readAsBytes();
                final uploadedFile = await _appwrite.uploadFile(
                  bucketId: AppwriteService.reportImagesBucketId,
                  filePath: path,
                  fileBytes: fileBytes,
                );
                imageIds.add(uploadedFile.$id);
              }
            }
          }

          final reportId = _uuid.v4();
          final reportData = {
            'userId': user.$id,
            'hazardType': draft['hazardType'],
            'severity': draft['severity'],
            'latitude': draft['latitude'],
            'longitude': draft['longitude'],
            'locationDetails': draft['locationDetails'],
            'ward':
                MVPLocationsData.getWardsForLGA(
                  MVPLocationsData.getLGAForWard(draft['locationDetails']!) ??
                      'Makurdi',
                ).firstOrNull ??
                'Unknown', // Simplification for draft
            'lga':
                MVPLocationsData.getLGAForWard(draft['locationDetails']!) ??
                'Makurdi',
            'state': 'Benue', // Default/Derived
            'description': draft['description'],
            'submittedAt': DateTime.now().toIso8601String(),
            'imageIds': imageIds,
            'status': 'pending',
            'isAlert':
                draft['severity'] == 'critical' || draft['severity'] == 'high',
            'verificationCount': 0,
          };

          await _appwrite.createDocument(
            collectionId: AppwriteService.reportsCollectionId,
            documentId: reportId,
            data: reportData,
          );

          // Delete draft after success
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
