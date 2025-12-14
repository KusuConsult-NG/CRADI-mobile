import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:climate_app/core/services/offline_queue_service.dart';
import 'package:climate_app/core/providers/connectivity_provider.dart';
import 'package:uuid/uuid.dart';
import 'dart:developer' as developer;

enum HazardType { flood, drought, temp, wind, erosion, fire, pest }

enum SeverityLevel { low, medium, high, critical }

class ReportingProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();
  final OfflineQueueService _offlineQueue = OfflineQueueService();
  final Uuid _uuid = const Uuid();

  ConnectivityProvider? _connectivityProvider;

  String? _hazardType;
  String? _severity;
  String? _locationDetails;
  String? _description;
  DateTime _reportDateTime = DateTime.now();
  List<XFile> _photos = [];

  bool _isLoading = false;

  String? get hazardType => _hazardType;
  String? get severity => _severity;
  String? get locationDetails => _locationDetails;
  String? get description => _description;
  DateTime get reportDateTime => _reportDateTime;
  List<XFile> get photos => _photos;
  bool get isLoading => _isLoading;

  /// Set connectivity provider reference (call from widget tree)
  void setConnectivityProvider(ConnectivityProvider provider) {
    _connectivityProvider = provider;
  }

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
        imageQuality: 70, // Resize/compress
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
    notifyListeners();
  }

  /// Submit report - automatically queues if offline, uploads if online
  Future<Map<String, dynamic>> submitReport() async {
    try {
      _isLoading = true;
      notifyListeners();

      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User must be logged in to submit a report');
      }

      if (_hazardType == null ||
          _severity == null ||
          _locationDetails == null) {
        throw Exception('Please fill all required fields');
      }

      // Generate unique ID for this report
      final reportId = _uuid.v4();

      // Prepare report data
      final reportData = {
        'id': reportId,
        'userId': user.uid,
        'hazardType': _hazardType,
        'severity': _severity,
        'locationDetails': _locationDetails,
        'description': _description ?? '',
        'reportDate': _reportDateTime.toIso8601String(),
        'submittedAt': DateTime.now().toIso8601String(),
        'photos': _photos.map((p) => p.path).toList(),
        'status': 'pending',
        'verificationCount': 0,
      };

      // Check connectivity
      final isOnline = _connectivityProvider?.isOnline ?? true;

      if (!isOnline) {
        // Queue for later sync
        await _offlineQueue.queueReport(reportData);

        developer.log('Report queued offline: $reportId');

        reset();
        _isLoading = false;
        notifyListeners();

        return {
          'success': true,
          'queued': true,
          'message': 'Report queued for sync when online',
        };
      }

      // Online: Upload immediately
      List<String> imageUrls = [];
      if (_photos.isNotEmpty) {
        for (int i = 0; i < _photos.length; i++) {
          final photo = _photos[i];
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final ext = photo.path.split('.').last;
          final path = 'report_images/${user.uid}/${timestamp}_$i.$ext';

          final ref = _storage.ref().child(path);
          final uploadTask = await ref.putFile(File(photo.path));

          if (uploadTask.state == TaskState.success) {
            final url = await ref.getDownloadURL();
            imageUrls.add(url);
          }
        }
      }

      // Create Firestore document
      final firestoreData = {
        'userId': user.uid,
        'hazardType': _hazardType,
        'severity': _severity,
        'locationDetails': _locationDetails,
        'description': _description ?? '',
        'reportDate': Timestamp.fromDate(_reportDateTime),
        'submittedAt': FieldValue.serverTimestamp(),
        'imageUrls': imageUrls,
        'status': 'pending',
        'verificationCount': 0,
      };

      await _firestore.collection('reports').doc(reportId).set(firestoreData);

      developer.log('Report submitted online: $reportId');

      reset();
      _isLoading = false;
      notifyListeners();

      return {
        'success': true,
        'queued': false,
        'message': 'Report submitted successfully',
      };
    } on Exception catch (e) {
      _isLoading = false;
      notifyListeners();
      developer.log('Error submitting report: $e');
      rethrow;
    }
  }
}
