import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:climate_app/features/verification/models/verification_report_model.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:climate_app/shared/widgets/custom_button.dart';
import 'package:google_fonts/google_fonts.dart';

class AlertsListScreen extends StatefulWidget {
  final String? initialCategory;

  const AlertsListScreen({super.key, this.initialCategory});

  @override
  State<AlertsListScreen> createState() => _AlertsListScreenState();
}

class _AlertsListScreenState extends State<AlertsListScreen> {
  int _selectedFilterIndex = 0;
  final List<String> _filters = [
    'All Alerts',
    'Floods',
    'Conflict',
    'Drought',
    'Fire',
    'Pests',
    'Erosion',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialCategory != null) {
      final index = _filters.indexWhere(
        (f) => f.toLowerCase() == widget.initialCategory!.toLowerCase(),
      );
      if (index != -1) {
        _selectedFilterIndex = index;
      } else if (widget.initialCategory == 'Pest/Disease') {
        _selectedFilterIndex = _filters.indexOf('Pests');
      } else if (widget.initialCategory == 'Flooding') {
        _selectedFilterIndex = _filters.indexOf('Floods');
      }
    }
  }

  List<VerificationReport> _filterReports(List<VerificationReport> allReports) {
    if (_selectedFilterIndex == 0) return allReports;
    final filter = _filters[_selectedFilterIndex];
    return allReports.where((report) {
      final hazard = report.type.toLowerCase();
      if (filter == 'Floods') return hazard.contains('flood');
      if (filter == 'Conflict') return hazard.contains('conflict');
      if (filter == 'Drought') return hazard.contains('drought');
      if (filter == 'Fire') return hazard.contains('fire');
      if (filter == 'Pests') return hazard.contains('pest');
      if (filter == 'Erosion') return hazard.contains('erosion');
      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Alert History',
          style: GoogleFonts.lexend(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list, color: AppColors.textPrimary),
            onPressed: () {},
          ),
        ],
        backgroundColor: AppColors.background.withValues(alpha: 0.95),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.grey.shade200, height: 1.0),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/report'),
        backgroundColor: AppColors.successGreen,
        child: const Icon(Icons.add_alert, color: Colors.black, size: 28),
      ),
      body: Consumer<ReportsStatusProvider>(
        builder: (context, provider, _) {
          return StreamBuilder<List<VerificationReport>>(
            stream: provider.reportsStatusStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              final allReports = snapshot.data ?? [];
              final filteredReports = _filterReports(allReports);

              return RefreshIndicator(
                onRefresh: () => provider.refreshReports(),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 80),
                  child: Column(
                    children: [
                      // Search Bar
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: 'Search location, hazard, or ID...',
                              hintStyle: GoogleFonts.lexend(
                                color: Colors.grey.shade400,
                              ),
                              prefixIcon: Icon(
                                Icons.search,
                                color: Colors.grey.shade400,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Meta Text
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'SYNC STATUS',
                              style: GoogleFonts.lexend(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade500,
                                letterSpacing: 1.0,
                              ),
                            ),
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: provider.isLoading
                                        ? Colors.orange
                                        : AppColors.successGreen,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  provider.isLoading
                                      ? 'Synchronizing...'
                                      : 'Online • Just now',
                                  style: GoogleFonts.lexend(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: provider.isLoading
                                        ? Colors.orange
                                        : AppColors.successGreen,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Filters
                      SizedBox(
                        height: 36,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          scrollDirection: Axis.horizontal,
                          itemCount: _filters.length,
                          separatorBuilder: (c, i) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final isSelected = _selectedFilterIndex == index;
                            return ChoiceChip(
                              label: Text(_filters[index]),
                              selected: isSelected,
                              onSelected: (v) =>
                                  setState(() => _selectedFilterIndex = index),
                              labelStyle: GoogleFonts.lexend(
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? Colors.black
                                    : Colors.grey.shade700,
                                fontSize: 12,
                              ),
                              selectedColor: AppColors.successGreen,
                              backgroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide(
                                  color: isSelected
                                      ? AppColors.successGreen
                                      : Colors.grey.shade200,
                                ),
                              ),
                              showCheckmark: false,
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 16),

                      if (filteredReports.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              'No alerts found for this category.',
                              style: GoogleFonts.lexend(color: Colors.grey),
                            ),
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            children: filteredReports.map((report) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _buildAlertCardFromReport(
                                  report,
                                  provider,
                                ),
                              );
                            }).toList(),
                          ),
                        ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildAlertCardFromReport(
    VerificationReport report,
    ReportsStatusProvider provider,
  ) {
    IconData icon = Icons.warning;
    Color color = Colors.orange;

    final hazard = report.type.toLowerCase();
    if (hazard.contains('flood')) {
      icon = Icons.flood;
      color = Colors.blue;
    } else if (hazard.contains('fire')) {
      icon = Icons.local_fire_department;
      color = AppColors.errorRed;
    } else if (hazard.contains('conflict')) {
      icon = Icons.shield;
      color = Colors.red;
    } else if (hazard.contains('pest')) {
      icon = Icons.bug_report;
      color = Colors.green;
    }

    final statusStr = report.status.displayName;
    Color statusColor = Colors.grey;
    if (report.status == ReportStatus.pending) statusColor = Colors.orange;
    if (report.status == ReportStatus.acknowledged) statusColor = Colors.blue;
    if (report.status == ReportStatus.resolved) {
      statusColor = AppColors.successGreen;
    }
    if (report.status == ReportStatus.rejected) statusColor = Colors.red;

    return _buildAlertCard(
      title: report.title,
      time: report.time,
      location: report.location,
      icon: icon,
      color: color,
      status: statusStr,
      statusColor: statusColor,
      report: report,
      provider: provider,
    );
  }

  Widget _buildAlertCard({
    required String title,
    required String time,
    required String location,
    required IconData icon,
    required Color color,
    String? severity,
    required String status,
    required Color statusColor,
    required VerificationReport report,
    required ReportsStatusProvider provider,
  }) {
    final isPending = report.status == ReportStatus.pending;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              children: [
                Container(width: 6, color: color),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, color: color, size: 24),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: GoogleFonts.lexend(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 2,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    time,
                                    style: GoogleFonts.lexend(
                                      fontSize: 12,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                location,
                                style: GoogleFonts.lexend(
                                  fontSize: 14,
                                  color: AppColors.textSecondary,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  if (severity != null)
                                    _buildTag(severity, color),
                                  _buildTag(status, statusColor),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Action buttons for pending alerts
          if (isPending)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: CustomButton(
                      onPressed: () async {
                        try {
                          await provider.rejectReport(report.id);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Report rejected')),
                            );
                          }
                        } on Exception catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                      text: 'Cannot confirm',
                      icon: Icons.close,
                      type: ButtonType.secondary,
                      foregroundColor: Colors.red,
                      borderColor: Colors.red,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CustomButton(
                      onPressed: () async {
                        try {
                          await provider.verifyReport(report.id);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Report confirmed')),
                            );
                          }
                        } on Exception catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                      text: 'Confirm this',
                      icon: Icons.check,
                      backgroundColor: AppColors.successGreen,
                      foregroundColor: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        text,
        style: GoogleFonts.lexend(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
