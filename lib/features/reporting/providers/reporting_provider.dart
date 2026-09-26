import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:climate_app/core/services/offline_storage_service.dart';
import 'package:climate_app/core/services/peer_verification_service.dart';
import 'package:climate_app/core/data/mvp_locations_data.dart';
import 'package:climate_app/core/providers/connectivity_provider.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'dart:developer' as developer;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

enum HazardType { flood, drought, temp, wind, erosion, fire, pest }

enum SeverityLevel { low, medium, high, critical }

class ReportingProvider extends ChangeNotifier {
  ReportingProvider();

  final SupabaseService _supabase = SupabaseService();
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

  /// Submit report using Supabase (with offline support).
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

      // Get current Supabase user
      final supabaseUser = Supabase.instance.client.auth.currentUser;
      if (supabaseUser == null) {
        throw Exception('User must be logged in to submit a report');
      }

      final String docId = const Uuid().v4();

      // Upload images to Supabase Storage
      final List<String> imageUrls = [];
      for (int i = 0; i < _photos.length; i++) {
        final photo = _photos[i];
        final file = File(photo.path);
        final fileName = photo.name;
        final url = await _supabase.uploadFileFromPath(
          storagePath:
              '${AppConfig.reportImagesBucket}/${supabaseUser.id}/${docId}_${i}_$fileName',
          file: file,
        );
        imageUrls.add(url);
      }

      final reportData = {
        'id': docId,
        'user_id': supabaseUser.id,
        'hazard_type': _hazardType,
        'severity': _severity,
        'latitude': _latitude,
        'longitude': _longitude,
        'location_description': _locationDetails,
        'ward': _ward,
        'lga': _lga,
        'state': MVPLocationsData.getStateForLGA(_lga!),
        'description': _description ?? '',
        'submitted_at': DateTime.now().toUtc().toIso8601String(),
        'image_urls': imageUrls,
        'status': 'pending',
        'verification_count': 0,
      };

      try {
        developer.log('Submitting report to Supabase...');
        final doc = await _supabase
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
            reporterId: supabaseUser.id,
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
      return {
        'success': false,
        'message': ErrorHandler.handleError(e, context: 'Report Submission'),
      };
    }
  }

  /// Sync pending drafts and failed submissions to Supabase.
  Future<Map<String, dynamic>> syncPendingReports(BuildContext context) async {
    _isLoading = true;
    notifyListeners();
    int successCount = 0, failCount = 0;

    try {
      final offlineService = OfflineStorageService();
      final supabaseUser = Supabase.instance.client.auth.currentUser;
      if (supabaseUser == null) throw Exception('User not logged in');

      // Process sync queue (failed submissions)
      final queue = offlineService.getSyncQueue();
      for (final item in queue) {
        if (item['status'] == 'synced') continue;
        try {
          final docId = item['docId'] as String?;
          await _supabase.createDocument(
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
                final url = await _supabase.uploadFileFromPath(
                  storagePath:
                      '${AppConfig.reportImagesBucket}/${supabaseUser.id}/${draftId}_${i}_$fileName',
                  file: File(path),
                );
                imageUrls.add(url);
              }
            }
          }

          await _supabase.createDocument(
            collectionId: AppConfig.reportsCollection,
            documentId: draftId,
            data: {
              'id': draftId,
              'user_id': supabaseUser.id,
              'hazard_type': draft['hazardType'],
              'severity': draft['severity'],
              'latitude': draft['latitude'],
              'longitude': draft['longitude'],
              'location_description': draft['locationDetails'],
              'ward': draft['ward'] ?? 'Unknown',
              'lga': draft['lga'] ?? 'Makurdi',
              'state': MVPLocationsData.getStateForLGA(
                (draft['lga'] ?? 'Makurdi').toString(),
              ),
              'description': draft['description'],
              'submitted_at': DateTime.now().toUtc().toIso8601String(),
              'image_urls': imageUrls,
              'status': 'pending',
              'verification_count': 0,
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
