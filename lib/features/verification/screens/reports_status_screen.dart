import 'dart:io';

import 'package:climate_app/core/constants/hazards.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:climate_app/features/verification/models/verification_report_model.dart';
import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/l10n/app_localizations.dart';

class ReportsStatusScreen extends StatefulWidget {
  const ReportsStatusScreen({super.key, this.initialTab});

  /// Tab to open on: 'pending' | 'verified' | 'approved' | 'rejected'
  /// (e.g. from the `tab` query parameter). Unknown values open Pending.
  final String? initialTab;

  /// Tab order, matching [ReportStatus] names.
  static const List<String> tabs = [
    'pending',
    'verified',
    'approved',
    'rejected',
  ];

  /// Index of [tab] in [tabs], defaulting to 0.
  static int tabIndexFor(String? tab) {
    final i = tabs.indexOf((tab ?? '').toLowerCase());
    return i < 0 ? 0 : i;
  }

  @override
  State<ReportsStatusScreen> createState() => _ReportsStatusScreenState();
}

class _ReportsStatusScreenState extends State<ReportsStatusScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: ReportsStatusScreen.tabs.length,
      vsync: this,
      initialIndex: ReportsStatusScreen.tabIndexFor(widget.initialTab),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      final isUser = auth.userRole == UserRole.user;
      context.read<ReportsStatusProvider>().refreshReports(
        userId: isUser ? auth.currentUser?.id : null,
      );
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            size: 20,
            color: AppColors.textPrimary,
          ),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/dashboard');
            }
          },
        ),
        title: Text(
          AppLocalizations.of(context)!.reportsStatus,
          style: GoogleFonts.lexend(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppColors.background.withValues(alpha: 0.95),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primaryRed,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primaryRed,
          labelStyle: GoogleFonts.lexend(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: GoogleFonts.lexend(
            fontSize: 14,
            fontWeight: FontWeight.normal,
          ),
          tabs: [
            Tab(text: AppLocalizations.of(context)!.pending),
            Tab(text: AppLocalizations.of(context)!.verified),
            Tab(text: AppLocalizations.of(context)!.approved),
            Tab(text: AppLocalizations.of(context)!.rejected),
          ],
        ),
      ),
      body: Consumer<ReportsStatusProvider>(
        builder: (context, provider, _) {
          return TabBarView(
            controller: _tabController,
            children: [
              _buildReportsList(provider, ReportStatus.pending),
              _buildReportsList(provider, ReportStatus.verified),
              _buildReportsList(provider, ReportStatus.approved),
              _buildReportsList(provider, ReportStatus.rejected),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'reports_status_fab',
        onPressed: _showReportGenerationDialog,
        backgroundColor: AppColors.primaryRed,
        icon: const Icon(Icons.download, color: Colors.white),
        label: Text(
          AppLocalizations.of(context)!.generateReport,
          style: GoogleFonts.lexend(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildReportsList(
    ReportsStatusProvider provider,
    ReportStatus status,
  ) {
    final auth = context.read<AuthProvider>();
    final isUser = auth.userRole == UserRole.user;
    final uid = isUser ? auth.currentUser?.id : null;

    final reports = provider.getReports(status, userId: uid);
    final isLoading = provider.isLoading(status, userId: uid);
    final hasMore = provider.hasMore(status, userId: uid);
    final error = provider.errorFor(status, userId: uid);

    if (reports.isEmpty && isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (reports.isEmpty && error != null) {
      return _buildErrorState(
        error,
        () => provider.fetchReports(status: status, userId: uid),
      );
    }

    if (reports.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.noReportsStatus(status.displayName),
              style: GoogleFonts.lexend(
                fontSize: 16,
                color: AppColors.textSecondary,
              ),
            ),
            ElevatedButton(
              onPressed: () {
                provider.fetchReports(status: status, userId: uid);
              },
              child: Text(AppLocalizations.of(context)!.refresh),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await provider.fetchReports(status: status, userId: uid);
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification scrollInfo) {
          if (!isLoading &&
              hasMore &&
              error == null &&
              scrollInfo.metrics.pixels >=
                  scrollInfo.metrics.maxScrollExtent - 200) {
            provider.fetchReports(loadMore: true, status: status, userId: uid);
          }
          return false;
        },
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: reports.length + ((hasMore || error != null) ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            if (index == reports.length) {
              if (error != null) {
                return _buildInlineError(
                  error,
                  () => provider.fetchReports(
                    loadMore: true,
                    status: status,
                    userId: uid,
                  ),
                );
              }
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            final report = reports[index];
            return _buildReportCard(report, provider);
          },
        ),
      ),
    );
  }

  Widget _buildReportCard(
    VerificationReport report,
    ReportsStatusProvider provider,
  ) {
    final auth = context.read<AuthProvider>();
    final currentUserId = auth.currentUser?.id;
    // Mirrors the database rules: peer votes by approved verifier roles
    // (EWMs only in their own ward, never on their own report); approve /
    // reject / reopen by ewv, ewr, ldp_coordinator, project_staff, admin.
    final canVerify =
        auth.canVoteOn(
          reporterId: report.reporterId,
          reportWard: report.ward,
          reportLga: report.lga,
        ) &&
        !provider.hasVotedOn(report.id);
    final isStaff = auth.canManageReportStatus(reporterId: report.reporterId);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _getIconBgColor(report.iconColor),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Hazard.iconFor(report.type),
                  color: _getIconColor(report.iconColor),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.title,
                      style: GoogleFonts.lexend(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppLocalizations.of(context)!.reportedBy(report.reporter),
                      style: GoogleFonts.lexend(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _buildStatusBadge(report.status),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.location_on,
                size: 14,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  report.location,
                  style: GoogleFonts.lexend(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 12),
              const Icon(
                Icons.schedule,
                size: 14,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                report.time,
                style: GoogleFonts.lexend(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: () {
                  context.push('/report-view', extra: report);
                },
                child: Text(
                  AppLocalizations.of(context)!.viewDetails,
                  style: GoogleFonts.lexend(
                    color: AppColors.primaryRed,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              Flexible(
                flex: 4,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (canVerify &&
                        report.status == ReportStatus.pending &&
                        report.reporterId != currentUserId) ...[
                      ElevatedButton(
                        onPressed: () => _runAction(
                          () => provider.verifyReport(report.id),
                          AppLocalizations.of(context)!.reportVerified,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryRed,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(AppLocalizations.of(context)!.verifyReport),
                      ),
                      // A peer "no" vote: it does not reject the report.
                      OutlinedButton(
                        onPressed: () => _runAction(
                          () => provider.disputeReport(report.id),
                          'Dispute recorded. Staff will review the report.',
                          successColor: Colors.orange,
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.orange),
                          foregroundColor: Colors.orange.shade800,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Dispute'),
                      ),
                    ],
                    if (isStaff &&
                        report.status == ReportStatus.verified &&
                        report.reporterId != currentUserId)
                      ElevatedButton(
                        onPressed: () => _runAction(
                          () => provider.approveReport(report.id),
                          AppLocalizations.of(context)!.reportResolvedItem,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          AppLocalizations.of(context)!.markResolved,
                          style: GoogleFonts.lexend(fontSize: 13),
                        ),
                      ),
                    if (isStaff &&
                        (report.status == ReportStatus.pending ||
                            report.status == ReportStatus.verified) &&
                        report.reporterId != currentUserId)
                      OutlinedButton(
                        onPressed: () => _confirmStaffReject(report, provider),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                          foregroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          AppLocalizations.of(context)!.reject,
                          style: GoogleFonts.lexend(fontSize: 13),
                        ),
                      ),
                    if (isStaff &&
                        report.status != ReportStatus.pending &&
                        report.reporterId != currentUserId)
                      OutlinedButton(
                        onPressed: () => _runAction(
                          () => provider.moveBackToPending(report.id),
                          report.status == ReportStatus.verified
                              ? AppLocalizations.of(context)!.reportMovedPending
                              : AppLocalizations.of(
                                  context,
                                )!.reportReopenedPending,
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.grey.shade300),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          AppLocalizations.of(context)!.reopen,
                          style: GoogleFonts.lexend(fontSize: 13),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Runs a report action, then shows [successMessage] or the error.
  Future<void> _runAction(
    Future<void> Function() action,
    String successMessage, {
    Color? successColor,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(
        SnackBar(
          content: Text(successMessage, style: GoogleFonts.lexend()),
          backgroundColor: successColor ?? AppColors.successGreen,
        ),
      );
    } on Exception catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is VerificationRefusedException
                ? e.message
                : ErrorHandler.handleError(e, context: 'Report'),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Senior-staff rejection: asks for a reason, then sets the report to
  /// rejected (the database enforces who may do this and audits it).
  Future<void> _confirmStaffReject(
    VerificationReport report,
    ReportsStatusProvider provider,
  ) async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          'Reject report?',
          style: GoogleFonts.lexend(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: reasonController,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason (required)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () {
              final text = reasonController.text.trim();
              if (text.isNotEmpty) Navigator.pop(c, text);
            },
            child: Text(
              AppLocalizations.of(context)!.reject,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    reasonController.dispose();
    if (reason == null || !mounted) return;
    await _runAction(
      () => provider.staffRejectReport(report.id, reason: reason),
      AppLocalizations.of(context)!.reportRejectedItem,
      successColor: Colors.red,
    );
  }

  Widget _buildErrorState(String message, VoidCallback onRetry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 56, color: Colors.red.shade200),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.lexend(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineError(String message, VoidCallback onRetry) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade300, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.lexend(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(ReportStatus status) {
    Color color;
    switch (status) {
      case ReportStatus.pending:
        color = Colors.orange;
        break;
      case ReportStatus.verified:
        color = AppColors.successGreen;
        break;
      case ReportStatus.approved:
        color = Colors.blue;
        break;
      case ReportStatus.rejected:
        color = Colors.red;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        status.displayName,
        style: GoogleFonts.lexend(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  void _showReportGenerationDialog() {
    final provider = Provider.of<ReportsStatusProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          AppLocalizations.of(context)!.generateReport,
          style: GoogleFonts.lexend(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context)!.selectStatusExport,
              style: GoogleFonts.lexend(fontSize: 14),
            ),
            const SizedBox(height: 12),
            _buildExportOption(
              c,
              provider,
              AppLocalizations.of(context)!.allReports,
              null,
            ),
            _buildExportOption(
              c,
              provider,
              AppLocalizations.of(context)!.pendingOnly,
              ReportStatus.pending,
            ),
            _buildExportOption(
              c,
              provider,
              AppLocalizations.of(context)!.verifiedOnly,
              ReportStatus.verified,
            ),
            _buildExportOption(
              c,
              provider,
              AppLocalizations.of(context)!.approvedOnly,
              ReportStatus.approved,
            ),
            _buildExportOption(
              c,
              provider,
              'Rejected only',
              ReportStatus.rejected,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
        ],
      ),
    );
  }

  Widget _buildExportOption(
    BuildContext dialogContext,
    ReportsStatusProvider provider,
    String label,
    ReportStatus? status,
  ) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: GoogleFonts.lexend(fontSize: 14)),
      trailing: const Icon(Icons.download, size: 20),
      onTap: () {
        Navigator.pop(dialogContext);
        _exportCsv(provider, status);
      },
    );
  }

  /// Generates the CSV, saves it to the app documents directory and opens
  /// the share sheet (on web the CSV is copied to the clipboard).
  Future<void> _exportCsv(
    ReportsStatusProvider provider,
    ReportStatus? status,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Preparing export…')));
    try {
      final csv = await provider.generateCSVReport(status);
      if (kIsWeb) {
        await Clipboard.setData(ClipboardData(text: csv));
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('CSV copied to the clipboard.')),
          );
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File(
        p.join(dir.path, 'cradi_reports_${status?.name ?? 'all'}_$stamp.csv'),
      );
      await file.writeAsString(csv, flush: true);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Report saved to ${file.path}'),
            duration: const Duration(seconds: 6),
          ),
        );
      try {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'text/csv')],
            subject: 'CRADI reports export',
          ),
        );
      } on Exception catch (e) {
        // Saved already; sharing is optional.
        ErrorHandler.logError(e, context: 'ReportsExport.share');
      }
    } on Exception catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(ErrorHandler.handleError(e, context: 'Export')),
            backgroundColor: Colors.red,
          ),
        );
    }
  }

  Color _getIconColor(String colorName) => SeverityColors.fromName(colorName);

  Color _getIconBgColor(String colorName) {
    return _getIconColor(colorName).withValues(alpha: 0.1);
  }
}
