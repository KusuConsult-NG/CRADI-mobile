import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:provider/provider.dart';
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

  static const int _pageSize = 50;

  final List<Map<String, dynamic>> _reports = [];
  bool _loading = false;
  bool _hasMore = true;
  String? _error;

  /// Bumped on every reload so responses for a stale filter are dropped.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() {
    _generation++;
    setState(() {
      _reports.clear();
      _hasMore = true;
      _error = null;
      _loading = false;
    });
    return _loadMore();
  }

  /// Loads the next page, newest first. The status filter is applied by the
  /// server.
  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    final generation = _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await SupabaseService().listDocuments(
        collectionId: AppConfig.reportsCollection,
        queries: [
          if (_statusFilter != 'all') FQuery.equal('status', _statusFilter),
          FQuery.orderDesc('submittedAt'),
        ],
        limitCount: _pageSize,
        offset: _reports.length,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        final known = _reports.map((r) => r[r'$id']).toSet();
        _reports.addAll(page.where((r) => !known.contains(r[r'$id'])));
        _hasMore = page.length == _pageSize;
      });
    } on Exception catch (e) {
      developer.log('Reports load failed: $e', name: 'AdminReportsScreen');
      if (mounted && generation == _generation) {
        setState(
          () => _error =
              'Could not load reports. You may not have permission to view them.',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  bool _isAdmin(BuildContext context) =>
      context.read<AuthProvider>().userRole == UserRole.admin;

  /// Status actions the current user may apply to a report in [status]
  /// (mirrors guard_report_update: only admins set 'verified' directly;
  /// moving back to pending goes through the reopen_report RPC).
  List<String> _allowedActions(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    final auth = context.read<AuthProvider>();
    if (!auth.canManageReportStatus(reporterId: data['userId']?.toString())) {
      return const [];
    }
    final status = data['status'] as String? ?? 'pending';
    return [
      if (status != 'approved') 'approved',
      if (status != 'rejected') 'rejected',
      if (status != 'verified' && _isAdmin(context)) 'verified',
      if (status != 'pending') 'pending',
    ];
  }

  Future<void> _updateStatus(String reportId, String newStatus) async {
    Map<String, dynamic>? updated;
    try {
      if (newStatus == 'pending') {
        // Reopening clears peer votes; only the reopen_report RPC may do
        // it. The provider also drops the cached vote and refreshes lists.
        await context.read<ReportsStatusProvider>().moveBackToPending(reportId);
      } else {
        final now = DateTime.now();
        updated = await SupabaseService().updateDocument(
          collectionId: AppConfig.reportsCollection,
          documentId: reportId,
          data: {
            'status': newStatus,
            'updatedBy': SupabaseService().currentUserId,
            if (newStatus == 'verified') 'verifiedAt': now,
            if (newStatus == 'approved') 'approvedAt': now,
            if (newStatus == 'rejected') 'rejectedAt': now,
          },
        );
      }
    } on Exception catch (e) {
      developer.log('Status update failed: $e', name: 'AdminReportsScreen');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update report status.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    developer.log('Report $reportId → $newStatus', name: 'AdminReportsScreen');
    if (!mounted) return;
    setState(() {
      final i = _reports.indexWhere((r) => r[r'$id'] == reportId);
      if (i != -1) {
        if (_statusFilter != 'all' && _statusFilter != newStatus) {
          _reports.removeAt(i);
        } else {
          _reports[i] = updated ?? {..._reports[i], 'status': newStatus};
        }
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          newStatus == 'pending'
              ? 'Report reopened for verification'
              : 'Report marked as $newStatus',
        ),
      ),
    );
  }

  void _showReportDetails(
    BuildContext context,
    String id,
    Map<String, dynamic> data,
  ) {
    final hazard = data['hazardType'] as String? ?? 'Unknown';
    final severity = data['severity'] as String? ?? '';
    final lga = data['lga'] as String? ?? '';
    final ward = data['ward'] as String? ?? '';
    final locationDetails = data['locationDetails'] as String? ?? '';
    final description =
        data['description'] as String? ?? 'No description provided.';
    final imageUrls =
        (data['imageUrls'] as List<dynamic>?)?.cast<String>() ?? [];
    final status = data['status'] as String? ?? 'pending';
    // Status changes are refused by the database for tech support (and for
    // staff on their own reports) — mirror guard_report_update.
    final actions = _allowedActions(context, data);
    final canChangeStatus = actions.isNotEmpty;
    final createdAt = data['submittedAt'] ?? data['createdAt'];
    String timeStr = '';
    final dt = parseTimestamp(createdAt);
    if (dt != null) {
      timeStr =
          '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
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
                if (canChangeStatus)
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
                          if (actions.contains('approved'))
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
                          if (actions.contains('rejected'))
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
                          if (actions.contains('verified'))
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
                          if (actions.contains('pending'))
                            OutlinedButton.icon(
                              onPressed: () {
                                _updateStatus(id, 'pending');
                                Navigator.pop(context);
                              },
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('Reopen (pending)'),
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
                          onSelected: (_) {
                            if (_statusFilter == s) return;
                            setState(() => _statusFilter = s);
                            _reload();
                          },
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          // ── List ──
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_reports.isEmpty) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.all(48),
              child: Column(
                children: [
                  Text(
                    _error ?? 'No reports found',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.lexend(
                      color: _error != null
                          ? Colors.red
                          : AppColors.textSecondary,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _reload,
                      child: const Text('Retry'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _reports.length + 1,
        itemBuilder: (_, i) {
          if (i == _reports.length) return _buildFooter();
          return _buildReportTile(_reports[i]);
        },
      ),
    );
  }

  Widget _buildFooter() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: TextButton(
            onPressed: _loadMore,
            child: const Text('Could not load more. Tap to retry.'),
          ),
        ),
      );
    }
    if (!_hasMore) return const SizedBox(height: 24);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: _loadMore,
          icon: const Icon(Icons.expand_more),
          label: const Text('Load more'),
        ),
      ),
    );
  }

  Widget _buildReportTile(Map<String, dynamic> d) {
    final id = d[r'$id'] as String;
    final hazard = d['hazardType'] as String? ?? 'Unknown';
    final lga = d['lga'] as String? ?? '';
    final ward = d['ward'] as String? ?? '';
    final status = d['status'] as String? ?? 'pending';
    final severity = d['severity'] as String? ?? '';
    String timeStr = '';
    final dt = parseTimestamp(d['submittedAt'] ?? d['createdAt']);
    if (dt != null) {
      timeStr = '${dt.day}/${dt.month}/${dt.year}';
    }

    final statusColor = _statusColors[status] ?? Colors.grey;
    final actions = _allowedActions(context, d);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        onTap: () => _showReportDetails(context, id, d),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.report_outlined, color: statusColor, size: 24),
        ),
        title: Text(
          hazard,
          style: GoogleFonts.lexend(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [ward, lga].where((s) => s.isNotEmpty).join(', '),
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
        trailing: actions.isEmpty
            ? null
            : PopupMenuButton<String>(
                onSelected: (action) => _updateStatus(id, action),
                itemBuilder: (_) => [
                  if (actions.contains('approved'))
                    const PopupMenuItem(
                      value: 'approved',
                      child: Text('Approve'),
                    ),
                  if (actions.contains('rejected'))
                    const PopupMenuItem(
                      value: 'rejected',
                      child: Text('Reject'),
                    ),
                  if (actions.contains('verified'))
                    const PopupMenuItem(
                      value: 'verified',
                      child: Text('Mark Verified'),
                    ),
                  if (actions.contains('pending'))
                    const PopupMenuItem(
                      value: 'pending',
                      child: Text('Reopen (reset to pending)'),
                    ),
                ],
              ),
        isThreeLine: true,
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
