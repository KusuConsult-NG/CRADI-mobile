import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/features/verification/models/verification_report_model.dart';
import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

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
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Reports Status',
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
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Acknowledged'),
            Tab(text: 'Resolved'),
            Tab(text: 'Rejected'),
          ],
        ),
      ),
      body: Consumer<ReportsStatusProvider>(
        builder: (context, provider, _) {
          return TabBarView(
            controller: _tabController,
            children: [
              _buildReportsList(provider, ReportStatus.pending),
              _buildReportsList(provider, ReportStatus.acknowledged),
              _buildReportsList(provider, ReportStatus.resolved),
              _buildReportsList(provider, ReportStatus.rejected),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showReportGenerationDialog,
        backgroundColor: AppColors.primaryRed,
        icon: const Icon(Icons.download, color: Colors.white),
        label: Text(
          'Generate Report',
          style: GoogleFonts.lexend(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildReportsList(
    ReportsStatusProvider provider,
    ReportStatus status,
  ) {
    return StreamBuilder<List<VerificationReport>>(
      stream: provider.getReportsStreamByStatus(status),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
                const SizedBox(height: 16),
                Text(
                  'Error loading reports',
                  style: GoogleFonts.lexend(
                    fontSize: 16,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '${snapshot.error}',
                  style: GoogleFonts.lexend(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final reports = snapshot.data ?? [];

        if (reports.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 64,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 16),
                Text(
                  'No ${status.displayName} Reports',
                  style: GoogleFonts.lexend(
                    fontSize: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: reports.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final report = reports[index];
            return _buildReportCard(report, provider);
          },
        );
      },
    );
  }

  Widget _buildReportCard(
    VerificationReport report,
    ReportsStatusProvider provider,
  ) {
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
                      'Reported by ${report.reporter}',
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
              Text(
                report.location,
                style: GoogleFonts.lexend(
                  fontSize: 12,
                  color: AppColors.textSecondary,
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
                  context.push('/report/details');
                },
                child: Text(
                  'View Details',
                  style: GoogleFonts.lexend(
                    color: AppColors.primaryRed,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              if (report.status == ReportStatus.pending) ...[
                ElevatedButton(
                  onPressed: () async {
                    final scaffoldMessenger = ScaffoldMessenger.of(context);
                    try {
                      await provider.verifyReport(report.id);
                      if (context.mounted) {
                        scaffoldMessenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              'Report verified and moved to Acknowledged',
                              style: GoogleFonts.lexend(),
                            ),
                            backgroundColor: AppColors.successGreen,
                          ),
                        );
                      }
                    } on Exception catch (e) {
                      if (context.mounted) {
                        scaffoldMessenger.showSnackBar(
                          SnackBar(
                            content: Text('Error: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
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
                  child: const Text('Verify'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () async {
                    final scaffoldMessenger = ScaffoldMessenger.of(context);
                    try {
                      await provider.rejectReport(report.id);
                      if (context.mounted) {
                        scaffoldMessenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              'Report rejected',
                              style: GoogleFonts.lexend(),
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    } on Exception catch (e) {
                      if (context.mounted) {
                        scaffoldMessenger.showSnackBar(
                          SnackBar(
                            content: Text('Error: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    foregroundColor: Colors.red,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Reject'),
                ),
              ],
              if (report.status == ReportStatus.acknowledged) ...[
                Expanded(
                  flex: 3,
                  child: ElevatedButton(
                    onPressed: () async {
                      final scaffoldMessenger = ScaffoldMessenger.of(context);
                      try {
                        await provider.resolveReport(report.id);
                        if (context.mounted) {
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                'Report marked as Resolved',
                                style: GoogleFonts.lexend(),
                              ),
                              backgroundColor: AppColors.successGreen,
                            ),
                          );
                        }
                      } on Exception catch (e) {
                        if (context.mounted) {
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Mark Resolved'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: OutlinedButton(
                    onPressed: () {
                      provider.moveBackToPending(report.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Report moved back to Pending',
                            style: GoogleFonts.lexend(),
                          ),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Reopen'),
                  ),
                ),
              ],
              if (report.status == ReportStatus.resolved) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      provider.moveBackToPending(report.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Report reopened and moved to Pending',
                            style: GoogleFonts.lexend(),
                          ),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Reopen'),
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
      case ReportStatus.acknowledged:
        color = AppColors.successGreen;
        break;
      case ReportStatus.resolved:
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
          'Generate Report',
          style: GoogleFonts.lexend(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select status to export:',
              style: GoogleFonts.lexend(fontSize: 14),
            ),
            const SizedBox(height: 12),
            _buildExportOption(c, provider, 'All Reports', null),
            _buildExportOption(
              c,
              provider,
              'Pending Only',
              ReportStatus.pending,
            ),
            _buildExportOption(
              c,
              provider,
              'Acknowledged Only',
              ReportStatus.acknowledged,
            ),
            _buildExportOption(
              c,
              provider,
              'Resolved Only',
              ReportStatus.resolved,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
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
              'CSV export available on web version',
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
