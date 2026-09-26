import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/core/services/notification_service.dart';
import 'package:climate_app/core/services/sms_service.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/core/services/remote_config_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;

/// Service for managing peer verification workflow.
/// Handles verification requests, escalation, and notification.
/// Backed by Supabase. Push notifications via OneSignal REST API.
class PeerVerificationService {
  static final PeerVerificationService _instance =
      PeerVerificationService._internal();
  factory PeerVerificationService() => _instance;
  PeerVerificationService._internal();

  final SupabaseService _supabase = SupabaseService();
  final NotificationService _notificationService = NotificationService();

  static const Duration escalationTimeout = Duration(minutes: 30);

  /// OneSignal REST API base URL
  static const String _osBaseUrl = 'https://onesignal.com/api/v1';

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
      final reportDoc = await _supabase.getDocument(
        collectionId: AppConfig.reportsCollection,
        documentId: reportId,
      );
      final reporterId =
          reportDoc['user_id'] as String? ??
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

      // Supabase auto-generates a UUID for the primary key
      final result = await _supabase.createDocument(
        collectionId: AppConfig.verificationsCollection,
        data: {
          'report_id': reportId,
          'verifier_id': userId,
          'is_confirmed': isConfirmed,
          'comments': comment ?? '',
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
    } on Exception catch (e) {
      developer.log(
        'Error submitting verification: $e',
        name: 'PeerVerificationService',
      );
      rethrow;
    }
  }

