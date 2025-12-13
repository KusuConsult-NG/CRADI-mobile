import 'package:flutter/material.dart';
import 'package:climate_app/features/verification/models/verification_report_model.dart';

class ReportsStatusProvider extends ChangeNotifier {
  final List<VerificationReport> _allReports = [
    // Demo data
    VerificationReport(
      id: '1',
      title: 'Crop Pest Infestation',
      type: 'Pest',
      reporter: 'Peer Yusuf',
      location: 'Makurdi North',
      time: '30m ago',
      status: ReportStatus.pending,
      iconName: 'pest_control',
      iconColor: 'orange',
      bgIconColor: 'orange_50',
    ),
    VerificationReport(
      id: '2',
      title: 'Drought Signs',
      type: 'Drought',
      reporter: 'Peer Amara',
      location: 'Otukpo East',
      time: '2h ago',
      status: ReportStatus.pending,
      iconName: 'water_drop',
      iconColor: 'blue',
      bgIconColor: 'blue_50',
    ),
    VerificationReport(
      id: '3',
      title: 'Flash Flood Warning',
      type: 'Flood',
      reporter: 'Monitor Musa',
      location: 'Benue River Bank',
      time: '1d ago',
      status: ReportStatus.acknowledged,
      verifiedAt: DateTime.now().subtract(const Duration(hours: 4)),
      iconName: 'water',
      iconColor: 'red',
      bgIconColor: 'red_50',
    ),
    VerificationReport(
      id: '4',
      title: 'Wildfire Containment',
      type: 'Fire',
      reporter: 'Peer John',
      location: 'Gboko District',
      time: '3d ago',
      status: ReportStatus.resolved,
      verifiedAt: DateTime.now().subtract(const Duration(days: 2)),
      resolvedAt: DateTime.now().subtract(const Duration(hours: 12)),
      iconName: 'local_fire_department',
      iconColor: 'green',
      bgIconColor: 'green_50',
    ),
  ];

  List<VerificationReport> get allReports => List.unmodifiable(_allReports);

  List<VerificationReport> getReportsByStatus(ReportStatus status) {
    return _allReports.where((report) => report.status == status).toList();
  }

  void verifyReport(String reportId) {
    final index = _allReports.indexWhere((r) => r.id == reportId);
    if (index != -1) {
      _allReports[index] = _allReports[index].copyWith(
        status: ReportStatus.acknowledged,
        verifiedAt: DateTime.now(),
      );
      notifyListeners();
    }
  }

  void resolveReport(String reportId) {
    final index = _allReports.indexWhere((r) => r.id == reportId);
    if (index != -1) {
      _allReports[index] = _allReports[index].copyWith(
        status: ReportStatus.resolved,
        resolvedAt: DateTime.now(),
      );
      notifyListeners();
    }
  }

  void moveBackToPending(String reportId) {
    final index = _allReports.indexWhere((r) => r.id == reportId);
    if (index != -1) {
      _allReports[index] = _allReports[index].copyWith(
        status: ReportStatus.pending,
        verifiedAt: null,
        resolvedAt: null,
      );
      notifyListeners();
    }
  }

  String generateCSVReport(ReportStatus? filterStatus) {
    final reports = filterStatus != null
        ? getReportsByStatus(filterStatus)
        : _allReports;

    final buffer = StringBuffer();
    buffer.writeln('ID,Title,Type,Reporter,Location,Time,Status,Verified Date,Resolved Date');

    for (final report in reports) {
      buffer.write('${report.id},');
      buffer.write('"${report.title}",');
      buffer.write('${report.type},');
      buffer.write('"${report.reporter}",');
      buffer.write('"${report.location}",');
      buffer.write('${report.time},');
      buffer.write('${report.status.displayName},');
      buffer.write('${report.verifiedAt?.toString() ?? "N/A"},');
      buffer.write(report.resolvedAt?.toString() ?? "N/A");
      buffer.writeln();
    }

    return buffer.toString();
  }
}
