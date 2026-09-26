import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/core/services/remote_config_service.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart'
    show AuthProvider, UserRole;
import 'dart:developer' as developer;
import 'dart:math' as math;

/// Client side of the peer verification workflow.
///
/// Most of the workflow now runs in the database / backend:
///   * inserting into `verifications` fires `verifications_after_insert`,
///     which recounts confirmations and moves a pending report to
///     'verified' exactly once when the threshold is reached;
///   * inserting a report schedules its escalation and queues the
///     peer-verification push (`reports_after_insert`);
///   * overdue escalations are processed by the backend cron;
///   * every push / SMS / email is sent by the Railway backend from
///     `notification_outbox` events.
///
/// The client only records verifications and staff overrides.
class PeerVerificationService {
  static final PeerVerificationService _instance =
      PeerVerificationService._internal();
  factory PeerVerificationService() => _instance;
  PeerVerificationService._internal();

  final SupabaseService _db = SupabaseService();

  /// Submit a verification (confirm or dispute).
  ///
  /// [userId] is only used for the client-side self-verification guard; the
  /// row's `verifier_id` is always `auth.uid()` (database default + RLS).
  Future<Map<String, dynamic>> submitVerification({
    required String reportId,
    required String userId,
    required bool isConfirmed,
    String? comment,
    double? userLatitude,
    double? userLongitude,
  }) async {
    // ── Guard 1: Self-verification (also enforced by RLS) ──────────────
    final reportDoc = await _db.getDocument(
      collectionId: AppConfig.reportsCollection,
      documentId: reportId,
    );
    final reporterId = reportDoc['userId'] as String? ?? '';
    if (reporterId == userId) {
      return {
        'success': false,
        'message': 'You cannot verify your own report.',
      };
    }

    // ── Guard 2: Location proximity (2 km) ────────────────────────────
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

    try {
      final result = await _db.createDocument(
        collectionId: AppConfig.verificationsCollection,
        data: {
          'reportId': reportId,
          'isConfirmed': isConfirmed,
          'comment': comment ?? '',
        },
      );

      developer.log(
        'Verification submitted: ${result['\$id']} (confirmed: $isConfirmed)',
        name: 'PeerVerificationService',
      );

      return {
        'success': true,
        'verificationId': result['\$id'],
        'message': isConfirmed
            ? 'Report confirmed successfully'
            : 'Report disputed',
      };
    } on Exception catch (e) {
      if (SupabaseService.isUniqueViolation(e)) {
        return {
          'success': false,
          'alreadyVoted': true,
          'message': 'You have already voted on this report.',
        };
      }
      if (SupabaseService.isPermissionDenied(e)) {
        return {
          'success': false,
          'message':
              'Your account is not permitted to verify reports. '
              'Verification requires an approved monitor role.',
        };
      }
      developer.log(
        'Error submitting verification: $e',
        name: 'PeerVerificationService',
      );
      rethrow;
    }
  }

  /// Manual approve / reject by senior staff (ewv, ewr, ldp_coordinator,
  /// project_staff, admin; never one's own report — enforced by the
  /// `guard_report_update` trigger). The decision is audited into
  /// `verification_overrides` by the `reports_audit_decision` trigger, and
  /// the backend notifies from the resulting status-change event.
  Future<Map<String, dynamic>> manualValidation({
    required String reportId,
    required bool isApproved,
    String reason = '',
  }) async {
    final now = DateTime.now().toUtc();
    await _db.updateDocument(
      collectionId: AppConfig.reportsCollection,
      documentId: reportId,
      data: isApproved
          ? {'status': 'approved', 'approvedAt': now}
          : {
              'status': 'rejected',
              'rejectedAt': now,
              'rejectionReason': reason,
            },
    );
    return {
      'success': true,
      'message': isApproved ? 'Report approved' : 'Report rejected',
    };
  }

  /// Get verification statistics for a report.
  ///
  /// Verifications are readable by every verifier role and by
  /// ldp_coordinator / project_staff (`verifications_select`). Pass the
  /// caller's *effective* role (`AuthProvider.userRole`, which is `user`
  /// until the account is approved) as [role]: `canValidate` is then only
  /// true for roles allowed to approve / reject. `readable` is false when
  /// the votes could not be read (so zero counts are not trusted).
  Future<Map<String, dynamic>> getVerificationStats(
    String reportId, {
    UserRole? role,
  }) async {
    try {
      final verifications = await _db.listDocuments(
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

      final roleMayValidate =
          role == null || AuthProvider.statusManagerRoles.contains(role);
      return {
        'readable': true,
        'totalVerifications': verifications.length,
        'confirmations': confirmations,
        'disputes': disputes,
        'requiresEscalation': disputes > 0 && confirmations == 0,
        'canValidate':
            roleMayValidate &&
            confirmations >= RemoteConfigService().minimumPeerConfirmations,
      };
    } on Exception catch (e) {
      developer.log(
        'Error getting verification stats: $e',
        name: 'PeerVerificationService',
      );
      return {
        'readable': false,
        'totalVerifications': 0,
        'confirmations': 0,
        'disputes': 0,
        'requiresEscalation': false,
        'canValidate': false,
      };
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
