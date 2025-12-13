class VerificationReport {
  final String id;
  final String title;
  final String type;
  final String reporter;
  final String location;
  final String time;
  final ReportStatus status;
  final DateTime? verifiedAt;
  final DateTime? resolvedAt;
  final String iconName;
  final String iconColor;
  final String bgIconColor;

  VerificationReport({
    required this.id,
    required this.title,
    required this.type,
    required this.reporter,
    required this.location,
    required this.time,
    required this.status,
    this.verifiedAt,
    this.resolvedAt,
    required this.iconName,
    required this.iconColor,
    required this.bgIconColor,
  });

  VerificationReport copyWith({
    String? id,
    String? title,
    String? type,
    String? reporter,
    String? location,
    String? time,
    ReportStatus? status,
    DateTime? verifiedAt,
    DateTime? resolvedAt,
    String? iconName,
    String? iconColor,
    String? bgIconColor,
  }) {
    return VerificationReport(
      id: id ?? this.id,
      title: title ?? this.title,
      type: type ?? this.type,
      reporter: reporter ?? this.reporter,
      location: location ?? this.location,
      time: time ?? this.time,
      status: status ?? this.status,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      iconName: iconName ?? this.iconName,
      iconColor: iconColor ?? this.iconColor,
      bgIconColor: bgIconColor ?? this.bgIconColor,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'type': type,
      'reporter': reporter,
      'location': location,
      'time': time,
      'status': status.toString(),
      'verifiedAt': verifiedAt?.toIso8601String(),
      'resolvedAt': resolvedAt?.toIso8601String(),
      'iconName': iconName,
      'iconColor': iconColor,
      'bgIconColor': bgIconColor,
    };
  }
}

enum ReportStatus {
  pending,
  acknowledged,
  resolved,
}

extension ReportStatusExtension on ReportStatus {
  String get displayName {
    switch (this) {
      case ReportStatus.pending:
        return 'Pending';
      case ReportStatus.acknowledged:
        return 'Acknowledged';
      case ReportStatus.resolved:
        return 'Resolved';
    }
  }
}
