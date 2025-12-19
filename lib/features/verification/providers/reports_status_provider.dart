import 'package:flutter/material.dart';
import 'package:climate_app/core/services/appwrite_service.dart';
import 'package:climate_app/features/verification/models/verification_report_model.dart';
import 'dart:async';
import 'dart:developer' as developer;
import 'package:appwrite/appwrite.dart';

class ReportsStatusProvider extends ChangeNotifier {
  final AppwriteService _appwrite = AppwriteService();
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  Future<void> refreshReports() async {
    _isLoading = true;
    notifyListeners();
    // Realtime will handle the update, but we can call notify anyway
    await Future.delayed(const Duration(milliseconds: 500));
    _isLoading = false;
    notifyListeners();
  }

  /// Get all reports stream using Realtime
  Stream<List<VerificationReport>> get reportsStatusStream {
    final controller = StreamController<List<VerificationReport>>();
    RealtimeSubscription? subscription;

    void updateReports() async {
      try {
        final docs = await _appwrite.listDocuments(
          collectionId: AppwriteService.reportsCollectionId,
        );

        final reports = docs.documents.map((doc) {
          final data = doc.data;
          final status = _parseStatus(data['status']);
          return VerificationReport(
            id: doc.$id,
            title: _formatTitle(data['hazardType'] ?? 'Unknown Hazard'),
            type: data['hazardType'] ?? 'Unknown',
            reporter: 'Community Report',
            location: data['locationDetails'] ?? 'Unknown Location',
            time: _formatTimeAgo(data['submittedAt']),
            status: status,
            iconName: _getIconName(data['hazardType']),
            iconColor: _getIconColor(data['severity']),
            bgIconColor: '${_getIconColor(data['severity'])}_50',
          );
        }).toList();

        if (!controller.isClosed) {
          controller.add(reports);
        }
      } on Exception catch (e) {
        developer.log('Error updating reports stream: $e');
      }
    }

    updateReports();

    const channel =
        'databases.${AppwriteService.databaseId}.collections.${AppwriteService.reportsCollectionId}.documents';

    subscription = _appwrite.subscribe(
      channels: [channel],
      callback: (event) {
        updateReports();
      },
    );

    controller.onCancel = () {
      subscription?.close();
      controller.close();
    };

    return controller.stream;
  }

  /// Get reports stream by status using Realtime
  Stream<List<VerificationReport>> getReportsStreamByStatus(
    ReportStatus status,
  ) {
    final controller = StreamController<List<VerificationReport>>();
    RealtimeSubscription? subscription;

    void updateReports() async {
      try {
        String appwriteStatus;
        switch (status) {
          case ReportStatus.pending:
            appwriteStatus = 'pending';
            break;
          case ReportStatus.acknowledged:
            appwriteStatus = 'acknowledged';
            break;
          case ReportStatus.resolved:
            appwriteStatus = 'resolved';
            break;
          case ReportStatus.rejected:
            appwriteStatus = 'rejected';
            break;
        }

        final docs = await _appwrite.listDocuments(
          collectionId: AppwriteService.reportsCollectionId,
          queries: [Query.equal('status', appwriteStatus)],
        );

        final reports = docs.documents.map((doc) {
          final data = doc.data;
          return VerificationReport(
            id: doc.$id,
            title: _formatTitle(data['hazardType'] ?? 'Unknown Hazard'),
            type: data['hazardType'] ?? 'Unknown',
            reporter: 'Community Report',
            location: data['locationDetails'] ?? 'Unknown Location',
            time: _formatTimeAgo(data['submittedAt']),
            status: status,
            iconName: _getIconName(data['hazardType']),
            iconColor: _getIconColor(data['severity']),
            bgIconColor: '${_getIconColor(data['severity'])}_50',
          );
        }).toList();

        if (!controller.isClosed) {
          controller.add(reports);
        }
      } on Exception catch (e) {
        developer.log('Error updating reports: $e');
      }
    }

    // Initial fetch
    updateReports();

    // Subscribe to realtime updates
    const channel =
        'databases.${AppwriteService.databaseId}.collections.${AppwriteService.reportsCollectionId}.documents';

    subscription = _appwrite.subscribe(
      channels: [channel],
      callback: (event) {
        // Trigger re-fetch for simplicity and to ensure correct ordering/filtering
        updateReports();
      },
    );

    controller.onCancel = () {
      subscription?.close();
      controller.close();
    };

    return controller.stream;
  }

  /// Get all reports (for CSV export)
  Future<List<VerificationReport>> getAllReports() async {
    try {
      final docs = await _appwrite.listDocuments(
        collectionId: AppwriteService.reportsCollectionId,
      );

      return docs.documents.map((doc) {
        final data = doc.data;
        final status = _parseStatus(data['status']);

        return VerificationReport(
          id: doc.$id,
          title: _formatTitle(data['hazardType'] ?? 'Unknown'),
          type: data['hazardType'] ?? 'Unknown',
          reporter: 'Community Report',
          location: data['locationDetails'] ?? 'Unknown',
          time: _formatTimeAgo(data['submittedAt']),
          status: status,
          iconName: _getIconName(data['hazardType']),
          iconColor: _getIconColor(data['severity']),
          bgIconColor: '${_getIconColor(data['severity'])}_50',
        );
      }).toList();
    } on Exception catch (e) {
      developer.log('Error fetching all reports: $e');
      return [];
    }
  }

