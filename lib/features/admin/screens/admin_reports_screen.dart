import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:climate_app/features/verification/widgets/report_verifications_section.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'dart:developer' as developer;
import 'package:climate_app/core/l10n/l10n.dart';
import 'package:climate_app/core/l10n/severity_label.dart';
import 'package:climate_app/core/constants/hazards.dart';
import 'package:climate_app/features/verification/models/verification_report_model.dart';

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
  LocalizedText? _error;

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
        setState(() => _error = (l) => l.adminReportsLoadError);
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

  /// Asks for a rejection reason (optional but encouraged; it is shown to the
  /// reporter). Returns null when the admin cancels, '' for no reason.
  Future<String?> _promptRejectionReason() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          context.l10n.staffRejectTitle,
          style: GoogleFonts.lexend(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          maxLength: 500,
          decoration: InputDecoration(
            labelText: context.l10n.adminReportsRejectReasonLabel,
            hintText: context.l10n.adminReportsRejectReasonHint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, controller.text.trim()),
            child: Text(
              context.l10n.reject,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    controller.dispose();
    return reason;
  }

  Future<void> _rejectWithReason(String reportId) async {
    final reason = await _promptRejectionReason();
    if (reason == null || !mounted) return;
    await _updateStatus(reportId, 'rejected', rejectionReason: reason);
  }

  Future<void> _updateStatus(
    String reportId,
    String newStatus, {
    String? rejectionReason,
  }) async {
    if (newStatus == 'rejected' && rejectionReason == null) {
      return _rejectWithReason(reportId);
    }
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
            if (newStatus == 'rejected' &&
                rejectionReason != null &&
                rejectionReason.isNotEmpty)
              'rejectionReason': rejectionReason,
          },
        );
      }
    } on Exception catch (e) {
      developer.log('Status update failed: $e', name: 'AdminReportsScreen');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.adminReportsStatusUpdateFailed(
                reportActionErrorMessage(
                  e,
                  context.l10n,
                  context: 'AdminReports',
                ),
              ),
            ),
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
              ? context.l10n.adminReportsReopened
              : context.l10n.adminReportsMarkedAs(
                  reportStatusLabelFor(context.l10n, newStatus),
                ),
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
        data['description'] as String? ?? context.l10n.noDescriptionProvided;
    final imageUrls =
        (data['imageUrls'] as List<dynamic>?)?.cast<String>() ?? [];
    final status = data['status'] as String? ?? 'pending';
    final rejectionReason = (data['rejectionReason'] as String?)?.trim();
    // Status changes are refused by the database for tech support (and for
    // staff on their own reports) — mirror guard_report_update.
    final actions = _allowedActions(context, data);
    final canChangeStatus = actions.isNotEmpty;
    final createdAt = data['submittedAt'] ?? data['createdAt'];
    String timeStr = '';
    final dt = parseTimestamp(createdAt);
    if (dt != null) {
      timeStr = localizedDateFormat(context, 'd/M/y H:mm').format(dt);
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
                        context.l10n.reportDetailsTitle,
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
                      _detailRow(
                        context.l10n.hazardType,
                        Hazard.labelFor(hazard, context.l10n),
                      ),
                      _detailRow(
                        context.l10n.reportViewSeverity,
                        severity.isEmpty
                            ? ''
                            : severityLabel(context.l10n, severity),
                      ),
                      _detailRow(
                        context.l10n.alertDetailStatus,
                        reportStatusLabelFor(context.l10n, status),
                        _statusColors[status],
                      ),
                      _detailRow(context.l10n.adminReportsDateTime, timeStr),
                      _detailRow(context.l10n.adminReportsLga, lga),
                      _detailRow(context.l10n.wardLabel, ward),
                      _detailRow(
                        context.l10n.adminReportsLocationDetails,
                        locationDetails,
                      ),
                      if (status == 'rejected')
                        _detailRow(
                          context.l10n.adminReportsRejectionReason,
                          (rejectionReason == null || rejectionReason.isEmpty)
                              ? context.l10n.adminReportsNoReason
                              : rejectionReason,
                        ),
                      const SizedBox(height: 16),
                      Text(
                        context.l10n.descriptionLabel,
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
                          context.l10n.adminReportsImages,
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
                      // Confirmations / disputes with their comments.
                      ReportVerificationsSection(reportId: id),
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
                              label: Text(context.l10n.staffApprove),
                            ),
                          if (actions.contains('rejected'))
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () {
                                // Close the sheet first: the reason dialog
                                // opens on the screen.
                                Navigator.pop(context);
                                _rejectWithReason(id);
                              },
                              icon: const Icon(Icons.close, size: 18),
                              label: Text(context.l10n.reject),
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
                              label: Text(
                                context.l10n.adminReportsMarkVerified,
                              ),
                            ),
                          if (actions.contains('pending'))
                            OutlinedButton.icon(
                              onPressed: () {
                                _updateStatus(id, 'pending');
                                Navigator.pop(context);
                              },
                              icon: const Icon(Icons.refresh, size: 18),
                              label: Text(context.l10n.adminReportsReopen),
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
          context.l10n.reportsOverview,
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
                            s == 'all'
                                ? context.l10n.contactsFilterAll
                                : reportStatusLabelFor(context.l10n, s),
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
                    _error?.call(context.l10n) ??
                        context.l10n.adminReportsEmpty,
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
                      child: Text(context.l10n.retry),
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
            child: Text(context.l10n.adminReportsLoadMoreError),
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
          label: Text(context.l10n.adminReportsLoadMore),
        ),
      ),
    );
  }

  Widget _buildReportTile(Map<String, dynamic> d) {
    final id = d[r'$id'] as String;
    final hazard = Hazard.labelFor(d['hazardType'], context.l10n);
    final lga = d['lga'] as String? ?? '';
    final ward = d['ward'] as String? ?? '';
    final status = d['status'] as String? ?? 'pending';
    final severity = d['severity'] as String? ?? '';
    String timeStr = '';
    final dt = parseTimestamp(d['submittedAt'] ?? d['createdAt']);
    if (dt != null) {
      timeStr = localizedDateFormat(context, 'd/M/y').format(dt);
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
                _chip(reportStatusLabelFor(context.l10n, status), statusColor),
                if (severity.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  _chip(severityLabel(context.l10n, severity), Colors.purple),
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
                    PopupMenuItem(
                      value: 'approved',
                      child: Text(context.l10n.staffApprove),
                    ),
                  if (actions.contains('rejected'))
                    PopupMenuItem(
                      value: 'rejected',
                      child: Text(context.l10n.reject),
                    ),
                  if (actions.contains('verified'))
                    PopupMenuItem(
                      value: 'verified',
                      child: Text(context.l10n.adminReportsMarkVerified),
                    ),
                  if (actions.contains('pending'))
                    PopupMenuItem(
                      value: 'pending',
                      child: Text(context.l10n.adminReportsReopenReset),
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
