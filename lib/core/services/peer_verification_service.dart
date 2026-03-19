import 'package:climate_app/core/services/firebase_service.dart';
import 'package:climate_app/core/services/notification_service.dart';
import 'package:climate_app/core/services/sms_service.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/core/services/remote_config_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:developer' as developer;
import 'dart:math' as math;

/// Service for managing peer verification workflow.
/// Handles verification requests, escalation, and notification.
/// Now backed by Firestore. Key fixes from audit:
///   - minimumConfirmations raised to AppConfig.minimumPeerConfirmations (2)
///   - No hard 25-document limit (Firestore has no default cap)
///   - Firestore auto-IDs replace millisecond timestamp IDs
class PeerVerificationService {
  static final PeerVerificationService _instance =
      PeerVerificationService._internal();
  factory PeerVerificationService() => _instance;
  PeerVerificationService._internal();

  final FirebaseService _firebase = FirebaseService();
  final NotificationService _notificationService = NotificationService();

  static const Duration escalationTimeout = Duration(minutes: 30);

  /// Submit a verification (confirm or dispute)
  Future<Map<String, dynamic>> submitVerification({
    required String reportId,
    required String userId,
    required bool isConfirmed,
    String? comment,
    double? userLatitude,
    double? userLongitude,
  }) async {
    try {
      // ── Guard 1: Self-verification ─────────────────────────────────
      final reportDoc = await _firebase.getDocument(
        collectionId: AppConfig.reportsCollection,
        documentId: reportId,
      );
      final reporterId =
          reportDoc['userId'] as String? ??
          reportDoc['reporterId'] as String? ??
          '';
      if (reporterId == userId) {
        return {
          'success': false,
          'message': 'You cannot verify your own report.',
        };
      }

      // ── Guard 2: Location proximity (2 km) ────────────────────────
      if (userLatitude != null && userLongitude != null) {
        final rLat = (reportDoc['latitude'] as num?)?.toDouble();
        final rLng = (reportDoc['longitude'] as num?)?.toDouble();
        if (rLat != null && rLng != null) {
          final dist = _haversineKm(userLatitude, userLongitude, rLat, rLng);
          if (dist > 2.0) {
            return {
              'success': false,
              'message':
                  'You must be within 2 km of the report location to verify. '
                  'Current distance: ${dist.toStringAsFixed(1)} km.',
            };
          }
        }
      }

      // Firestore auto-generates a safe document ID
      final result = await _firebase.createDocument(
        collectionId: AppConfig.verificationsCollection,
        data: {
          'reportId': reportId,
          'userId': userId,
          'isConfirmed': isConfirmed,
          'comment': comment ?? '',
          'submittedAt': FieldValue.serverTimestamp(),
        },
      );

      developer.log(
        'Verification submitted: ${result['\$id']} (confirmed: $isConfirmed)',
        name: 'PeerVerificationService',
      );

      await _checkAndValidateReport(reportId);

      return {
        'success': true,
        'verificationId': result['\$id'],
        'message': isConfirmed
            ? 'Report confirmed successfully'
            : 'Report disputed',
      };
    } on FirebaseException catch (e) {
      developer.log(
        'Error submitting verification: ${e.message}',
        name: 'PeerVerificationService',
      );
      rethrow;
    }
  }

