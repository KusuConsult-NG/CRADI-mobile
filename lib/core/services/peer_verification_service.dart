import 'package:climate_app/core/services/backend.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/core/services/remote_config_service.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart'
    show AuthProvider, UserRole;
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'package:climate_app/core/l10n/l10n.dart';

/// Client side of the peer verification workflow.
///
/// Result maps carry `'message'` as a [LocalizedText] (resolved by the UI in
/// the current language).
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

  final DataBackend _db = backend;

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
        'message': (AppLocalizations l) => l.verifyErrorOwnReport,
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
            'message': (AppLocalizations l) =>
                l.verifyErrorTooFar(dist.toStringAsFixed(1)),
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
            ? (AppLocalizations l) => l.verifyConfirmedMessage
            : (AppLocalizations l) => l.verifyDisputedMessage,
      };
    } on Exception catch (e) {
      if (isDuplicate(e)) {
        return {
          'success': false,
          'alreadyVoted': true,
          'message': (AppLocalizations l) => l.verifyErrorAlreadyVoted,
        };
      }
      if (isRefusal(e)) {
        // RLS also refuses votes on reports that left 'pending' (e.g.
        // verified or rejected meanwhile): tell those apart.
        if (await _isNoLongerPending(reportId)) {
          return {
            'success': false,
            'noLongerPending': true,
            'message': noLongerPendingMessage,
          };
        }
        return {
          'success': false,
          'message': (AppLocalizations l) => l.verifyErrorNotPermitted,
        };
      }
      developer.log(
        'Error submitting verification: $e',
        name: 'PeerVerificationService',
      );
      rethrow;
    }
  }

  /// Message returned when a vote is refused because the report is no
  /// longer pending.
  static String noLongerPendingMessage(AppLocalizations l) =>
      l.verifyErrorNoLongerPending;

  /// Re-reads the report after a refused vote: true when it is no longer
  /// pending (also when it is no longer visible: RLS hides reports that
  /// left 'pending' from peers, or it was deleted). Unknown (read failed)
  /// counts as still pending.
  Future<bool> _isNoLongerPending(String reportId) async {
    try {
      final doc = await _db.getDocument(
        collectionId: AppConfig.reportsCollection,
        documentId: reportId,
      );
      final status = (doc['status'] as String?)?.toLowerCase();
      return status != null && status != 'pending';
    } on DocumentNotFoundException {
      return true;
    } on Exception catch (e) {
      developer.log(
        'Could not re-read report $reportId: $e',
        name: 'PeerVerificationService',
      );
      return false;
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
      'message': isApproved
          ? (AppLocalizations l) => l.reportResolvedItem
          : (AppLocalizations l) => l.reportRejectedItem,
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

  /// The peer votes on [reportId] (confirmations and disputes with their
  /// comments), newest first. Readable by ewm, ewv, ewr, ldp_coordinator,
  /// project_staff, admin and techSupport (`verifications_select`).
  ///
  /// The verifier's name is embedded from `profiles` where the caller may
  /// read that profile; otherwise it is null (never looked up separately).
  Future<List<ReportVerification>> getVerifications(String reportId) async {
    final docs = await _db.listDocuments(
      collectionId: AppConfig.verificationsCollection,
      queries: [
        FQuery.equal('reportId', reportId),
        FQuery.orderDesc('submittedAt'),
        FQuery.limit(200),
      ],
      // Best-effort by contract: a backend that cannot join returns the
      // documents without it and the name simply reads as null.
      related: const RelatedFields(
        alias: 'verifier',
        collectionId: AppConfig.usersCollection,
        foreignKey: 'verifierId',
        fields: ['name'],
      ),
    );
    return docs.map(ReportVerification.fromDocument).toList();
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

/// One peer vote on a report.
class ReportVerification {
  const ReportVerification({
    required this.verifierId,
    required this.isConfirmed,
    this.comment = '',
    this.verifierName,
    this.submittedAt,
  });

  /// Builds a vote from a raw `verifications` row (optionally with an
  /// embedded `verifier: {name}`).
  /// Reads a document as the backend returns it — field names, not column
  /// names. [verifier] is the embedded related object where the backend
  /// could supply one; absent, the name reads as null, which is what the
  /// UI already shows for a profile the caller may not read.
  factory ReportVerification.fromDocument(Map<String, dynamic> doc) {
    final verifier = doc['verifier'];
    final name = verifier is Map ? verifier['name']?.toString().trim() : null;
    return ReportVerification(
      verifierId: doc['verifierId']?.toString() ?? '',
      isConfirmed: doc['isConfirmed'] == true,
      comment: doc['comment']?.toString().trim() ?? '',
      verifierName: (name == null || name.isEmpty) ? null : name,
      submittedAt: parseTimestamp(doc['submittedAt'] ?? doc['createdAt']),
    );
  }

  final String verifierId;
  final bool isConfirmed;
  final String comment;
  final String? verifierName;
  final DateTime? submittedAt;
}
