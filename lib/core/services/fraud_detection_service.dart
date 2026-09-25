import 'dart:developer' as developer;
import 'package:climate_app/core/services/firebase_service.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Risk levels for fraud detection
enum FraudRisk { low, medium, high, critical }

/// Fraud detection result
class FraudAssessment {
  final FraudRisk risk;
  final String reason;
  final List<String> flags;
  final bool requiresVerification;

  FraudAssessment({
    required this.risk,
    required this.reason,
    this.flags = const [],
    this.requiresVerification = false,
  });
}

/// Service for detecting fraudulent login attempts.
///
/// Analyzes login patterns to detect new devices, failed attempts, etc.
/// Now backed by Firestore instead of Appwrite.
class FraudDetectionService {
  static final FraudDetectionService _instance =
      FraudDetectionService._internal();
  factory FraudDetectionService() => _instance;
  FraudDetectionService._internal();

  final FirebaseService _firebase = FirebaseService();

  Future<FraudAssessment> assessLoginRisk({
    required String userId,
    required String deviceFingerprint,
  }) async {
    try {
      final flags = <String>[];
      FraudRisk risk = FraudRisk.low;

      final isKnownDevice = await _isDeviceRecognized(
        userId,
        deviceFingerprint,
      );
      if (!isKnownDevice) {
        flags.add('new_device');
        risk = FraudRisk.medium;
      }

      final failedAttempts = await _getRecentFailedAttempts(userId);
      if (failedAttempts >= 3) {
        flags.add('multiple_failed_attempts');
        risk = FraudRisk.high;
      }

      final requiresVerification =
          risk == FraudRisk.high ||
          risk == FraudRisk.critical ||
          flags.contains('new_device');

      final reason = _getRiskReason(flags);
      developer.log(
        'Fraud assessment: $risk – $reason',
        name: 'FraudDetectionService',
      );

      return FraudAssessment(
        risk: risk,
        reason: reason,
        flags: flags,
        requiresVerification: requiresVerification,
      );
    } on Exception catch (e) {
      developer.log(
        'Error assessing fraud risk: $e',
        name: 'FraudDetectionService',
      );
      return FraudAssessment(
        risk: FraudRisk.low,
        reason: 'Assessment unavailable',
      );
    }
  }

  Future<bool> _isDeviceRecognized(
    String userId,
    String deviceFingerprint,
  ) async {
    try {
      final devices = await _firebase.listDocuments(
        collectionId: AppConfig.trustedDevicesCollection,
        queries: [
          FQuery.equal('userId', userId),
          FQuery.equal('deviceFingerprint', deviceFingerprint),
        ],
      );
      return devices.isNotEmpty;
    } on Exception catch (e) {
      developer.log('Error checking device: $e');
      return false;
    }
  }

  Future<int> _getRecentFailedAttempts(String userId) async {
    try {
      final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
      final attempts = await _firebase.listDocuments(
        collectionId: AppConfig.loginHistoryCollection,
        queries: [
          FQuery.equal('userId', userId),
          FQuery.equal('success', false),
          // `timestamp` is written as a server Timestamp, so compare against
          // a Timestamp (an ISO string never matches a Timestamp field).
          FQuery.greaterThan('timestamp', Timestamp.fromDate(oneHourAgo)),
        ],
      );
      return attempts.length;
    } on Exception catch (e) {
      developer.log('Error getting failed attempts: $e');
      return 0;
    }
  }

  String _getRiskReason(List<String> flags) {
    if (flags.isEmpty) return 'Normal login activity';
    if (flags.contains('multiple_failed_attempts')) {
      return 'Multiple failed login attempts detected';
    }
    if (flags.contains('new_device')) return 'Login from new device';
    return 'Unusual activity detected';
  }

  Future<void> registerTrustedDevice({
    required String userId,
    required String deviceFingerprint,
    required String deviceName,
  }) async {
    try {
      await _firebase.createDocument(
        collectionId: AppConfig.trustedDevicesCollection,
        data: {
          'userId': userId,
          'deviceFingerprint': deviceFingerprint,
          'deviceName': deviceName,
          'trusted': true,
          'lastUsed': FieldValue.serverTimestamp(),
        },
      );
      developer.log(
        'Trusted device registered for user: $userId',
        name: 'FraudDetectionService',
      );
    } on Exception catch (e) {
      developer.log('Error registering trusted device: $e');
      rethrow;
    }
  }

  Future<void> recordLoginAttempt({
    required String userId,
    required bool success,
    required String deviceFingerprint,
    String? deviceName,
  }) async {
    try {
      await _firebase.createDocument(
        collectionId: AppConfig.loginHistoryCollection,
        data: {
          'userId': userId,
          'success': success,
          'deviceFingerprint': deviceFingerprint,
          'deviceName': deviceName ?? 'Unknown',
          'timestamp': FieldValue.serverTimestamp(),
          'riskScore': 0,
        },
      );
      developer.log(
        'Login attempt recorded: ${success ? "SUCCESS" : "FAILED"}',
        name: 'FraudDetectionService',
      );
    } on Exception catch (e) {
      developer.log('Error recording login attempt: $e');
      // Non-critical — don't rethrow
    }
  }
}
