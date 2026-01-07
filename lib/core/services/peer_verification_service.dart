import 'package:climate_app/core/services/appwrite_service.dart';
import 'package:climate_app/core/services/notification_service.dart';
import 'package:appwrite/appwrite.dart';
import 'dart:developer' as developer;

/// Service for managing peer verification workflow
/// Handles verification requests, escalation, and notification
class PeerVerificationService {
  static final PeerVerificationService _instance =
      PeerVerificationService._internal();
  factory PeerVerificationService() => _instance;
  PeerVerificationService._internal();

  final AppwriteService _appwrite = AppwriteService();
  final NotificationService _notificationService = NotificationService();

  static const String verificationsCollectionId = 'verifications';
  static const Duration escalationTimeout = Duration(minutes: 30);
  static const int minimumConfirmations = 1;

  /// Submit a verification (confirm or dispute)
  Future<Map<String, dynamic>> submitVerification({
    required String reportId,
    required String userId,
    required bool isConfirmed,
    String? comment,
  }) async {
    try {
      // Create verification document
      final verificationId = DateTime.now().millisecondsSinceEpoch.toString();
      final verification = {
        'reportId': reportId,
        'userId': userId,
        'isConfirmed': isConfirmed,
        'comment': comment ?? '',
        'submittedAt': DateTime.now().toIso8601String(),
      };

      await _appwrite.createDocument(
        collectionId: verificationsCollectionId,
        documentId: verificationId,
        data: verification,
      );

      developer.log(
        'Verification submitted: $verificationId (confirmed: $isConfirmed)',
        name: 'PeerVerificationService',
      );

      // Check if report should be validated
      await _checkAndValidateReport(reportId);

      return {
        'success': true,
        'verificationId': verificationId,
        'message': isConfirmed
            ? 'Report confirmed successfully'
            : 'Report disputed',
      };
    } on AppwriteException catch (e) {
      developer.log(
        'Error submitting verification: ${e.message}',
        name: 'PeerVerificationService',
      );
      rethrow;
    }
  }

  /// Check if report has enough confirmations and validate if needed
  Future<void> _checkAndValidateReport(String reportId) async {
    try {
      // Get all verifications for this report
      final verifications = await _appwrite.listDocuments(
        collectionId: verificationsCollectionId,
        queries: [Query.equal('reportId', reportId)],
      );

      final confirmations = verifications.documents
          .where((v) => v.data['isConfirmed'] == true)
          .length;
      final disputes = verifications.documents
          .where((v) => v.data['isConfirmed'] == false)
          .length;

      developer.log(
        'Report $reportId: $confirmations confirmations, $disputes disputes',
        name: 'PeerVerificationService',
      );

      // If minimum confirmations met, validate the report
      if (confirmations >= minimumConfirmations) {
        await _validateReport(reportId, isAutoValidated: true);
      }

      // If there are disputes, escalate to coordinators
      if (disputes > 0) {
        await escalateToCoordinator(
          reportId: reportId,
          reason: 'Conflicting verifications',
        );
      }
    } on Exception catch (e) {
      developer.log(
        'Error checking report validation: $e',
        name: 'PeerVerificationService',
      );
    }
  }

  /// Validate a report
  Future<void> _validateReport(
    String reportId, {
    required bool isAutoValidated,
  }) async {
    try {
      // Update report status to validated
      await _appwrite.updateDocument(
        collectionId: AppwriteService.reportsCollectionId,
        documentId: reportId,
        data: {
          'status': 'validated',
          'validatedAt': DateTime.now().toIso8601String(),
          'autoValidated': isAutoValidated,
        },
      );

      developer.log(
        'Report validated: $reportId (auto: $isAutoValidated)',
        name: 'PeerVerificationService',
      );

      // Trigger alert distribution
      await _triggerAlert(reportId);

      // Notify original reporter
      await _notifyReporter(reportId, status: 'validated');
    } on Exception catch (e) {
      developer.log(
        'Error validating report: $e',
        name: 'PeerVerificationService',
      );
    }
  }

