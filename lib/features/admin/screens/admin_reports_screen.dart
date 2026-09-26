import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'dart:developer' as developer;

/// Admin Reports Overview screen.
/// Lists all reports across all LGAs with status filters and manual actions.
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  String _statusFilter = 'all';
  final SupabaseService _supabase = SupabaseService();
  List<Map<String, dynamic>> _reports = [];
  bool _loading = false;

  static const _statuses = [
    'all',
    'pending',
    'verified',
    'approved',
    'rejected',
  ];
  static const _statusColors = {
    'pending': Colors.orange,
    'verified': Colors.deepOrange,
    'approved': Colors.green,
    'rejected': Colors.red,
  };

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() => _loading = true);
    try {
      final docs = await _supabase.listDocuments(
        collectionId: AppConfig.reportsCollection,
        queries: [
          SQuery.orderDesc('submitted_at'),
          SQuery.limit(200),
        ],
      );
      if (mounted) setState(() => _reports = docs);
    } on Exception catch (e) {
      developer.log('Error loading reports: $e', name: 'AdminReportsScreen');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateStatus(String reportId, String newStatus) async {
    try {
      await _supabase.updateDocument(
        collectionId: AppConfig.reportsCollection,
        documentId: reportId,
        data: {
          'status': newStatus,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
      developer.log('Report $reportId → $newStatus', name: 'AdminReportsScreen');
      _loadReports();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Report marked as $newStatus')));
      }
    } on Exception catch (e) {
      developer.log('Error updating report status: $e', name: 'AdminReportsScreen');
    }
  }

  void _showReportDetails(
    BuildContext context,
    String id,
    Map<String, dynamic> data,
  ) {
    final hazard = (data['hazard_type'] ?? data['hazardType'] ?? 'Unknown').toString();
    final severity = (data['severity'] ?? '').toString();
    final lga = (data['lga'] ?? '').toString();
    final ward = (data['ward'] ?? '').toString();
    final locationDetails = (data['location_description'] ?? data['locationDetails'] ?? '').toString();
    final description = (data['description'] ?? 'No description provided.').toString();
    final imageUrls = ((data['image_urls'] ?? data['imageUrls']) as List<dynamic>?)?.cast<String>() ?? [];
    final status = (data['status'] ?? 'pending').toString();
    final createdAt = data['submitted_at'] ?? data['created_at'] ?? data['createdAt'];
    String timeStr = '';
    if (createdAt != null) {
      final dt = DateTime.tryParse(createdAt.toString());
      if (dt != null) {
        timeStr =
            '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Report Details',
                        style: GoogleFonts.lexend(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                // Body
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      _detailRow('Hazard Type', hazard),
                      _detailRow('Severity', severity),
                      _detailRow(
                        'Status',
                        status.capitalize(),
                        _statusColors[status],
                      ),
                      _detailRow('Date/Time', timeStr),
                      _detailRow('LGA', lga),
                      _detailRow('Ward', ward),
                      _detailRow('Location Details', locationDetails),
                      const SizedBox(height: 16),
                      Text(
                        'Description',
                        style: GoogleFonts.lexend(
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: GoogleFonts.lexend(fontSize: 15),
                      ),
                      const SizedBox(height: 16),
                      if (imageUrls.isNotEmpty) ...[
                        Text(
                          'Images',
                          style: GoogleFonts.lexend(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 120,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: imageUrls.length,
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    imageUrls[index],
                                    width: 120,
                                    height: 120,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, error, stackTrace) =>
                                        Container(
                                          width: 120,
                                          height: 120,
                                          color: Colors.grey.shade200,
                                          child: const Icon(Icons.broken_image),
                                        ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
                // Actions Footer
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Color.fromRGBO(0, 0, 0, 0.05),
                        blurRadius: 10,
                        offset: Offset(0, -5),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        if (status != 'approved')
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () {
                              _updateStatus(id, 'approved');
                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.check, size: 18),
                            label: const Text('Approve'),
                          ),
                        if (status != 'rejected')
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () {
                              _updateStatus(id, 'rejected');
                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.close, size: 18),
                            label: const Text('Reject'),
                          ),
                        if (status != 'verified')
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () {
                              _updateStatus(id, 'verified');
                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.verified, size: 18),
                            label: const Text('Mark Verified'),
                          ),
                        if (status != 'pending')
                          OutlinedButton.icon(
                            onPressed: () {
                              _updateStatus(id, 'pending');
                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Reset'),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredDocs = _reports.where((d) {
      if (_statusFilter != 'all') {
        final status = d['status'] as String? ?? 'pending';
        if (status != _statusFilter) return false;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Reports Overview',
          style: GoogleFonts.lexend(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.primaryRed,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // ── Status filters ──
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _statuses
                    .map(
                      (s) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(
                            s == 'all' ? 'All' : s.capitalize(),
                            style: GoogleFonts.lexend(fontSize: 12),
                          ),
                          selected: _statusFilter == s,
                          selectedColor: _statusFilter == s
                              ? (_statusColors[s] ?? AppColors.primaryRed)
                              : null,
                          labelStyle: TextStyle(
                            color: _statusFilter == s ? Colors.white : null,
                          ),
                          onSelected: (_) => setState(() => _statusFilter = s),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          // ── List ──
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadReports,
                    child: filteredDocs.isEmpty
                        ? Center(
                            child: Text(
                              'No reports found',
                              style: GoogleFonts.lexend(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredDocs.length,
                            itemBuilder: (_, i) {
                              final d = filteredDocs[i];
                              final id = (d['id'] ?? d['\$id'] ?? '').toString();
                              final hazard = (d['hazard_type'] ?? d['hazardType'] ?? 'Unknown').toString();
                              final lga = (d['lga'] ?? '').toString();
                              final ward = (d['ward'] ?? '').toString();
                              final status = (d['status'] ?? 'pending').toString();
                              final severity = (d['severity'] ?? '').toString();
                              final createdAt = d['submitted_at'] ?? d['created_at'] ?? d['createdAt'];
                              String timeStr = '';
                              if (createdAt != null) {
                                final dt = DateTime.tryParse(createdAt.toString());
                                if (dt != null) {
                                  timeStr = '${dt.day}/${dt.month}/${dt.year}';
                                }
                              }

                              final statusColor = _statusColors[status] ?? Colors.grey;

                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: ListTile(
                                  onTap: () => _showReportDetails(context, id, d),
                                  leading: Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      Icons.report_outlined,
                                      color: statusColor,
                                      size: 24,
                                    ),
                                  ),
                                  title: Text(
                                    hazard,
                                    style: GoogleFonts.lexend(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '$ward, $lga',
                                        style: GoogleFonts.lexend(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          _chip(status.capitalize(), statusColor),
                                          if (severity.isNotEmpty) ...[
                                            const SizedBox(width: 4),
                                            _chip(severity, Colors.purple),
                                          ],
                                          if (timeStr.isNotEmpty) ...[
                                            const SizedBox(width: 4),
                                            Text(
                                              timeStr,
                                              style: GoogleFonts.lexend(
                                                fontSize: 10,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (action) => _updateStatus(id, action),
                                    itemBuilder: (_) => [
                                      if (status != 'approved')
                                        const PopupMenuItem(
                                          value: 'approved',
                                          child: Text('Approve'),
                                        ),
                                      if (status != 'rejected')
                                        const PopupMenuItem(
                                          value: 'rejected',
                                          child: Text('Reject'),
                                        ),
                                      if (status != 'verified')
                                        const PopupMenuItem(
                                          value: 'verified',
                                          child: Text('Mark Verified'),
                                        ),
                                      if (status != 'pending')
                                        const PopupMenuItem(
                                          value: 'pending',
                                          child: Text('Reset to pending'),
                                        ),
                                    ],
                                  ),
                                  isThreeLine: true,
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: GoogleFonts.lexend(
        fontSize: 10,
        color: color,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _detailRow(String label, String value, [Color? color]) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: GoogleFonts.lexend(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.lexend(
                fontWeight: color != null ? FontWeight.bold : FontWeight.normal,
                color: color ?? AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension _StringExt on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
