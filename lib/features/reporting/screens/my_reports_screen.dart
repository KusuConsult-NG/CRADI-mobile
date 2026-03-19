import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:climate_app/features/verification/models/verification_report_model.dart';
import 'package:climate_app/shared/widgets/shimmer_loading.dart';

/// My Reports screen with Active / History tabs.
/// Active = pending + verified | History = approved + rejected
class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key});

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshMyReports();
    });
  }

  void _refreshMyReports() {
    final uid = context.read<AuthProvider>().currentUser?.uid;
    if (uid != null) {
      context.read<ReportsStatusProvider>().refreshReports(userId: uid);
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
          'My Reports',
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
          tabs: const [
            Tab(text: 'Active'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: Consumer2<ReportsStatusProvider, AuthProvider>(
        builder: (context, provider, auth, _) {
          final uid = auth.currentUser?.uid;
          if (uid == null) {
            return Center(
              child: Text(
                'Please sign in to view your reports.',
                style: GoogleFonts.lexend(color: AppColors.textSecondary),
              ),
            );
          }

          // Get ALL user reports (status: null means all)
          final allReports = provider.getReports(null, userId: uid);
          final isLoading = provider.isLoading(null, userId: uid);

          final activeReports =
              allReports.where((r) => r.isActive).toList();
          final historyReports =
              allReports.where((r) => r.isHistory).toList();

          return TabBarView(
            controller: _tabController,
            children: [
              _buildReportList(activeReports, isLoading, 'No active reports',
                  'Reports you submit will appear here while being verified.'),
              _buildReportList(historyReports, isLoading, 'No report history',
                  'Your approved and rejected reports will appear here.'),
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
          'New Report',
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
      onRefresh: () async => _refreshMyReports(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: reports.length,
        separatorBuilder: (_, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
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
                              report.title,
                              style: GoogleFonts.lexend(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
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
                                    report.location,
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
                            child: Text(
                              report.status.displayName,
                              style: GoogleFonts.lexend(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            report.time,
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

  Color _getHazardColor(String type) {
    switch (type.toLowerCase()) {
      case 'flooding':
      case 'flood':
        return AppColors.hazardFlood;
      case 'drought':
        return AppColors.hazardDrought;
      case 'fire':
      case 'wildfire':
        return AppColors.hazardFire;
      case 'pest/disease':
      case 'pest':
        return AppColors.hazardPest;
      case 'erosion':
        return AppColors.hazardErosion;
      case 'conflict':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  IconData _getHazardIcon(String type) {
    switch (type.toLowerCase()) {
      case 'flooding':
      case 'flood':
        return Icons.flood;
      case 'drought':
        return Icons.wb_sunny;
      case 'fire':
      case 'wildfire':
        return Icons.local_fire_department;
      case 'pest/disease':
      case 'pest':
        return Icons.bug_report;
      case 'erosion':
        return Icons.landscape;
      case 'conflict':
        return Icons.shield;
      default:
        return Icons.warning;
    }
  }
}