  /// Send verification requests to peers in the same ward
  Future<void> sendVerificationRequests({
    required String reportId,
    required String ward,
    required String lga,
    required String reporterId,
  }) async {
    try {
      // Get all EWMs in the same ward (excluding reporter)
      final peers = await _appwrite.listDocuments(
        collectionId: 'users',
        queries: [
          Query.equal('ward', ward),
          Query.equal('lga', lga),
          Query.equal('role', 'EWM'),
          Query.notEqual('\$id', reporterId),
        ],
      );

      if (peers.documents.isEmpty) {
        developer.log(
          'No peers found in $ward, $lga. Escalating to coordinator.',
          name: 'PeerVerificationService',
        );

        // No peers available, escalate immediately
        await escalateToCoordinator(
          reportId: reportId,
          reason: 'Single EWM in ward - no peers to verify',
        );
        return;
      }

      // Send push notifications to peers
      for (final peer in peers.documents) {
        final fcmToken = peer.data['fcmToken'] as String?;
        if (fcmToken != null && fcmToken.isNotEmpty) {
          // Simulation: Visualize the notification that would be sent
          _notificationService.showLocalNotification(
            title: 'Verification Request (Simulation)',
            body: 'Request sent to ${peer.data['name'] ?? 'User'}',
          );

          developer.log(
            'Would send verification request to user ${peer.$id}',
            name: 'PeerVerificationService',
          );
        }
      }

      developer.log(
        'Verification requests sent to ${peers.documents.length} peers',
        name: 'PeerVerificationService',
      );

      // Schedule escalation if no verification after 30 minutes
      await _scheduleEscalation(reportId);
    } on Exception catch (e) {
      developer.log(
        'Error sending verification requests: $e',
        name: 'PeerVerificationService',
      );
    }
  }

  /// Schedule automatic escalation after 30 minutes
  Future<void> _scheduleEscalation(String reportId) async {
    try {
      // Store escalation timer in database
      final escalationTime = DateTime.now()
          .add(escalationTimeout)
          .toIso8601String();

      await _appwrite.updateDocument(
        collectionId: AppwriteService.reportsCollectionId,
        documentId: reportId,
        data: {
          'escalationScheduledAt': escalationTime,
          'escalationStatus': 'pending',
        },
      );

      developer.log(
        'Escalation scheduled for $reportId at $escalationTime',
        name: 'PeerVerificationService',
      );

      // NOTE: Actual timer would be handled by a cloud function or background service
      // For MVP, this can be checked periodically or on app launch
    } on Exception catch (e) {
      developer.log(
        'Error scheduling escalation: $e',
        name: 'PeerVerificationService',
      );
    }
  }

  /// Escalate report to coordinators
  Future<void> escalateToCoordinator({
    required String reportId,
    required String reason,
  }) async {
    try {
      // Update report status
      await _appwrite.updateDocument(
        collectionId: AppwriteService.reportsCollectionId,
        documentId: reportId,
        data: {
          'status': 'escalated',
          'escalatedAt': DateTime.now().toIso8601String(),
          'escalationReason': reason,
        },
      );

      // Get report details to find LGA
      final report = await _appwrite.getDocument(
        collectionId: AppwriteService.reportsCollectionId,
        documentId: reportId,
      );

      final lga = report.data['lga'] as String? ?? '';

      // Get coordinators for this LGA
      final coordinators = await _appwrite.listDocuments(
        collectionId: 'users',
        queries: [
          Query.equal('role', 'LDP Coordinator'),
          if (lga.isNotEmpty) Query.equal('lga', lga),
        ],
      );

      // Get project staff (they see all escalations)
      final staff = await _appwrite.listDocuments(
        collectionId: 'users',
        queries: [Query.equal('role', 'Project Staff')],
      );

      // Send notifications to coordinators and staff
      final recipients = [...coordinators.documents, ...staff.documents];

      for (final recipient in recipients) {
        final fcmToken = recipient.data['fcmToken'] as String?;
        if (fcmToken != null && fcmToken.isNotEmpty) {
          // Simulation
          _notificationService.showLocalNotification(
            title: 'Escalation Notification (Simulation)',
            body: 'Report escalated to ${recipient.data['name']}',
          );

          developer.log(
            'Would send escalation notification to ${recipient.$id}',
            name: 'PeerVerificationService',
          );
        }
      }

      developer.log(
        'Report escalated: $reportId. Notified ${recipients.length} coordinators/staff',
        name: 'PeerVerificationService',
      );
    } on Exception catch (e) {
      developer.log(
        'Error escalating report: $e',
        name: 'PeerVerificationService',
      );
    }
  }

