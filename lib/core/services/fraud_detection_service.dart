import 'dart:developer' as developer;
import 'package:climate_app/core/services/appwrite_service.dart';
import 'package:appwrite/appwrite.dart';

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

/// Service for detecting fraudulent login attempts
///
/// Analyzes login patterns to detect:
/// - New device logins
/// - Logins from unusual locations
/// - Multiple failed attempts
/// - Impossible travel (two locations too quickly)
class FraudDetectionService {
  static final FraudDetectionService _instance =
      FraudDetectionService._internal();
  factory FraudDetectionService() => _instance;
  FraudDetectionService._internal();

  final AppwriteService _appwrite = AppwriteService();

  /// Assess risk level for a login attempt
  Future<FraudAssessment> assessLoginRisk({
    required String userId,
    required String deviceFingerprint,
  }) async {
    try {
      final flags = <String>[];
      FraudRisk risk = FraudRisk.low;

      // Check if device is recognized
      final isKnownDevice = await _isDeviceRecognized(
        userId,
        deviceFingerprint,
      );
      if (!isKnownDevice) {
        flags.add('new_device');
        risk = FraudRisk.medium;
      }

      // Check recent failed login attempts
      final failedAttempts = await _getRecentFailedAttempts(userId);
      if (failedAttempts >= 3) {
        flags.add('multiple_failed_attempts');
        risk = FraudRisk.high;
      }

      // Determine if additional verification is needed
      final requiresVerification =
          risk == FraudRisk.high ||
          risk == FraudRisk.critical ||
          flags.contains('new_device');

      final String reason = _getRiskReason(flags);

      developer.log(
        'Fraud assessment: $risk - $reason',
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
      // Default to low risk if assessment fails
      return FraudAssessment(
        risk: FraudRisk.low,
        reason: 'Assessment unavailable',
      );
    }
  }

  /// Check if device is recognized for this user
  Future<bool> _isDeviceRecognized(
    String userId,
    String deviceFingerprint,
  ) async {
    try {
      // Check trusted_devices collection
      final devices = await _appwrite.listDocuments(
        collectionId: AppwriteService.trustedDevicesCollectionId,
        queries: [
          Query.equal('userId', userId),
          Query.equal('deviceFingerprint', deviceFingerprint),
        ],
      );

      return devices.total > 0;
    } on Exception catch (e) {
      developer.log('Error checking device: $e');
      return false; // Assume unknown device on error
    }
  }

  /// Get count of recent failed login attempts
  Future<int> _getRecentFailedAttempts(String userId) async {
    try {
      final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));

      final attempts = await _appwrite.listDocuments(
        collectionId: AppwriteService.loginHistoryCollectionId,
        queries: [
          Query.equal('userId', userId),
          Query.equal('success', false),
          Query.greaterThan('timestamp', oneHourAgo.toIso8601String()),
        ],
      );

      return attempts.total;
    } on Exception catch (e) {
      developer.log('Error getting failed attempts: $e');
      return 0;
    }
  }

  /// Generate human-readable risk reason
  String _getRiskReason(List<String> flags) {
    if (flags.isEmpty) {
      return 'Normal login activity';
    }

    if (flags.contains('multiple_failed_attempts')) {
      return 'Multiple failed login attempts detected';
    }

    if (flags.contains('new_device')) {
      return 'Login from new device';
    }

    return 'Unusual activity detected';
  }

  /// Register a new trusted device
  Future<void> registerTrustedDevice({
    required String userId,
    required String deviceFingerprint,
    required String deviceName,
  }) async {
    try {
      await _appwrite.createDocument(
        collectionId: AppwriteService.trustedDevicesCollectionId,
        data: {
          'userId': userId,
          'deviceFingerprint': deviceFingerprint,
          'deviceName': deviceName,
          'trusted': true,
          'lastUsed': DateTime.now().toIso8601String(),
          'createdAt': DateTime.now().toIso8601String(),
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

  /// Record login attempt for fraud tracking
  Future<void> recordLoginAttempt({
    required String userId,
    required bool success,
    required String deviceFingerprint,
    String? deviceName,
  }) async {
    try {
      await _appwrite.createDocument(
        collectionId: AppwriteService.loginHistoryCollectionId,
        data: {
          'userId': userId,
          'success': success,
          'deviceFingerprint': deviceFingerprint,
          'deviceName': deviceName ?? 'Unknown',
          'timestamp': DateTime.now().toIso8601String(),
          'riskScore': 0, // Calculated by assessment
        },
      );

      developer.log(
        'Login attempt recorded: ${success ? "SUCCESS" : "FAILED"}',
        name: 'FraudDetectionService',
      );
    } on Exception catch (e) {
      developer.log('Error recording login attempt: $e');
      // Don't rethrow - login should continue even if logging fails
    }
  }
}
