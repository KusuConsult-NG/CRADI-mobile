import 'package:climate_app/core/constants/hazards.dart';
import 'package:climate_app/core/l10n/relative_time.dart';
import 'package:climate_app/l10n/app_localizations.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart'
    show normalizeSeverity;

class VerificationReport {
  final String id;
  final String title;

  /// Hazard type (`reports.hazard_type`).
  final String type;

  /// Kind of report row (`reports.type`): null for ordinary reports,
  /// [verificationRequestType] for requests sent from the verification
  /// request screen.
  final String? reportType;

  /// Stored [reportType] of verification requests.
  static const String verificationRequestType = 'verification_request';

  /// Location text stored on verification requests (not user-entered).
  static const String verificationRequestLocation = 'Verification Request';
  final String reporter;
  final String? reporterId;
  final String location;
  final String time;

  /// When the report was submitted (local time); drives the localised
  /// "time ago" label (see [displayTime]). [time] is the fallback for data
  /// without a timestamp.
  final DateTime? submittedAt;
  final ReportStatus status;
  final String iconName;
  final String iconColor;
  final String bgIconColor;

  // ── Extended fields for detail viewer & geolocation ──
  final double? latitude;
  final double? longitude;
  final String? description;
  final String? severity;
  final List<String> imageUrls;
  final int verificationCount;
  final String? lga;
  final String? ward;
  final String? state;

  /// Staff's reason for rejecting the report (null unless rejected).
  final String? rejectionReason;

  /// When the report was rejected (local time).
  final DateTime? rejectedAt;

  VerificationReport({
    required this.id,
    required this.title,
    required this.type,
    this.reportType,
    required this.reporter,
    this.reporterId,
    required this.location,
    required this.time,
    this.submittedAt,
    required this.status,
    required this.iconName,
    required this.iconColor,
    required this.bgIconColor,
    this.latitude,
    this.longitude,
    this.description,
    this.severity,
    this.imageUrls = const [],
    this.verificationCount = 0,
    this.lga,
    this.ward,
    this.state,
    this.rejectionReason,
    this.rejectedAt,
  });

  /// Whether this report is in an active state (visible in "Active" tab).
  bool get isActive =>
      status == ReportStatus.pending || status == ReportStatus.verified;

  /// Whether this report is historical (visible in "History" tab).
  bool get isHistory =>
      status == ReportStatus.approved || status == ReportStatus.rejected;

  VerificationReport copyWith({
    String? id,
    String? title,
    String? type,
    String? reportType,
    String? reporter,
    String? reporterId,
    String? location,
    String? time,
    DateTime? submittedAt,
    ReportStatus? status,
    String? iconName,
    String? iconColor,
    String? bgIconColor,
    double? latitude,
    double? longitude,
    String? description,
    String? severity,
    List<String>? imageUrls,
    int? verificationCount,
    String? lga,
    String? ward,
    String? state,
    String? rejectionReason,
    DateTime? rejectedAt,
  }) {
    return VerificationReport(
      id: id ?? this.id,
      title: title ?? this.title,
      type: type ?? this.type,
      reportType: reportType ?? this.reportType,
      reporter: reporter ?? this.reporter,
      reporterId: reporterId ?? this.reporterId,
      location: location ?? this.location,
      time: time ?? this.time,
      submittedAt: submittedAt ?? this.submittedAt,
      status: status ?? this.status,
      iconName: iconName ?? this.iconName,
      iconColor: iconColor ?? this.iconColor,
      bgIconColor: bgIconColor ?? this.bgIconColor,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      description: description ?? this.description,
      severity: severity ?? this.severity,
      imageUrls: imageUrls ?? this.imageUrls,
      verificationCount: verificationCount ?? this.verificationCount,
      lga: lga ?? this.lga,
      ward: ward ?? this.ward,
      state: state ?? this.state,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      rejectedAt: rejectedAt ?? this.rejectedAt,
    );
  }