  /// Check if report has enough confirmations and validate if needed.
  Future<void> _checkAndValidateReport(String reportId) async {
    try {
      final verifications = await _supabase.listDocuments(
        collectionId: AppConfig.verificationsCollection,
        queries: [SQuery.equal('report_id', reportId)],
        limitCount: 200,
      );

      final confirmations = verifications
          .where((v) => v['is_confirmed'] == true)
          .length;
      final disputes = verifications
          .where((v) => v['is_confirmed'] == false)
          .length;

      developer.log(
        'Report $reportId: $confirmations confirmations, $disputes disputes',
        name: 'PeerVerificationService',
      );

      // Update verification count on report
      await _supabase.updateDocument(
        collectionId: AppConfig.reportsCollection,
        documentId: reportId,
        data: {'verification_count': verifications.length},
      );

      // Validate only if minimum confirmations reached
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
      await _supabase.updateDocument(
        collectionId: AppConfig.reportsCollection,
        documentId: reportId,
        data: {
          'status': 'verified',
          'validated_at': DateTime.now().toUtc().toIso8601String(),
          'auto_validated': isAutoValidated,
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

  /// Send verification requests to peers in the same ward via OneSignal filters.
  Future<void> sendVerificationRequests({
    required String reportId,
    required String ward,
    required String lga,
    required String reporterId,
  }) async {
    try {
      // Find EWM peers in the same ward (excluding the reporter)
      final peers = await _supabase.listDocuments(
        collectionId: AppConfig.usersCollection,
        queries: [
          SQuery.equal('ward', ward.toLowerCase()),
          SQuery.equal('lga', lga.toLowerCase()),
          SQuery.equal('role', 'ewm'),
          SQuery.notEqual('id', reporterId),
        ],
        limitCount: 50,
      );

      if (peers.isNotEmpty) {
        // Use OneSignal to send targeted push to peers in this ward
        await _sendOneSignalPush(
          heading: 'Verification Needed',
          content: 'A new hazard report needs your verification in $ward.',
          filters: [
            {'field': 'tag', 'key': 'ward', 'relation': '=', 'value': ward.toLowerCase()},
            {'operator': 'AND'},
            {'field': 'tag', 'key': 'lga', 'relation': '=', 'value': lga.toLowerCase()},
            {'operator': 'AND'},
            {'field': 'tag', 'key': 'role', 'relation': '=', 'value': 'ewm'},
          ],
          data: {
            'type': 'verification',
            'reportId': reportId,
            'ward': ward,
            'lga': lga,
          },
        );

        developer.log(
          'OneSignal verification push sent to EWMs in $ward/$lga',
          name: 'PeerVerificationService',
        );
      }

      await _scheduleEscalation(reportId);
    } on Exception catch (e) {
      developer.log(
        'Error sending verification requests: $e',
        name: 'PeerVerificationService',
      );
    }
  }

  /// Write an escalation schedule entry to Supabase.
  Future<void> _scheduleEscalation(String reportId) async {
    try {
      final escalationTime = DateTime.now().add(escalationTimeout);

      await _supabase.updateDocument(
        collectionId: AppConfig.reportsCollection,
        documentId: reportId,
        data: {
          'escalation_scheduled_at': escalationTime.toUtc().toIso8601String(),
          'escalation_status': 'pending',
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
      await _supabase.updateDocument(
        collectionId: AppConfig.reportsCollection,
        documentId: reportId,
        data: {
          'escalated': true,
          'escalated_at': DateTime.now().toUtc().toIso8601String(),
          'escalation_reason': reason,
        },
      );

      final report = await _supabase.getDocument(
        collectionId: AppConfig.reportsCollection,
        documentId: reportId,
      );
      final lga = report['lga'] as String? ?? '';

      // Notify coordinators and project staff via OneSignal
      await _sendOneSignalPush(
        heading: 'Report Escalated',
        content: 'Report in $lga needs coordinator review. Reason: $reason',
        filters: [
          {'field': 'tag', 'key': 'role', 'relation': '=', 'value': 'ldp_coordinator'},
          {'operator': 'OR'},
          {'field': 'tag', 'key': 'role', 'relation': '=', 'value': 'project_staff'},
        ],
        data: {
          'type': 'report',
          'reportId': reportId,
          'reason': reason,
        },
      );

      developer.log(
        'Report escalated: $reportId. OneSignal push sent to coordinators/staff.',
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
        await _supabase.updateDocument(
          collectionId: AppConfig.reportsCollection,
          documentId: reportId,
          data: {
            'status': 'approved',
            'approved_at': DateTime.now().toUtc().toIso8601String(),
          },
        );
        await _triggerAlert(reportId);
        await _notifyReporter(reportId, status: 'approved');
        await _supabase.createDocument(
          collectionId: AppConfig.verificationsOverrideCollection,
          data: {
            'report_id': reportId,
            'validator_id': validatorId,
            'action': 'approved',
            'reason': reason,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          },
        );
        return {'success': true, 'message': 'Report approved'};
      } else {
        await _supabase.updateDocument(
          collectionId: AppConfig.reportsCollection,
          documentId: reportId,
          data: {
            'status': 'rejected',
            'rejected_at': DateTime.now().toUtc().toIso8601String(),
            'rejection_reason': reason,
          },
        );
        await _supabase.createDocument(
          collectionId: AppConfig.verificationsOverrideCollection,
          data: {
            'report_id': reportId,
            'validator_id': validatorId,
            'action': 'rejected',
            'reason': reason,
            'created_at': DateTime.now().toUtc().toIso8601String(),
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

  /// Trigger alert distribution after validation via OneSignal geo-tags.
  Future<void> _triggerAlert(String reportId) async {
    try {
      final report = await _supabase.getDocument(
        collectionId: AppConfig.reportsCollection,
        documentId: reportId,
      );

      final lga = report['lga'] as String? ?? '';
      final ward = report['ward'] as String? ?? '';
      final hazardType = report['hazard_type'] ?? 'Hazard';
      final severity = report['severity'] ?? 'HIGH';

      // Send OneSignal push to all users tagged with this LGA
      await _sendOneSignalPush(
        heading: '⚠️ Alert: $hazardType',
        content:
            'Verified $hazardType alert in $ward, $lga. Severity: $severity.',
        filters: [
          {'field': 'tag', 'key': 'lga', 'relation': '=', 'value': lga.toLowerCase()},
        ],
        data: {
          'type': 'alert',
          'reportId': reportId,
          'lga': lga,
          'ward': ward,
        },
      );

      developer.log(
        'Alert OneSignal push sent for report $reportId to LGA: $lga',
        name: 'PeerVerificationService',
      );

      // SMS to authorities via Africa's Talking
      final authorities = await _supabase.listDocuments(
        collectionId: AppConfig.authoritiesCollection,
        queries: [if (lga.isNotEmpty) SQuery.equal('coverage_lga', lga)],
        limitCount: 50,
      );

      final authorityContacts = authorities
          .map((doc) => doc['phone'] as String?)
          .where((phone) => phone != null && phone.isNotEmpty)
          .cast<String>()
          .toList();

      if (authorityContacts.isNotEmpty) {
        final sentCount = await SmsService().sendAlertToAuthorities(
          alertTitle: hazardType,
          location: '$lga (Ward: $ward)',
          severity: severity,
          authorityContacts: authorityContacts,
        );
        developer.log(
          'SMS Alerts sent to $sentCount/${authorityContacts.length} authorities',
          name: 'PeerVerificationService',
        );
      }

      _notificationService.showLocalNotification(
        title: 'Alert Triggered',
        body: 'Alert sent for $hazardType in $lga',
      );
    } on Exception catch (e) {
      developer.log(
        'Error triggering alert: $e',
        name: 'PeerVerificationService',
      );
    }
  }

  /// Notify original reporter of verification status via OneSignal external user ID.
  Future<void> _notifyReporter(
    String reportId, {
    required String status,
    String? reason,
  }) async {
    try {
      final report = await _supabase.getDocument(
        collectionId: AppConfig.reportsCollection,
        documentId: reportId,
      );
      final reporterId = report['user_id'] as String? ?? '';
      if (reporterId.isEmpty) return;

      final statusMessages = {
        'verified': 'Your report has been verified by peers.',
        'approved': 'Your report has been approved by a coordinator.',
        'rejected': reason != null
            ? 'Your report was not approved. Reason: $reason'
            : 'Your report was not approved.',
      };

      await _sendOneSignalPushToUser(
        externalUserId: reporterId,
        heading: 'Report Status Update',
        content: statusMessages[status] ?? 'Your report status: $status',
        data: {
          'type': 'report',
          'reportId': reportId,
          'status': status,
        },
      );

      developer.log(
        'Reporter $reporterId status update sent via OneSignal: $status',
        name: 'PeerVerificationService',
      );
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
      final verifications = await _supabase.listDocuments(
        collectionId: AppConfig.verificationsCollection,
        queries: [SQuery.equal('report_id', reportId)],
        limitCount: 200,
      );

      final confirmations = verifications
          .where((v) => v['is_confirmed'] == true)
          .length;
      final disputes = verifications
          .where((v) => v['is_confirmed'] == false)
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
      final reports = await _supabase.listDocuments(
        collectionId: AppConfig.reportsCollection,
        queries: [SQuery.equal('status', 'pending')],
        limitCount: 100,
      );

      final now = DateTime.now();
      int escalatedCount = 0;

      for (final doc in reports) {
        final submittedAtStr = doc['submitted_at'];
        if (submittedAtStr == null) continue;

        DateTime? submittedAt;
        if (submittedAtStr is String) {
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

  // ── OneSignal REST API helpers ────────────────────────────────────────────

  /// Send a targeted push via OneSignal filter-based segments.
  Future<void> _sendOneSignalPush({
    required String heading,
    required String content,
    required List<Map<String, dynamic>> filters,
    Map<String, dynamic>? data,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_osBaseUrl/notifications'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Key ${AppConfig.oneSignalRestKey}',
        },
        body: jsonEncode({
          'app_id': AppConfig.oneSignalAppId,
          'headings': {'en': heading},
          'contents': {'en': content},
          'filters': filters,
          'data': ?data,
        }),
      );

      if (response.statusCode == 200) {
        developer.log(
          'OneSignal push sent: $heading',
          name: 'PeerVerificationService',
        );
      } else {
        developer.log(
          'OneSignal push failed: ${response.statusCode} ${response.body}',
          name: 'PeerVerificationService',
        );
      }
    } on Exception catch (e) {
      developer.log('OneSignal push error: $e', name: 'PeerVerificationService');
    }
  }

  /// Send push to a specific user by their external OneSignal user ID.
  Future<void> _sendOneSignalPushToUser({
    required String externalUserId,
    required String heading,
    required String content,
    Map<String, dynamic>? data,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_osBaseUrl/notifications'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Key ${AppConfig.oneSignalRestKey}',
        },
        body: jsonEncode({
          'app_id': AppConfig.oneSignalAppId,
          'headings': {'en': heading},
          'contents': {'en': content},
          'include_aliases': {
            'external_id': [externalUserId],
          },
          'target_channel': 'push',
          'data': ?data,
        }),
      );

      if (response.statusCode != 200) {
        developer.log(
          'OneSignal user push failed: ${response.statusCode} ${response.body}',
          name: 'PeerVerificationService',
        );
      }
    } on Exception catch (e) {
      developer.log(
        'OneSignal user push error: $e',
        name: 'PeerVerificationService',
      );
    }
  }

  // ── Haversine ────────────────────────────────────────────────────────────

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
