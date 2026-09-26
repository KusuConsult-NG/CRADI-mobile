import 'package:climate_app/core/constants/hazards.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart'
    show normalizeSeverity;

class VerificationReport {
  final String id;
  final String title;
  final String type;
  final String reporter;
  final String? reporterId;
  final String location;
  final String time;
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
    required this.reporter,
    this.reporterId,
    required this.location,
    required this.time,
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
    String? reporter,
    String? reporterId,
    String? location,
    String? time,
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
      reporter: reporter ?? this.reporter,
      reporterId: reporterId ?? this.reporterId,
      location: location ?? this.location,
      time: time ?? this.time,
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
      title: data['hazardType'] ?? data['title'] ?? 'Unknown Report',
      type: data['hazardType'] ?? data['type'] ?? 'unknown',
      reporter: data['reporterName'] ?? data['reporter'] ?? 'Anonymous',
      reporterId: data['userId'] ?? data['reporterId'],
      location: data['locationDetails'] ?? data['location'] ?? 'Unknown',
      time: _formatTime(
        data['submittedAt'] ?? data['createdAt'] ?? data['time'],
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
      'reporter': reporter,
      'reporterId': reporterId,
      'location': location,
      'time': time,
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

  static String _formatTime(dynamic raw) {
    if (raw == null) return '';
    // Supabase returns ISO-8601 strings; cached values may be DateTimes.
    final date = raw is DateTime
        ? raw.toLocal()
        : raw is String
        ? DateTime.tryParse(raw)?.toLocal()
        : null;
    if (date == null) return raw.toString();
    try {
      final diff = DateTime.now().difference(date);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${date.day}/${date.month}/${date.year}';
    } on Exception catch (_) {
      return raw.toString();
    }
  }
}

enum ReportStatus { pending, verified, approved, rejected }

extension ReportStatusExtension on ReportStatus {
  String get displayName {
    switch (this) {
      case ReportStatus.pending:
        return 'Pending';
      case ReportStatus.verified:
        return 'Verified';
      case ReportStatus.approved:
        return 'Approved';
      case ReportStatus.rejected:
        return 'Rejected';
    }
  }
}