  /// Manual validation by coordinator/staff
  Future<Map<String, dynamic>> manualValidation({
    required String reportId,
    required String validatorId,
    required bool isApproved,
    required String reason,
  }) async {
    try {
      if (isApproved) {
        await _validateReport(reportId, isAutoValidated: false);

        // Log manual validation
        await _appwrite.createDocument(
          collectionId: 'verification_overrides',
          data: {
            'reportId': reportId,
            'validatorId': validatorId,
            'action': 'approved',
            'reason': reason,
            'timestamp': DateTime.now().toIso8601String(),
          },
        );

        return {'success': true, 'message': 'Report approved and validated'};
      } else {
        // Reject report
        await _appwrite.updateDocument(
          collectionId: AppwriteService.reportsCollectionId,
          documentId: reportId,
          data: {
            'status': 'rejected',
            'rejectedAt': DateTime.now().toIso8601String(),
            'rejectionReason': reason,
          },
        );

        // Log rejection
        await _appwrite.createDocument(
          collectionId: 'verification_overrides',
          data: {
            'reportId': reportId,
            'validatorId': validatorId,
            'action': 'rejected',
            'reason': reason,
            'timestamp': DateTime.now().toIso8601String(),
          },
        );

        // Notify reporter
        await _notifyReporter(reportId, status: 'rejected', reason: reason);

        return {'success': true, 'message': 'Report rejected'};
      }
    } on Exception catch (e) {
      developer.log(
        'Error in manual validation: $e',
        name: 'PeerVerificationService',
      );
      rethrow;
    }
  }

  /// Trigger alert distribution after validation
  Future<void> _triggerAlert(String reportId) async {
    try {
      // Get report details
      final report = await _appwrite.getDocument(
        collectionId: AppwriteService.reportsCollectionId,
        documentId: reportId,
      );

      final lga = report.data['lga'] as String? ?? '';
      // Note: severity and hazardType will be used when implementing alert templates

      // Get all EWMs in the LGA
      final ewms = await _appwrite.listDocuments(
        collectionId: 'users',
        queries: [
          Query.equal('role', 'EWM'),
          if (lga.isNotEmpty) Query.equal('lga', lga),
        ],
      );

      // Get authorities for the LGA
      final authorities = await _appwrite.listDocuments(
        collectionId: 'authorities',
        queries: [if (lga.isNotEmpty) Query.equal('coverageLGA', lga)],
      );

      // Send alerts to all recipients
      final recipients = [...ewms.documents, ...authorities.documents];

      developer.log(
        'Alert triggered for report $reportId: ${recipients.length} recipients',
        name: 'PeerVerificationService',
      );

      // TODO: Actual alert sending would be done via Cloud Function
      // - Send push notifications to EWMs
      // - Send SMS to authorities
      // - Send SMS to coordinators

      _notificationService.showLocalNotification(
        title: 'Alert Triggered (Simulation)',
        body: 'Alert sent to ${recipients.length} recipients',
      );
    } on Exception catch (e) {
      developer.log(
        'Error triggering alert: $e',
        name: 'PeerVerificationService',
      );
    }
  }

  /// Notify original reporter of verification status
  Future<void> _notifyReporter(
    String reportId, {
    required String status,
    String? reason,
  }) async {
    try {
      final report = await _appwrite.getDocument(
        collectionId: AppwriteService.reportsCollectionId,
        documentId: reportId,
      );

      final reporterId = report.data['userId'] as String? ?? '';

      // Get reporter's FCM token
      final reporter = await _appwrite.getDocument(
        collectionId: 'users',
        documentId: reporterId,
      );

      final fcmToken = reporter.data['fcmToken'] as String?;

      if (fcmToken != null && fcmToken.isNotEmpty) {
        // Simulation
        _notificationService.showLocalNotification(
          title: 'Report Status Update (Simulation)',
          body: 'Reporter notified: $status',
        );

        developer.log(
          'Would notify reporter $reporterId: status=$status',
          name: 'PeerVerificationService',
        );
      }
    } on Exception catch (e) {
      developer.log(
        'Error notifying reporter: $e',
        name: 'PeerVerificationService',
      );
    }
  }

  /// Get verification statistics for a report
  Future<Map<String, dynamic>> getVerificationStats(String reportId) async {
    try {
      final verifications = await _appwrite.listDocuments(
        collectionId: verificationsCollectionId,
        queries: [Query.equal('reportId', reportId)],
      );

      final confirmations = verifications.documents
          .where((v) => v.data['isConfirmed'] == true)
          .length;
      final disputes = verifications.documents
          .where((v) => v.data['isConfirmed'] == false)
          .length;

      return {
        'totalVerifications': verifications.documents.length,
        'confirmations': confirmations,
        'disputes': disputes,
        'requiresEscalation': disputes > 0 && confirmations == 0,
        'canValidate': confirmations >= minimumConfirmations,
      };
    } on Exception catch (e) {
      developer.log(
        'Error getting verification stats: $e',
        name: 'PeerVerificationService',
      );
      return {
        'totalVerifications': 0,
        'confirmations': 0,
        'disputes': 0,
        'requiresEscalation': false,
        'canValidate': false,
      };
    }
  }
}