  /// Build a [VerificationReport] from a report document map.
  /// Handles backward-compatible status parsing for legacy docs.
  factory VerificationReport.fromMap(Map<String, dynamic> data, String docId) {
    return VerificationReport(
      id: docId,
      title: data['hazardType'] ?? data['title'] ?? '',
      type: data['hazardType'] ?? data['type'] ?? 'unknown',
      // Rows carry the hazard in hazardType and the row kind in type;
      // serialised reports (toJson) carry the row kind in reportType.
      reportType: _nonEmpty(
        data['reportType'] ??
            (data['hazardType'] != null ? data['type'] : null),
      ),
      reporter: data['reporterName'] ?? data['reporter'] ?? '',
      reporterId: data['userId'] ?? data['reporterId'],
      location: data['locationDetails'] ?? data['location'] ?? '',
      time: _formatTime(
        data['submittedAt'] ?? data['createdAt'] ?? data['time'],
      ),
      submittedAt: _parseDate(
        data['submittedAt'] ?? data['createdAt'] ?? data['submittedAtIso'],
      ),
      status: _parseStatus(data['status']),
      iconName: Hazard.iconKeyFor(data['hazardType']),
      iconColor: SeverityColors.nameFor(normalizeSeverity(data['severity'])),
      bgIconColor:
          '${SeverityColors.nameFor(normalizeSeverity(data['severity']))}_50',
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      description: data['description'],
      severity: data['severity'],
      imageUrls: List<String>.from(data['imageUrls'] ?? []),
      verificationCount: (data['verificationCount'] as num?)?.toInt() ?? 0,
      lga: data['lga'] as String?,
      ward: data['ward'] as String?,
      state: data['state'] as String?,
      rejectionReason: _nonEmpty(data['rejectionReason']),
      rejectedAt: _parseDate(data['rejectedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'type': type,
      'reportType': reportType,
      'reporter': reporter,
      'reporterId': reporterId,
      'location': location,
      'time': time,
      'submittedAtIso': submittedAt?.toUtc().toIso8601String(),
      'status': status.name,
      'iconName': iconName,
      'iconColor': iconColor,
      'bgIconColor': bgIconColor,
      'latitude': latitude,
      'longitude': longitude,
      'description': description,
      'severity': severity,
      'imageUrls': imageUrls,
      'verificationCount': verificationCount,
      'lga': lga,
      'ward': ward,
      'state': state,
      'rejectionReason': rejectionReason,
      'rejectedAt': rejectedAt?.toUtc().toIso8601String(),
    };
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  static String? _nonEmpty(Object? raw) {
    final s = raw?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw is DateTime) return raw.toLocal();
    if (raw is String) return DateTime.tryParse(raw)?.toLocal();
    return null;
  }

  static ReportStatus _parseStatus(dynamic raw) {
    final s = (raw ?? 'pending').toString().toLowerCase();
    switch (s) {
      case 'verified':
      // legacy compat:
      case 'acknowledged':
        return ReportStatus.verified;
      case 'approved':
      // legacy compat:
      case 'validated':
      case 'resolved':
        return ReportStatus.approved;
      case 'rejected':
        return ReportStatus.rejected;
      case 'pending':
      default:
        return ReportStatus.pending;
    }
  }

  /// Fallback text for [time] when there is no parseable timestamp (e.g. a
  /// legacy cached "5m ago"); parseable timestamps are shown via
  /// [submittedAt] instead, so this never produces display text itself.
  static String _formatTime(dynamic raw) {
    if (raw == null) return '';
    if (raw is DateTime) return '';
    if (raw is String && DateTime.tryParse(raw) != null) return '';
    return raw.toString();
  }

  // ── Display (localised) ─────────────────────────────────────────────────

  /// Whether this is a verification request (see [reportType]).
  bool get isVerificationRequest => reportType == verificationRequestType;

  /// Card headline for this report's hazard.
  String displayTitle(AppLocalizations l10n) => Hazard.titleFor(type, l10n);

  /// Location text, or "Unknown Location".
  /// Verification requests store a fixed placeholder, shown localised.
  String displayLocation(AppLocalizations l10n) {
    final text = location.trim();
    if (isVerificationRequest &&
        (text.isEmpty || text == verificationRequestLocation)) {
      return l10n.verificationRequestBadge;
    }
    return text.isEmpty ? l10n.commonUnknownLocation : location;
  }

  /// Reporter name, or "Community Report" when unknown.
  String displayReporter(AppLocalizations l10n) =>
      reporter.trim().isEmpty ? l10n.commonCommunityReport : reporter;

  /// "5m ago" style submission time (or the stored [time] fallback).
  String displayTime(AppLocalizations l10n) {
    final at = submittedAt;
    if (at != null) return relativeTimeLabel(l10n, at);
    return time.isEmpty ? l10n.commonUnknown : time;
  }
}

enum ReportStatus { pending, verified, approved, rejected }

/// Display text for a stored report status value ('pending', 'approved',
/// …); unknown values are shown as stored.
String reportStatusLabelFor(AppLocalizations l10n, String status) {
  final s = status.toLowerCase();
  for (final value in ReportStatus.values) {
    if (value.name == s) return value.label(l10n);
  }
  return status;
}

extension ReportStatusExtension on ReportStatus {
  /// Status badge text in the language of [l10n] (the stored value is
  /// [name]).
  String label(AppLocalizations l10n) {
    switch (this) {
      case ReportStatus.pending:
        return l10n.reportStatusPending;
      case ReportStatus.verified:
        return l10n.reportStatusVerified;
      case ReportStatus.approved:
        return l10n.reportStatusApproved;
      case ReportStatus.rejected:
        return l10n.reportStatusRejected;
    }
  }
}
