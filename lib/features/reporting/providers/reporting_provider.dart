import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:climate_app/core/services/appwrite_service.dart';
import 'package:uuid/uuid.dart';
import 'dart:developer' as developer;
import 'package:appwrite/appwrite.dart';

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
  DateTime _reportDateTime = DateTime.now();
  List<XFile> _photos = [];
  double? _latitude;
  double? _longitude;

  bool _isLoading = false;

  String? get hazardType => _hazardType;
  String? get severity => _severity;
  String? get locationDetails => _locationDetails;
  String? get description => _description;
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

  /// Pick an image from gallery or camera
  Future<void> pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1024,
      );

      if (image != null) {
        if (_photos.length >= 5) {
          throw Exception('Maximum 5 images allowed');
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
    _reportDateTime = DateTime.now();
    _photos = [];
    _latitude = null;
    _longitude = null;
    notifyListeners();
  }

  /// Submit report using Appwrite
  Future<Map<String, dynamic>> submitReport() async {
    try {
      _isLoading = true;
      notifyListeners();

      final user = await _appwrite.getCurrentUser();
      if (user == null) {
        throw Exception('User must be logged in to submit a report');
      }

      if (_hazardType == null) {
        throw Exception('Hazard Type is missing');
      }
      if (_severity == null || _severity == 'Unknown') {
        throw Exception('Severity Level is missing');
      }
      if (_locationDetails == null) {
        throw Exception('Location Details are missing');
      }

      // Generate unique ID for this report
      final reportId = _uuid.v4();

      // Upload images to Appwrite Storage
      List<String> imageIds = [];
      if (_photos.isNotEmpty) {
        for (int i = 0; i < _photos.length; i++) {
          final photo = _photos[i];
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
        'description': _description ?? '',
        'submittedAt': DateTime.now().toIso8601String(),
        'imageIds': imageIds,
        'status': 'pending',
        'isAlert': _severity == 'critical' || _severity == 'high',
        'verificationCount': 0,
      };

      await _appwrite.createDocument(
        collectionId: AppwriteService.reportsCollectionId,
        documentId: reportId,
        data: reportData,
      );

      developer.log('Report submitted: $reportId');

      reset();
      _isLoading = false;
      notifyListeners();

      return {
        'success': true,
        'message': 'Report submitted successfully',
        'reportId': reportId,
      };
    } on AppwriteException catch (e) {
      _isLoading = false;
      notifyListeners();
      developer.log('Error submitting report: ${e.message}');
      rethrow;
    } on Exception catch (e) {
      _isLoading = false;
      notifyListeners();
      developer.log('Error submitting report: $e');
      rethrow;
    }
  }
}
