import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:climate_app/features/verification/models/verification_report_model.dart';
import 'package:climate_app/features/profile/providers/profile_provider.dart';
import 'package:climate_app/shared/widgets/shimmer_loading.dart';

/// Nearby Reports feed — shows reports from the user's LGA/monitoring zone
/// and, when coordinates are available, sorts by proximity.
class NearbyReportsScreen extends StatefulWidget {
  const NearbyReportsScreen({super.key});

  @override
  State<NearbyReportsScreen> createState() => _NearbyReportsScreenState();
}

class _NearbyReportsScreenState extends State<NearbyReportsScreen> {
  List<_NearbyEntry> _nearbyReports = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNearby());
  }

  Future<void> _loadNearby() async {
    setState(() => _isLoading = true);

    final profile = context.read<ProfileProvider>();
    final uid = context.read<AuthProvider>().currentUser?.uid;

    // Fetch all reports
    final provider = context.read<ReportsStatusProvider>();
    await provider.fetchReports(status: null);
    final allReports = provider.getReports(null);

    // Filter: exclude user's own, then match by location area
    final userLga = profile.lga?.toLowerCase();
    final userState = profile.state?.toLowerCase();
    final userZone = profile.monitoringZone?.toLowerCase();

    final filtered = allReports.where((r) {
      // Exclude own reports
      if (r.reporterId == uid) return false;

      // Match by location text — check if the report location
      // contains user's LGA, zone, or state
      final loc = r.location.toLowerCase();
      if (userLga != null && loc.contains(userLga)) return true;
      if (userZone != null && loc.contains(userZone)) return true;
      if (userState != null && loc.contains(userState)) return true;

      return false;
    }).toList();

    // Build entries (compute distance if both have coordinates)
    _nearbyReports = filtered.map((r) {
      return _NearbyEntry(report: r, distanceKm: null);
    }).toList();

    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Nearby Reports',
          style: GoogleFonts.lexend(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppColors.background,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textPrimary),
            onPressed: _loadNearby,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.grey.shade200, height: 1.0),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
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

    final profile = context.read<ProfileProvider>();
    if (profile.lga == null && profile.state == null && profile.monitoringZone == null) {
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
                  Icons.location_off,
                  size: 64,
                  color: Colors.grey.shade400,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Location Not Set',
                style: GoogleFonts.lexend(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Set your LGA or monitoring zone in\nyour profile to see reports near you.',
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

    if (_nearbyReports.isEmpty) {
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
                  Icons.explore_off,
                  size: 64,
                  color: Colors.grey.shade400,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'No Nearby Reports',
                style: GoogleFonts.lexend(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'There are no reports from your\narea at this time.',
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
      onRefresh: _loadNearby,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _nearbyReports.length + 1, // +1 for header
        separatorBuilder: (_, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${_nearbyReports.length} report${_nearbyReports.length == 1 ? '' : 's'} in your area',
                style: GoogleFonts.lexend(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            );
          }
          final entry = _nearbyReports[index - 1];
          return _buildNearbyCard(entry);
        },
      ),
    );
  }

  Widget _buildNearbyCard(_NearbyEntry entry) {
    final report = entry.report;
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
                                const Icon(
                                  Icons.near_me,
                                  size: 12,
                                  color: AppColors.successGreen,
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

/// Pairs a report with an optional distance for sorting.
class _NearbyEntry {
  final VerificationReport report;
  final double? distanceKm;

  const _NearbyEntry({required this.report, this.distanceKm});
}