  /// Verify a report (move to acknowledged)
  Future<void> verifyReport(String reportId) async {
    try {
      await _appwrite.updateDocument(
        collectionId: AppwriteService.reportsCollectionId,
        documentId: reportId,
        data: {'status': 'acknowledged'},
      );
      developer.log('Report verified: $reportId');
      notifyListeners();
    } on Exception catch (e) {
      developer.log('Error verifying report: $e');
      rethrow;
    }
  }

  /// Resolve a report (mark as resolved)
  Future<void> resolveReport(String reportId) async {
    try {
      await _appwrite.updateDocument(
        collectionId: AppwriteService.reportsCollectionId,
        documentId: reportId,
        data: {'status': 'resolved'},
      );
      developer.log('Report resolved: $reportId');
      notifyListeners();
    } on Exception catch (e) {
      developer.log('Error resolving report: $e');
      rethrow;
    }
  }

  /// Reject a report
  Future<void> rejectReport(String reportId) async {
    try {
      await _appwrite.updateDocument(
        collectionId: AppwriteService.reportsCollectionId,
        documentId: reportId,
        data: {'status': 'rejected'},
      );
      developer.log('Report rejected: $reportId');
      notifyListeners();
    } on Exception catch (e) {
      developer.log('Error rejecting report: $e');
      rethrow;
    }
  }

  /// Move report back to pending (reopen)
  Future<void> moveBackToPending(String reportId) async {
    try {
      await _appwrite.updateDocument(
        collectionId: AppwriteService.reportsCollectionId,
        documentId: reportId,
        data: {'status': 'pending'},
      );
      developer.log('Report moved back to pending: $reportId');
      notifyListeners();
    } on Exception catch (e) {
      developer.log('Error moving report to pending: $e');
      rethrow;
    }
  }

  /// Generate CSV report
  Future<String> generateCSVReport(ReportStatus? filterStatus) async {
    final reports = await getAllReports();
    final filteredReports = filterStatus != null
        ? reports.where((r) => r.status == filterStatus).toList()
        : reports;

    final buffer = StringBuffer();
    buffer.writeln(
      'ID,Title,Type,Reporter,Location,Time,Status,Verified Date,Resolved Date',
    );

    for (final report in filteredReports) {
      buffer.write('${report.id},');
      buffer.write('"${report.title}",');
      buffer.write('${report.type},');
      buffer.write('"${report.reporter}",');
      buffer.write('"${report.location}",');
      buffer.write('${report.time},');
      buffer.write(report.status.displayName);
      buffer.writeln();
    }

    return buffer.toString();
  }

  // Helper methods
  String _formatTitle(String hazardType) {
    switch (hazardType.toLowerCase()) {
      case 'flood':
        return 'Flood Alert';
      case 'drought':
        return 'Drought Warning';
      case 'extreme temperature':
        return 'Temperature Extreme';
      case 'high winds':
        return 'High Wind Alert';
      case 'erosion':
        return 'Erosion Report';
      case 'wildfire':
        return 'Wildfire Report';
      case 'crop disease':
        return 'Crop Disease';
      default:
        return hazardType;
    }
  }

  String _getIconName(String? hazardType) {
    switch (hazardType?.toLowerCase()) {
      case 'flood':
        return 'water';
      case 'drought':
        return 'water_drop';
      case 'wildfire':
        return 'local_fire_department';
      case 'crop disease':
        return 'pest_control';
      default:
        return 'warning';
    }
  }

  String _getIconColor(String? severity) {
    switch (severity?.toLowerCase()) {
      case 'low severity':
        return 'green';
      case 'medium severity':
        return 'orange';
      case 'high severity':
        return 'orange';
      case 'critical severity':
        return 'red';
      default:
        return 'orange';
    }
  }

  ReportStatus _parseStatus(String? status) {
    switch (status?.toLowerCase()) {
      case 'pending':
        return ReportStatus.pending;
      case 'acknowledged':
        return ReportStatus.acknowledged;
      case 'resolved':
        return ReportStatus.resolved;
      case 'rejected':
        return ReportStatus.rejected;
      default:
        return ReportStatus.pending;
    }
  }

  String _formatTimeAgo(dynamic timestamp) {
    if (timestamp == null) return 'Unknown';

    DateTime dateTime;
    if (timestamp is String) {
      try {
        dateTime = DateTime.parse(timestamp);
      } on Exception {
        return 'Unknown';
      }
    } else if (timestamp is DateTime) {
      dateTime = timestamp;
    } else {
      return 'Unknown';
    }

    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${(difference.inDays / 7).floor()}w ago';
    }
  }

  /// Legacy method for backward compatibility
  List<VerificationReport> getReportsByStatus(ReportStatus status) {
    // This is now async, but keeping for compatibility
    // UI should use getReportsStreamByStatus instead
    return [];
  }
}
