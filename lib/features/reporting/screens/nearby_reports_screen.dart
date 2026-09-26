import 'package:climate_app/features/verification/widgets/verification_request_badge.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:climate_app/core/constants/hazards.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:climate_app/features/verification/models/verification_report_model.dart';
import 'package:climate_app/features/profile/providers/profile_provider.dart';
import 'package:climate_app/shared/widgets/shimmer_loading.dart';
import 'package:climate_app/core/l10n/l10n.dart';

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
  LocalizedText? _error;

  /// Plain users may only read their own reports (RLS), so a feed of
  /// other people's reports is not available to them.
  bool get _isPlainUser =>
      context.read<AuthProvider>().userRole == UserRole.user;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNearby());
  }

  /// Reports within this radius of the user's position count as nearby.
  static const double _nearbyRadiusKm = 25;

  Future<void> _loadNearby() async {
    if (_isPlainUser) {
      setState(() => _isLoading = false);
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final profile = context.read<ProfileProvider>();
    final uid = context.read<AuthProvider>().currentUser?.id;

    // Load every page (the area filter below is client-side, so the first
    // page alone would miss older nearby reports).
    final provider = context.read<ReportsStatusProvider>();
    await provider.fetchAllPages(status: null, maxRows: 2000);
    final userPosition = await _tryGetUserPosition();
    if (!mounted) return;
    final allReports = provider.getReports(null);
    final fetchError = provider.errorFor(null);

    // Resolve the user's area. Monitoring zones look like
    // "Makurdi, Benue" (LGA, State) or "Benue State".
    String? norm(String? v) {
      final t = v?.trim().toLowerCase();
      return (t == null || t.isEmpty) ? null : t;
    }

    final zone = norm(profile.monitoringZone);
    String? userLga = norm(profile.lga);
    String? userState = norm(profile.state);
    if (zone != null && !zone.contains('all zone')) {
      if (zone.contains(',')) {
        userLga ??= norm(zone.split(',').first);
        userState ??= norm(
          zone.split(',').last.replaceAll(RegExp(r'\s+state$'), ''),
        );
      } else {
        userState ??= norm(zone.replaceAll(RegExp(r'\s+state$'), ''));
      }
    }

    final entries = <_NearbyEntry>[];
    for (final r in allReports) {
      // Exclude own reports
      if (uid != null && r.reporterId == uid) continue;

      // Distance, when both the user and the report have real coordinates
      double? distanceKm;
      final lat = r.latitude, lng = r.longitude;
      if (userPosition != null &&
          lat != null &&
          lng != null &&
          !(lat == 0 && lng == 0)) {
        distanceKm =
            Geolocator.distanceBetween(
              userPosition.latitude,
              userPosition.longitude,
              lat,
              lng,
            ) /
            1000;
      }

      final reportLga = norm(r.lga);
      final reportState = norm(r.state);
      final bool isNearby;
      if (distanceKm != null && distanceKm <= _nearbyRadiusKm) {
        isNearby = true;
      } else if (userLga != null && reportLga != null) {
        // LGA names repeat across states: the state must match too.
        isNearby =
            reportLga == userLga &&
            (userState == null ||
                reportState == null ||
                reportState == userState);
      } else if (userState != null && reportState != null) {
        isNearby = reportState == userState;
      } else {
        isNearby = false;
      }

      if (isNearby) {
        entries.add(_NearbyEntry(report: r, distanceKm: distanceKm));
      }
    }

    // Closest first; reports without a distance keep their (recency) order.
    final withDistance = entries.where((e) => e.distanceKm != null).toList()
      ..sort((a, b) => a.distanceKm!.compareTo(b.distanceKm!));
    _nearbyReports = [
      ...withDistance,
      ...entries.where((e) => e.distanceKm == null),
    ];
    if (mounted) {
      setState(() {
        _isLoading = false;
        _error = fetchError;
      });
    }
  }

  /// Best-effort user position without prompting for permission.
  Future<Position?> _tryGetUserPosition() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return null;
      }
      return await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition().timeout(
            const Duration(seconds: 5),
          );
    } on Object catch (_) {
      // Location unavailable (disabled, timeout, unsupported platform).
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          context.l10n.nearbyTitle,
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
            tooltip: context.l10n.refresh,
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
    if (_isPlainUser) {
      return _buildMessage(
        icon: Icons.lock_outline,
        title: context.l10n.nearbyNotAvailableTitle,
        message: context.l10n.nearbyNotAvailableBody,
      );
    }
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
    if (profile.lga == null &&
        profile.state == null &&
        profile.monitoringZone == null) {
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
                context.l10n.nearbyLocationNotSetTitle,
                style: GoogleFonts.lexend(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                context.l10n.nearbyLocationNotSetBody,
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

    if (_nearbyReports.isEmpty && _error != null) {
      return _buildMessage(
        icon: Icons.cloud_off,
        title: context.l10n.nearbyLoadErrorTitle,
        message: _error!(context.l10n),
        onRetry: _loadNearby,
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
                context.l10n.nearbyEmptyTitle,
                style: GoogleFonts.lexend(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                context.l10n.nearbyEmptyBody,
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
                context.l10n.nearbyReportsInAreaCount(_nearbyReports.length),
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
                                const Icon(
                                  Icons.near_me,
                                  size: 12,
                                  color: AppColors.successGreen,
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

  Widget _buildMessage({
    required IconData icon,
    required String title,
    required String message,
    VoidCallback? onRetry,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.lexend(
                fontSize: 18,
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
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(context.l10n.retry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pairs a report with an optional distance for sorting.
class _NearbyEntry {
  final VerificationReport report;
  final double? distanceKm;

  const _NearbyEntry({required this.report, this.distanceKm});
}