  /// Check if report has enough confirmations and validate if needed.
  Future<void> _checkAndValidateReport(String reportId) async {
    try {
      final verifications = await _firebase.listDocuments(
        collectionId: AppConfig.verificationsCollection,
        queries: [FQuery.equal('reportId', reportId)],
        limitCount: 200, // A report won't have more than 200 verifications
      );

      final confirmations = verifications
          .where((v) => v['isConfirmed'] == true)
          .length;
      final disputes = verifications
          .where((v) => v['isConfirmed'] == false)
          .length;

      developer.log(
        'Report $reportId: $confirmations confirmations, $disputes disputes',
        name: 'PeerVerificationService',
      );

      // Update verification count on report
      await _firebase.updateDocument(
        collectionId: AppConfig.reportsCollection,
        documentId: reportId,
        data: {'verificationCount': verifications.length},
      );

      // Validate only if minimum confirmations reached (configurable via Firebase Remote Config)
      if (confirmations >= RemoteConfigService().minimumPeerConfirmations) {
        await _validateReport(reportId, isAutoValidated: true);
      }

      // Escalate if there are disputes
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

  /// Mark a report as verified once peer threshold is reached.
  Future<void> _validateReport(
    String reportId, {
    required bool isAutoValidated,
  }) async {
    try {
      await _firebase.updateDocument(
        collectionId: AppConfig.reportsCollection,
        documentId: reportId,
        data: {
          'status': 'verified',
          'verifiedAt': FieldValue.serverTimestamp(),
          'autoValidated': isAutoValidated,
        },
      );

      developer.log(
        'Report verified: $reportId (auto: $isAutoValidated)',
        name: 'PeerVerificationService',
      );

      await _triggerAlert(reportId);
      await _notifyReporter(reportId, status: 'verified');
    } on Exception catch (e) {
      developer.log(
        'Error validating report: $e',
        name: 'PeerVerificationService',
      );
    }
  }

  /// Send verification requests to peers in the same ward.
  Future<void> sendVerificationRequests({
    required String reportId,
    required String ward,
    required String lga,
    required String reporterId,
  }) async {
    try {
      final peers = await _firebase.listDocuments(
        collectionId: AppConfig.usersCollection,
        queries: [
          FQuery.equal('ward', ward),
          FQuery.equal('lga', lga),
          FQuery.equal('role', 'ewm'),
          FQuery.notEqual('\$id', reporterId),
        ],
        limitCount: 50, // Notify up to 50 ward peers
      );

      if (peers.isEmpty) {
        developer.log(
          'No peers found in $ward, $lga. Escalating to coordinator.',
          name: 'PeerVerificationService',
        );
        await escalateToCoordinator(
          reportId: reportId,
          reason: 'Single EWM in ward – no peers to verify',
        );
        return;
      }

      // Collect FCM tokens from peers and call the server-side FCM function.
      final peerTokens = peers
          .map((p) => p['fcmToken'] as String?)
          .where((t) => t != null && t.isNotEmpty)
          .cast<String>()
          .toList();

      if (peerTokens.isNotEmpty) {
        try {
          await FirebaseFunctions.instance
              .httpsCallable('sendVerificationRequest')
              .call({
                'reportId': reportId,
                'ward': ward,
                'lga': lga,
                'reporterId': reporterId,
                'peerTokens': peerTokens,
              });
          developer.log(
            'FCM verification request sent to ${peerTokens.length} peers via Cloud Function',
            name: 'PeerVerificationService',
          );
        } on FirebaseFunctionsException catch (e) {
          developer.log(
            'Cloud Function call failed: ${e.code} — ${e.message}. Falling back.',
            name: 'PeerVerificationService',
          );
          // Fallback: local notification to submitting device only
          _notificationService.showLocalNotification(
            title: 'Verification Requested',
            body: 'Notified ${peerTokens.length} peer(s) in $ward',
          );
        }
      }

      developer.log(
        'Verification requests dispatched to ${peers.length} peers',
        name: 'PeerVerificationService',
      );

      await _scheduleEscalation(reportId);
    } on Exception catch (e) {
      developer.log(
        'Error sending verification requests: $e',
        name: 'PeerVerificationService',
      );
    }
  }

  /// Write an escalation schedule entry to Firestore.
  /// A Cloud Function trigger on `scheduled_escalations` fires the actual escalation.
  Future<void> _scheduleEscalation(String reportId) async {
    try {
      final escalationTime = DateTime.now().add(escalationTimeout);

      await _firebase.updateDocument(
        collectionId: AppConfig.reportsCollection,
        documentId: reportId,
        data: {
          'escalationScheduledAt': escalationTime.toIso8601String(),
          'escalationStatus': 'pending',
        },
      );

      // Write to dedicated collection for Cloud Function trigger
      await _firebase.createDocument(
        collectionId: AppConfig.scheduledEscalationsCollection,
        data: {
          'reportId': reportId,
          'escalateAt': Timestamp.fromDate(escalationTime),
          'status': 'pending',
        },
      );

      developer.log(
        'Escalation scheduled for $reportId at $escalationTime',
        name: 'PeerVerificationService',
      );
    } on Exception catch (e) {
      developer.log(
        'Error scheduling escalation: $e',
        name: 'PeerVerificationService',
      );
    }
  }

  /// Escalate report to coordinators.
  Future<void> escalateToCoordinator({
    required String reportId,
    required String reason,
  }) async {
    try {
      await _firebase.updateDocument(
        collectionId: AppConfig.reportsCollection,
        documentId: reportId,
        data: {
          'escalated': true,
          'escalatedAt': FieldValue.serverTimestamp(),
          'escalationReason': reason,
        },
      );

      final report = await _firebase.getDocument(
        collectionId: AppConfig.reportsCollection,
        documentId: reportId,
      );
      final lga = report['lga'] as String? ?? '';

      final coordinators = await _firebase.listDocuments(
        collectionId: AppConfig.usersCollection,
        queries: [
          FQuery.equal('role', 'ldp_coordinator'),
          if (lga.isNotEmpty) FQuery.equal('lga', lga),
        ],
        limitCount: 20, // Reasonable coordinator limit per LGA
      );

      final staff = await _firebase.listDocuments(
        collectionId: AppConfig.usersCollection,
        queries: [FQuery.equal('role', 'project_staff')],
        limitCount: 20, // Reasonable project staff limit
      );

      final recipients = [...coordinators, ...staff];

      final recipientTokens = recipients
          .map((r) => r['fcmToken'] as String?)
          .where((t) => t != null && t.isNotEmpty)
          .cast<String>()
          .toList();

      if (recipientTokens.isNotEmpty) {
        try {
          await FirebaseFunctions.instance
              .httpsCallable('sendEscalationNotification')
              .call({
                'reportId': reportId,
                'reason': reason,
                'recipientTokens': recipientTokens,
              });
          developer.log(
            'Escalation FCM sent to ${recipientTokens.length} coordinators/staff via Cloud Function',
            name: 'PeerVerificationService',
          );
        } on FirebaseFunctionsException catch (e) {
          developer.log(
            'Escalation Cloud Function failed: ${e.code} — ${e.message}.',
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

  /// Manual validation by coordinator/staff.
  Future<Map<String, dynamic>> manualValidation({
    required String reportId,
    required String validatorId,
    required bool isApproved,
    required String reason,
  }) async {
    try {
      if (isApproved) {
        // Admin approval writes 'approved' status directly
        await _firebase.updateDocument(
          collectionId: AppConfig.reportsCollection,
          documentId: reportId,
          data: {
            'status': 'approved',
            'approvedAt': FieldValue.serverTimestamp(),
          },
        );
        await _triggerAlert(reportId);
        await _notifyReporter(reportId, status: 'approved');
        await _firebase.createDocument(
          collectionId: AppConfig.verificationsOverrideCollection,
          data: {
            'reportId': reportId,
            'validatorId': validatorId,
            'action': 'approved',
            'reason': reason,
            'timestamp': FieldValue.serverTimestamp(),
          },
        );
        return {'success': true, 'message': 'Report approved'};
      } else {
        await _firebase.updateDocument(
          collectionId: AppConfig.reportsCollection,
          documentId: reportId,
          data: {
            'status': 'rejected',
            'rejectedAt': FieldValue.serverTimestamp(),
            'rejectionReason': reason,
          },
        );
        await _firebase.createDocument(
          collectionId: AppConfig.verificationsOverrideCollection,
          data: {
            'reportId': reportId,
            'validatorId': validatorId,
            'action': 'rejected',
            'reason': reason,
            'timestamp': FieldValue.serverTimestamp(),
          },
        );
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

  /// Trigger alert distribution after validation.
  Future<void> _triggerAlert(String reportId) async {
    try {
      final report = await _firebase.getDocument(
        collectionId: AppConfig.reportsCollection,
        documentId: reportId,
      );

      final lga = report['lga'] as String? ?? '';

      final ewms = await _firebase.listDocuments(
        collectionId: AppConfig.usersCollection,
        queries: [
          FQuery.equal('role', 'ewm'),
          if (lga.isNotEmpty) FQuery.equal('lga', lga),
        ],
        limitCount: 200, // Alert all EWMs in LGA — up to 200
      );

      final authorities = await _firebase.listDocuments(
        collectionId: AppConfig.authoritiesCollection,
        queries: [if (lga.isNotEmpty) FQuery.equal('coverageLGA', lga)],
        limitCount: 50, // Alert all authorities in LGA — up to 50
      );

      final recipients = [...ewms, ...authorities];

      developer.log(
        'Alert triggered for report $reportId: ${recipients.length} recipients',
        name: 'PeerVerificationService',
      );

      // SMS to authorities (real path — uses Africa's Talking)
      final authorityContacts = authorities
          .map((doc) => doc['phone'] as String?)
          .where((phone) => phone != null && phone.isNotEmpty)
          .cast<String>()
          .toList();

      if (authorityContacts.isNotEmpty) {
        final sentCount = await SmsService().sendAlertToAuthorities(
          alertTitle: report['hazardType'] ?? 'Hazard',
          location: '$lga (Ward: ${report['ward']})',
          severity: report['severity'] ?? 'HIGH',
          authorityContacts: authorityContacts,
        );
        developer.log(
          'SMS Alerts sent to $sentCount/${authorityContacts.length} authorities',
          name: 'PeerVerificationService',
        );
      }

      _notificationService.showLocalNotification(
        title: 'Alert Triggered',
        body: 'Alert sent to ${recipients.length} recipients',
      );
    } on Exception catch (e) {
      developer.log(
        'Error triggering alert: $e',
        name: 'PeerVerificationService',
      );
    }
  }

  /// Notify original reporter of verification status.
  Future<void> _notifyReporter(
    String reportId, {
    required String status,
    String? reason,
  }) async {
    try {
      final report = await _firebase.getDocument(
        collectionId: AppConfig.reportsCollection,
        documentId: reportId,
      );
      final reporterId = report['userId'] as String? ?? '';
      if (reporterId.isEmpty) return;

      final reporter = await _firebase.getDocument(
        collectionId: AppConfig.usersCollection,
        documentId: reporterId,
      );
      final fcmToken = reporter['fcmToken'] as String?;

      if (fcmToken != null && fcmToken.isNotEmpty) {
        try {
          await FirebaseFunctions.instance
              .httpsCallable('sendReporterStatusUpdate')
              .call({
                'reporterToken': fcmToken,
                'reportId': reportId,
                'status': status,
                ...?reason != null ? {'reason': reason} : null,
              });
          developer.log(
            'Reporter $reporterId status update sent via Cloud Function: $status',
            name: 'PeerVerificationService',
          );
        } on FirebaseFunctionsException catch (e) {
          developer.log(
            'Reporter notification Cloud Function failed: ${e.code}',
            name: 'PeerVerificationService',
          );
          // Fallback: local notification
          _notificationService.showLocalNotification(
            title: 'Report Status Update',
            body: 'Your report is now: $status',
          );
        }
      }
    } on Exception catch (e) {
      developer.log(
        'Error notifying reporter: $e',
        name: 'PeerVerificationService',
      );
    }
  }

  /// Get verification statistics for a report.
  Future<Map<String, dynamic>> getVerificationStats(String reportId) async {
    try {
      final verifications = await _firebase.listDocuments(
        collectionId: AppConfig.verificationsCollection,
        queries: [FQuery.equal('reportId', reportId)],
        limitCount: 200,
      );

      final confirmations = verifications
          .where((v) => v['isConfirmed'] == true)
          .length;
      final disputes = verifications
          .where((v) => v['isConfirmed'] == false)
          .length;

      return {
        'totalVerifications': verifications.length,
        'confirmations': confirmations,
        'disputes': disputes,
        'requiresEscalation': disputes > 0 && confirmations == 0,
        'canValidate': confirmations >= AppConfig.minimumPeerConfirmations,
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

  /// Lazy escalation: Check for pending reports older than 30 minutes.
  Future<void> checkAndEscalatePendingReports() async {
    try {
      final reports = await _firebase.listDocuments(
        collectionId: AppConfig.reportsCollection,
        queries: [FQuery.equal('status', 'pending')],
        limitCount:
            100, // Process at most 100 pending reports per scheduled check
      );

      final now = DateTime.now();
      int escalatedCount = 0;

      for (final doc in reports) {
        final submittedAtStr = doc['submittedAt'];
        if (submittedAtStr == null) continue;

        DateTime? submittedAt;
        if (submittedAtStr is Timestamp) {
          submittedAt = submittedAtStr.toDate();
        } else if (submittedAtStr is String) {
          submittedAt = DateTime.tryParse(submittedAtStr);
        }
        if (submittedAt == null) continue;

        if (now.difference(submittedAt) > escalationTimeout) {
          await escalateToCoordinator(
            reportId: doc['\$id'] as String,
            reason: 'Auto-escalation: No verification within 30 minutes',
          );
          escalatedCount++;
        }
      }

      if (escalatedCount > 0) {
        developer.log(
          'Lazy Escalation: Escalated $escalatedCount reports.',
          name: 'PeerVerificationService',
        );
      }
    } on Exception catch (e) {
      developer.log(
        'Error in checkAndEscalatePendingReports: $e',
        name: 'PeerVerificationService',
      );
    }
  }

  /// Haversine distance in kilometres.
  static double _haversineKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const R = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLng = _deg2rad(lng2 - lng1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  static double _deg2rad(double deg) => deg * (math.pi / 180);
}
