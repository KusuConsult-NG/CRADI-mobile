import 'package:climate_app/features/verification/widgets/verification_request_badge.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:climate_app/core/constants/hazards.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:climate_app/features/verification/models/verification_report_model.dart';
import 'package:climate_app/shared/widgets/shimmer_loading.dart';
import 'package:climate_app/core/l10n/l10n.dart';
import 'package:climate_app/core/utils/screen_security.dart';

/// My Reports screen with Active / History tabs.
/// Active = pending + verified | History = approved + rejected
class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key});

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen>
    with SingleTickerProviderStateMixin, ScreenSecurityMixin<MyReportsScreen> {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  /// User and [ReportsStatusProvider.userDataGeneration] the list was last
  /// loaded for. The list is (re)loaded on first build, when another user
  /// signs in, and after the provider dropped its cached lists (sign-in /
  /// sign-out), which would otherwise leave this screen empty.
  String? _loadedUid;
  int? _loadedGen;

  void _reloadIfStale(ReportsStatusProvider provider, String uid) {
    final gen = provider.userDataGeneration;
    if (uid == _loadedUid && gen == _loadedGen) return;
    _loadedUid = uid;
    _loadedGen = gen;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshMyReports();
    });
  }

  /// Loads every page of the user's reports (the Active / History split
  /// is done client-side, so a single page would hide older reports).
  Future<void> _refreshMyReports() async {
    final uid = context.read<AuthProvider>().currentUser?.id;
    if (uid != null) {
      await context.read<ReportsStatusProvider>().fetchAllPages(userId: uid);
    }
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
        title: Text(
          context.l10n.myReports,
          style: GoogleFonts.lexend(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppColors.background,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.successGreen,
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: GoogleFonts.lexend(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          tabs: [
            Tab(text: context.l10n.myReportsTabActive),
            Tab(text: context.l10n.myReportsTabHistory),
          ],
        ),
      ),
      body: Consumer2<ReportsStatusProvider, AuthProvider>(
        builder: (context, provider, auth, _) {
          final uid = auth.currentUser?.id;
          if (uid == null) {
            return Center(
              child: Text(
                context.l10n.myReportsSignIn,
                style: GoogleFonts.lexend(color: AppColors.textSecondary),
              ),
            );
          }

          _reloadIfStale(provider, uid);

          // Get ALL user reports (status: null means all)
          final allReports = provider.getReports(null, userId: uid);
          final isLoading = provider.isLoading(null, userId: uid);
          final error = provider.errorFor(null, userId: uid);

          final activeReports = allReports.where((r) => r.isActive).toList();
          final historyReports = allReports.where((r) => r.isHistory).toList();

          return TabBarView(
            controller: _tabController,
            children: [
              _buildReportList(
                activeReports,
                isLoading,
                context.l10n.myReportsEmptyActiveTitle,
                context.l10n.myReportsEmptyActiveBody,
                error,
              ),
              _buildReportList(
                historyReports,
                isLoading,
                context.l10n.myReportsEmptyHistoryTitle,
                context.l10n.myReportsEmptyHistoryBody,
                error,
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'my_reports_fab',
        onPressed: () => context.push('/report'),
        backgroundColor: AppColors.successGreen,
        icon: const Icon(Icons.add, color: Colors.black),
        label: Text(
          context.l10n.myReportsNewReport,
          style: GoogleFonts.lexend(
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
      ),
    );
  }

  Widget _buildReportList(
    List<VerificationReport> reports,
    bool isLoading,
    String emptyTitle,
    String emptySubtitle,
    LocalizedText? error,
  ) {
    if (isLoading && reports.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ShimmerSkeletons.card(height: 90),
            ShimmerSkeletons.card(height: 90),
            ShimmerSkeletons.card(height: 90),
          ],
        ),
      );
    }

    if (reports.isEmpty && error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 56, color: Colors.red.shade200),
              const SizedBox(height: 12),
              Text(
                error(context.l10n),
                textAlign: TextAlign.center,
                style: GoogleFonts.lexend(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _refreshMyReports,
                icon: const Icon(Icons.refresh),
                label: Text(context.l10n.retry),
              ),
            ],
          ),
        ),
      );
    }

    if (reports.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.description_outlined,
                  size: 64,
                  color: Colors.grey.shade400,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                emptyTitle,
                style: GoogleFonts.lexend(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                emptySubtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.lexend(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshMyReports,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: reports.length + (error != null ? 1 : 0),
        separatorBuilder: (_, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == reports.length) {
            return Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade300),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error!(context.l10n),
                    style: GoogleFonts.lexend(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _refreshMyReports,
                  child: Text(context.l10n.retry),
                ),
              ],
            );
          }
          final report = reports[index];
          return _buildReportCard(report);
        },
      ),
    );
  }

  Widget _buildReportCard(VerificationReport report) {
    final statusColor = _getStatusColor(report.status);
    final hazardColor = _getHazardColor(report.type);

    return GestureDetector(
      onTap: () => context.push('/report-view', extra: report),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 5, color: hazardColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: hazardColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _getHazardIcon(report.type),
                          color: hazardColor,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              report.displayTitle(context.l10n),
                              style: GoogleFonts.lexend(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (report.isVerificationRequest) ...[
                              const SizedBox(height: 4),
                              const VerificationRequestBadge(),
                            ],
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on,
                                  size: 12,
                                  color: Colors.grey.shade500,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    report.displayLocation(context.l10n),
                                    style: GoogleFonts.lexend(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            if (report.status == ReportStatus.rejected &&
                                report.rejectionReason != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                context.l10n.myReportsRejectionReason(
                                  report.rejectionReason!,
                                ),
                                style: GoogleFonts.lexend(
                                  fontSize: 12,
                                  color: Colors.red.shade700,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            // The chip's colour also encodes the status, so
                            // the screen reader is given the meaning in words.
                            child: Semantics(
                              label: context.l10n.a11yStatusLabel(
                                report.status.label(context.l10n),
                              ),
                              excludeSemantics: true,
                              child: Text(
                                report.status.label(context.l10n),
                                style: GoogleFonts.lexend(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: statusColor,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            report.displayTime(context.l10n),
                            style: GoogleFonts.lexend(
                              fontSize: 10,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  Color _getStatusColor(ReportStatus status) {
    switch (status) {
      case ReportStatus.pending:
        return Colors.orange;
      case ReportStatus.verified:
        return AppColors.successGreen;
      case ReportStatus.approved:
        return Colors.blue;
      case ReportStatus.rejected:
        return Colors.red;
    }
  }

  Color _getHazardColor(String type) => Hazard.colorFor(type);

  IconData _getHazardIcon(String type) => Hazard.iconFor(type);
}
