import 'package:climate_app/core/theme/app_colors.dart';
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
  const ReportsStatusScreen({super.key});

  @override
  State<ReportsStatusScreen> createState() => _ReportsStatusScreenState();
}

class _ReportsStatusScreenState extends State<ReportsStatusScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      final isUser = auth.userRole == UserRole.user;
      context.read<ReportsStatusProvider>().refreshReports(
        userId: isUser ? auth.currentUser?.uid : null,
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
    final uid = isUser ? auth.currentUser?.uid : null;

    final reports = provider.getReports(status, userId: uid);
    final isLoading = provider.isLoading(status, userId: uid);
    final hasMore = provider.hasMore(status, userId: uid);

    if (reports.isEmpty && isLoading) {
      return const Center(child: CircularProgressIndicator());
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
              scrollInfo.metrics.pixels == scrollInfo.metrics.maxScrollExtent) {
            provider.fetchReports(loadMore: true, status: status, userId: uid);
          }
          return false;
        },
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: reports.length + (hasMore ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            if (index == reports.length) {
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
    final currentUserId = auth.currentUser?.uid;
    final role = auth.userRole;
    // Peer verification is limited to verifier roles (see firestore.rules
    // isVerifier); status management to staff.
    final canVerify = const {
      UserRole.ewm,
      UserRole.ewv,
      UserRole.ewr,
      UserRole.admin,
    }.contains(role);
    final isStaff = role != null && role != UserRole.user;
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
                  _getIconData(report.iconName),
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
              if (canVerify &&
                  report.status == ReportStatus.pending &&
                  report.reporterId != currentUserId) ...[
                ElevatedButton(
                  onPressed: () async {
                    final scaffoldMessenger = ScaffoldMessenger.of(context);
                    final verifiedMsg = AppLocalizations.of(
                      context,
                    )!.reportVerified;
                    try {
                      await provider.verifyReport(report.id);
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            verifiedMsg,
                            style: GoogleFonts.lexend(),
                          ),
                          backgroundColor: AppColors.successGreen,
                        ),
                      );
                    } on Exception catch (e) {
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            e is VerificationRefusedException
                                ? e.message
                                : ErrorHandler.handleError(
                                    e,
                                    context: 'Report',
                                  ),
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
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
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () async {
                    final scaffoldMessenger = ScaffoldMessenger.of(context);
                    final rejectedMsg = AppLocalizations.of(
                      context,
                    )!.reportRejectedItem;
                    try {
                      await provider.rejectReport(report.id);
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            rejectedMsg,
                            style: GoogleFonts.lexend(),
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    } on Exception catch (e) {
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            e is VerificationRefusedException
                                ? e.message
                                : ErrorHandler.handleError(
                                    e,
                                    context: 'Report',
                                  ),
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    foregroundColor: Colors.red,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(AppLocalizations.of(context)!.reject),
                ),
              ],
              if (isStaff &&
                  report.status == ReportStatus.verified &&
                  report.reporterId != currentUserId) ...[
                ElevatedButton(
                  onPressed: () async {
                    final scaffoldMessenger = ScaffoldMessenger.of(context);
                    final resolvedMsg = AppLocalizations.of(
                      context,
                    )!.reportResolvedItem;
                    try {
                      await provider.approveReport(report.id);
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            resolvedMsg,
                            style: GoogleFonts.lexend(),
                          ),
                          backgroundColor: AppColors.successGreen,
                        ),
                      );
                    } on Exception catch (e) {
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            e is VerificationRefusedException
                                ? e.message
                                : ErrorHandler.handleError(
                                    e,
                                    context: 'Report',
                                  ),
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
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
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    provider.moveBackToPending(report.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          AppLocalizations.of(context)!.reportMovedPending,
                          style: GoogleFonts.lexend(),
                        ),
                      ),
                    );
                  },
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
              if (isStaff &&
                  report.status == ReportStatus.approved &&
                  report.reporterId != currentUserId) ...[
                OutlinedButton(
                  onPressed: () {
                    provider.moveBackToPending(report.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          AppLocalizations.of(context)!.reportReopenedPending,
                          style: GoogleFonts.lexend(),
                        ),
                      ),
                    );
                  },
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
            ],
          ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.csvExportWeb,
              style: GoogleFonts.lexend(),
            ),
            backgroundColor: AppColors.textSecondary,
          ),
        );
      },
    );
  }

  Color _getIconColor(String colorName) {
    switch (colorName) {
      case 'orange':
        return Colors.orange;
      case 'blue':
        return Colors.blue;
      case 'red':
        return AppColors.errorRed;
      case 'green':
        return AppColors.successGreen;
      default:
        return Colors.grey;
    }
  }

  Color _getIconBgColor(String colorName) {
    return _getIconColor(colorName).withValues(alpha: 0.1);
  }

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'pest_control':
        return Icons.pest_control;
      case 'water_drop':
        return Icons.water_drop;
      case 'water':
        return Icons.water;
      case 'local_fire_department':
        return Icons.local_fire_department;
      default:
        return Icons.warning;
    }
  }
}
