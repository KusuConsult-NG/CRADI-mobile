import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:climate_app/features/verification/models/verification_report_model.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart'
    show SeverityLevel, normalizeSeverity;

import 'package:climate_app/shared/widgets/custom_button.dart';
import 'package:climate_app/shared/widgets/shimmer_loading.dart';
import 'package:climate_app/shared/widgets/custom_toast.dart';
import 'package:climate_app/shared/widgets/animated_list_item.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:climate_app/core/services/supabase_service.dart'
    show parseTimestamp;
import 'package:climate_app/features/alerts/providers/alerts_provider.dart';
import 'package:climate_app/features/alerts/screens/alert_severity.dart';
import 'package:climate_app/features/profile/providers/profile_provider.dart';

class AlertsListScreen extends StatefulWidget {
  final String? initialCategory;

  const AlertsListScreen({super.key, this.initialCategory});

  @override
  State<AlertsListScreen> createState() => _AlertsListScreenState();
}

class _AlertsListScreenState extends State<AlertsListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  int _selectedFilterIndex = 0;

  /// Canonical severity to show (see [normalizeSeverity]); null = all.
  String? _severityFilter;
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
    // A hazard category (from the dashboard) opens the report history.
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialCategory != null ? 1 : 0,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted) setState(() {});
    });
    _searchController.addListener(() {
      final q = _searchController.text.trim().toLowerCase();
      if (q != _query) setState(() => _query = q);
    });
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
    // Initial fetch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ReportsStatusProvider>().fetchReports(status: null);
      context.read<AlertsProvider>().fetchAlerts();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesQuery(Iterable<Object?> fields) {
    if (_query.isEmpty) return true;
    return fields.any(
      (f) => f != null && f.toString().toLowerCase().contains(_query),
    );
  }

  List<VerificationReport> _filterReports(List<VerificationReport> allReports) {
    final severity = _severityFilter;
    if (severity != null) {
      allReports = allReports
          .where((r) => normalizeSeverity(r.severity) == severity)
          .toList();
    }
    if (_query.isNotEmpty) {
      allReports = allReports
          .where(
            (r) => _matchesQuery([
              r.title,
              r.description,
              r.type,
              r.location,
              r.id,
            ]),
          )
          .toList();
    }
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
    final onReportsTab = _tabController.index == 1;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Alerts',
          style: GoogleFonts.lexend(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        actions: [
          if (onReportsTab)
            PopupMenuButton<String>(
              tooltip: 'Filter by severity',
              icon: Icon(
                _severityFilter == null ? Icons.filter_list : Icons.filter_alt,
                color: _severityFilter == null
                    ? AppColors.textPrimary
                    : AppColors.primaryRed,
              ),
              initialValue: _severityFilter ?? 'all',
              onSelected: (v) =>
                  setState(() => _severityFilter = v == 'all' ? null : v),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'all',
                  child: Text('All severities'),
                ),
                for (final level in SeverityLevel.values)
                  PopupMenuItem(
                    value: level.name,
                    child: Text(
                      '${level.name[0].toUpperCase()}${level.name.substring(1)}',
                    ),
                  ),
              ],
            ),
        ],
        backgroundColor: AppColors.background.withValues(alpha: 0.95),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primaryRed,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primaryRed,
          labelStyle: GoogleFonts.lexend(fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'Broadcasts'),
            Tab(text: 'Report History'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: onReportsTab
                      ? 'Search location, hazard, or ID...'
                      : 'Search alerts...',
                  hintStyle: GoogleFonts.lexend(color: Colors.grey.shade400),
                  prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.clear),
                          onPressed: _searchController.clear,
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
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildBroadcastsTab(), _buildReportHistoryTab()],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── Broadcast alerts ──────────────────────────────

  Widget _buildBroadcastsTab() {
    return Consumer2<AlertsProvider, ProfileProvider>(
      builder: (context, alertsProvider, profile, _) {
        final alerts = alertsProvider
            .alertsForLga(profile.lga)
            .where(
              (a) => _matchesQuery([a['title'], a['message'], a['targetLga']]),
            )
            .toList();

        final Widget child;
        if (alertsProvider.isLoading && alerts.isEmpty) {
          child = ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              ShimmerSkeletons.card(height: 100),
              ShimmerSkeletons.card(height: 100),
              ShimmerSkeletons.card(height: 100),
            ],
          );
        } else if (alerts.isEmpty) {
          final error = alertsProvider.error;
          child = ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              _buildEmptyState(
                icon: error != null
                    ? Icons.cloud_off
                    : Icons.notifications_off_outlined,
                title: error != null
                    ? 'Could not load alerts'
                    : _query.isNotEmpty
                    ? 'No matching alerts'
                    : 'No active alerts',
                message: error != null
                    ? 'Pull down to try again.'
                    : 'Official alerts for your area will appear here.',
              ),
            ],
          );
        } else {
          child = ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
            itemCount: alerts.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AnimatedListItem(
                index: index,
                child: _buildBroadcastCard(alerts[index]),
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: alertsProvider.fetchAlerts,
          child: child,
        );
      },
    );
  }

  Widget _buildBroadcastCard(Map<String, dynamic> alert) {
    final severity = alert['severity']?.toString();
    final color = alertSeverityColor(severity);
    final created = parseTimestamp(alert['createdAt']);
    final title = alert['title']?.toString() ?? 'Alert';
    final message = alert['message']?.toString() ?? '';
    final target = alert['targetLga']?.toString() ?? 'All';

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push('/alerts/detail', extra: alert),
      child: Container(
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
        child: IntrinsicHeight(
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
                        child: Icon(
                          alertSeverityIcon(severity),
                          color: color,
                          size: 24,
                        ),
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
                                if (created != null) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    DateFormat('MMM d, h:mm a').format(created),
                                    style: GoogleFonts.lexend(
                                      fontSize: 12,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (message.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                message,
                                style: GoogleFonts.lexend(
                                  fontSize: 14,
                                  color: AppColors.textSecondary,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 3,
                              ),
                            ],
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                _buildTag(alertSeverityLabel(severity), color),
                                _buildTag(
                                  target.toLowerCase() == 'all'
                                      ? 'All LGAs'
                                      : target,
                                  Colors.blueGrey,
                                ),
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
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
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
              child: Icon(icon, size: 64, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.lexend(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.lexend(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────── Report history ────────────────────────────────

  Widget _buildReportHistoryTab() {
    return Consumer<ReportsStatusProvider>(
      builder: (context, provider, _) {
        final allReports = provider.getReports(null);
        final isLoading = provider.isLoading(null);
        final hasMore = provider.hasMore(null);
        final filteredReports = _filterReports(allReports);
        final unfiltered =
            _selectedFilterIndex == 0 &&
            _severityFilter == null &&
            _query.isEmpty;

        return RefreshIndicator(
          onRefresh: () => provider.refreshReports(),
          child: NotificationListener<ScrollNotification>(
            onNotification: (ScrollNotification scrollInfo) {
              if (!isLoading &&
                  hasMore &&
                  scrollInfo.metrics.pixels >=
                      scrollInfo.metrics.maxScrollExtent - 200) {
                provider.fetchReports(loadMore: true, status: null);
              }
              return false;
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 80),
              child: Column(
                children: [
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
                                color: isLoading
                                    ? Colors.orange
                                    : AppColors.successGreen,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isLoading
                                  ? 'Synchronizing...'
                                  : 'Online • Just now',
                              style: GoogleFonts.lexend(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isLoading
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

                  if (filteredReports.isEmpty && !isLoading)
                    _buildEmptyState(
                      icon: unfiltered
                          ? Icons.notifications_off_outlined
                          : Icons.filter_list_off,
                      title: unfiltered
                          ? 'No Reports Yet'
                          : _selectedFilterIndex == 0
                          ? 'No matching reports'
                          : 'No ${_filters[_selectedFilterIndex]}',
                      message: unfiltered
                          ? 'When hazards are reported in your area,\nthey\'ll appear here'
                          : 'No matching reports found in this area',
                    )
                  else ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: filteredReports.asMap().entries.map((entry) {
                          final index = entry.key;
                          final report = entry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: AnimatedListItem(
                              index: index,
                              child: _buildAlertCardFromReport(
                                report,
                                provider,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    if (isLoading && filteredReports.isEmpty)
                      Column(
                        children: [
                          ShimmerSkeletons.card(height: 100),
                          ShimmerSkeletons.card(height: 100),
                          ShimmerSkeletons.card(height: 100),
                        ],
                      )
                    else if (isLoading)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                  ],

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
      },
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
    if (report.status == ReportStatus.verified) statusColor = Colors.blue;
    if (report.status == ReportStatus.approved) {
      statusColor = AppColors.successGreen;
    }
    if (report.status == ReportStatus.rejected) statusColor = Colors.red;

    return GestureDetector(
      onTap: () => context.push(
        '/alerts/detail',
        extra: <String, dynamic>{
          'title': report.title,
          'type': report.type,
          'severity': report.severity,
          'location': report.location,
          'time': report.time,
          'status': report.status.name,
          'description': report.description,
          'reportId': report.id,
          'reporterId': report.reporterId,
          'ward': report.ward,
          'lga': report.lga,
          'color': color,
          'icon': icon,
        },
      ),
      child: _buildAlertCard(
        title: report.title,
        time: report.time,
        location: report.location,
        icon: icon,
        color: color,
        severity: report.severity,
        status: statusStr,
        statusColor: statusColor,
        report: report,
        provider: provider,
      ),
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
    final auth = context.read<AuthProvider>();
    // Only verifiers (not the report owner) may confirm/decline.
    final canVerify = auth.canVoteOn(
      reporterId: report.reporterId,
      reportWard: report.ward,
      reportLga: report.lga,
    );
    final isPending = report.status == ReportStatus.pending && canVerify;

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
                            CustomToast.showSuccess(
                              context,
                              'Dispute recorded',
                            );
                          }
                        } on Exception catch (e) {
                          if (mounted) {
                            CustomToast.showError(
                              context,
                              e is VerificationRefusedException
                                  ? e.message
                                  : ErrorHandler.handleError(
                                      e,
                                      context: 'Alert',
                                    ),
                            );
                          }
                        }
                      },
                      text: 'Decline',
                      icon: Icons.close,
                      type: ButtonType.secondary,
                      foregroundColor: Colors.red,
                      borderColor: Colors.red,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: CustomButton(
                      onPressed: () async {
                        try {
                          await provider.verifyReport(report.id);
                          if (mounted) {
                            CustomToast.showSuccess(
                              context,
                              'Report confirmed',
                            );
                          }
                        } on Exception catch (e) {
                          if (mounted) {
                            CustomToast.showError(
                              context,
                              e is VerificationRefusedException
                                  ? e.message
                                  : ErrorHandler.handleError(
                                      e,
                                      context: 'Alert',
                                    ),
                            );
                          }
                        }
                      },
                      text: 'Confirm',
                      icon: Icons.check,
                      backgroundColor: AppColors.successGreen,
                      foregroundColor: Colors.black,
                      fontSize: 14,
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
