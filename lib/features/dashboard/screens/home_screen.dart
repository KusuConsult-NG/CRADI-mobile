import 'package:climate_app/features/verification/widgets/verification_request_badge.dart';
import 'package:climate_app/core/services/remote_config_service.dart';
import 'package:climate_app/core/constants/hazards.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/core/design/typography.dart';
import 'package:climate_app/features/dashboard/widgets/dashboard_stat_card.dart';
import 'package:climate_app/features/dashboard/widgets/home_feed_filter_bar.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:climate_app/features/profile/providers/profile_provider.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:climate_app/core/data/mvp_locations_data.dart';

import 'package:climate_app/features/knowledge_base/providers/news_provider.dart';
import 'package:climate_app/features/verification/models/verification_report_model.dart';
import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart'; // ADDED
import 'package:climate_app/core/providers/connectivity_provider.dart';
import 'package:climate_app/core/services/notification_service.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart';
import 'package:climate_app/shared/widgets/shimmer_loading.dart';
import 'package:climate_app/shared/widgets/animated_list_item.dart';
import 'package:climate_app/core/l10n/l10n.dart';
import 'package:climate_app/core/l10n/zone_label.dart';

/// Home feed tab actually shown for [selected] (0 To Verify, 1 Alerts,
/// 2 My Reports, 3 Nearby): "To Verify" only exists for peer verifiers and
/// "Nearby" not for plain users; both fall back to My Reports.
@visibleForTesting
int effectiveFeedTab(int selected, UserRole? role) {
  if (selected == 0 && !AuthProvider.verifierRoles.contains(role)) return 2;
  if (selected == 3 && role == UserRole.user) return 2;
  return selected;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Reports shown in the home "To Verify" feed.
  static const int _toVerifyLimit = 20;

  int _selectedFilterIndex = 0;

  @override
  void initState() {
    super.initState();
    // Initial fetch if needed, though StreamBuilder handles it

    // Lazy Escalation Check
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Fetch reports for all tabs on the home screen.
      // Two separate fetches are needed because each tab reads from a
      // different cache key:
      //   - To Verify / Alerts / Nearby → keyed by (status, null)
      //   - My Reports                  → keyed by (null, userId)
      final auth = context.read<AuthProvider>();
      final statusProvider = context.read<ReportsStatusProvider>();
      // 1. Zone-filtered reports for To Verify / Alerts / Nearby tabs
      statusProvider.refreshReports();
      // 2. User-specific reports for the "My Reports" tab
      if (auth.currentUser?.id != null) {
        statusProvider.refreshReports(userId: auth.currentUser!.id);
      }

      // Overdue-report escalation runs on the backend (cron); nothing to do
      // client-side.

      // Flush anything left offline once the (logged-in) dashboard opens.
      // Reconnect-triggered sync is wired once in main.dart (onReconnect);
      // ReportingProvider.syncPendingReports is re-entrancy guarded.
      try {
        if (!context.read<ConnectivityProvider>().isOffline) {
          context.read<ReportingProvider>().syncPendingReports(context);
        }
      } on Exception catch (e) {
        ErrorHandler.logError(e, context: 'HomeScreen.refresh');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            // Reload user profile data and stats
            if (context.mounted) {
              final auth = context.read<AuthProvider>();
              final statusProvider = context.read<ReportsStatusProvider>();
              await Future.wait([
                context.read<ProfileProvider>().loadProfile(),
                // Zone-filtered reports for To Verify / Alerts / Nearby
                statusProvider.refreshReports(),
                // User-specific reports for My Reports tab
                if (auth.currentUser?.id != null)
                  statusProvider.refreshReports(userId: auth.currentUser!.id),
                context.read<NewsProvider>().fetchNews(),
              ]);
            }
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                _buildHeader(), // Include Header in scrollable area
                // Main Content Body (formerly Expanded)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Greeting
                      Consumer<ProfileProvider>(
                        builder: (context, profile, child) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10n.homeGreeting(
                                profile.name.isNotEmpty
                                    ? profile.name
                                    : context.l10n.profileDefaultName,
                              ),
                              style: PremiumTypography.heading1(context),
                            ),
                          ],
                        ),
                      ),
                      // Sync Status
                      Consumer2<ReportsStatusProvider, ConnectivityProvider>(
                        builder:
                            (
                              context,
                              reportsProvider,
                              connectivityProvider,
                              _,
                            ) {
                              final isOffline = connectivityProvider.isOffline;
                              final isSyncing = reportsProvider.isLoading(null);

                              return Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    context.l10n.syncStatus,
                                    style: GoogleFonts.lexend(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade500,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () async {
                                      final auth = context.read<AuthProvider>();
                                      final isUser =
                                          auth.userRole == UserRole.user;
                                      await reportsProvider.refreshReports(
                                        userId: isUser
                                            ? auth.currentUser?.id
                                            : null,
                                      );
                                    },
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: isOffline
                                                ? Colors.red
                                                : (isSyncing
                                                      ? Colors.orange
                                                      : AppColors.successGreen),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          isOffline
                                              ? context.l10n.offline
                                              : (isSyncing
                                                    ? context.l10n.syncing
                                                    : context
                                                          .l10n
                                                          .onlineJustNow),
                                          style: GoogleFonts.lexend(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: isOffline
                                                ? Colors.red
                                                : (isSyncing
                                                      ? Colors.orange
                                                      : AppColors.successGreen),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          isOffline
                                              ? Icons.cloud_off
                                              : Icons.refresh,
                                          size: 12,
                                          color: isOffline
                                              ? Colors.red
                                              : (isSyncing
                                                    ? Colors.orange
                                                    : AppColors.successGreen),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                      ),
                      const SizedBox(height: 16),

                      // Quick Stats
                      Consumer<ReportsStatusProvider>(
                        builder: (context, provider, _) {
                          final auth = context.read<AuthProvider>();
                          final isUser = auth.userRole == UserRole.user;
                          final uid = isUser ? auth.currentUser?.id : null;
                          // Using total counts from provider (requires fetch to be populated)
                          // Assuming refreshReports() is called in initState
                          final activeCount = provider.getTotal(
                            ReportStatus.verified,
                            userId: uid,
                          );
                          final pendingCount = provider.getTotal(
                            ReportStatus.pending,
                            userId: uid,
                          );
                          final approvedCount = provider.getTotal(
                            ReportStatus.approved,
                            userId: uid,
                          );

                          return Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => context.push(
                                    '/reports-status?tab=verified',
                                  ),
                                  child: DashboardStatCard(
                                    count: '$activeCount',
                                    label: context.l10n.active,
                                    icon: Icons.warning_amber,
                                    color: AppColors.warningYellow,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => context.push(
                                    '/reports-status?tab=pending',
                                  ),
                                  child: DashboardStatCard(
                                    count: '$pendingCount',
                                    label: context.l10n.pending,
                                    icon: Icons.schedule,
                                    color: Colors.orange,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => context.push(
                                    '/reports-status?tab=approved',
                                  ),
                                  child: DashboardStatCard(
                                    count: '$approvedCount',
                                    label: context.l10n.approved,
                                    icon: Icons.check_circle,
                                    color: AppColors.successGreen,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      // Quick links: own reports, and the verification
                      // queue for peer verifiers.
                      _buildQuickLink(
                        icon: Icons.assignment_outlined,
                        label: context.l10n.myReports,
                        onTap: () => context.push('/my-reports'),
                      ),
                      if (AuthProvider.verifierRoles.contains(
                        context.watch<AuthProvider>().userRole,
                      )) ...[
                        const SizedBox(height: 8),
                        _buildQuickLink(
                          icon: Icons.fact_check_outlined,
                          label: context.l10n.homeVerifyReportsLink,
                          onTap: () => context.push('/verification'),
                        ),
                      ],
                      const SizedBox(height: 24),

                      // Browse Categories
                      _buildSectionHeader(
                        context.l10n.browseCategories,
                        () => context.push('/alerts'),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            // One shortcut per hazard; the stored name is
                            // the Alerts screen's category filter.
                            for (final hazard in Hazard.values)
                              _buildCategoryCard(
                                hazard.label(context.l10n),
                                hazard.icon,
                                hazard.color,
                                () => _onCategoryTap(hazard.storedName),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Biometrics Card Removed

                      // Filter Tabs (Sticky-ish behavior handled by placement here)
                      Builder(
                        builder: (context) {
                          final role = context.watch<AuthProvider>().userRole;
                          return HomeFeedFilterBar(
                            filters: [
                              // Only peer verifiers have anything to verify;
                              // everyone else starts on My Reports.
                              if (AuthProvider.verifierRoles.contains(role))
                                HomeFeedFilter(0, context.l10n.toVerify),
                              HomeFeedFilter(1, context.l10n.alerts),
                              HomeFeedFilter(2, context.l10n.myReports),
                              // Plain users can only read their own reports
                              // (RLS), so a "nearby" feed would always be
                              // empty for them.
                              if (role != UserRole.user)
                                HomeFeedFilter(3, context.l10n.homeTabNearby),
                            ],
                            selectedIndex: effectiveFeedTab(
                              _selectedFilterIndex,
                              role,
                            ),
                            onSelected: (index) =>
                                setState(() => _selectedFilterIndex = index),
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      // Feed Content
                      _buildFeedContent(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => context.push('/profile'),
                  child: Consumer<ProfileProvider>(
                    builder: (context, profile, _) {
                      if (profile.profileImagePath != null &&
                          profile.profileImagePath!.isNotEmpty) {
                        final imagePath = profile.profileImagePath!;
                        final isNetworkImage = imagePath.startsWith('http');

                        return Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.primaryRed,
                              width: 2,
                            ),
                            image: DecorationImage(
                              image: isNetworkImage
                                  ? NetworkImage(imagePath)
                                  : FileImage(File(imagePath)) as ImageProvider,
                              fit: BoxFit.cover,
                            ),
                          ),
                        );
                      }
                      return Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey.shade300,
                          border: Border.all(
                            color: AppColors.primaryRed,
                            width: 2,
                          ),
                        ),
                        child: const Icon(Icons.person, color: Colors.grey),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _showZoneSelector(context),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.monitoringZone,
                          style: GoogleFonts.lexend(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Consumer<ProfileProvider>(
                          builder: (context, profile, _) => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  context.l10n.homeZoneStatus(
                                    profile.monitoringZone != null
                                        ? monitoringZoneLabel(
                                            context.l10n,
                                            profile.monitoringZone!,
                                          )
                                        : context.l10n.selectZone,
                                    profile.monitoringZone != null
                                        ? context.l10n.activeZone
                                        : context.l10n.notSetZone,
                                  ),
                                  style: GoogleFonts.lexend(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                              const SizedBox(width: 2),
                              const Icon(
                                Icons.expand_more,
                                size: 18,
                                color: AppColors.textPrimary,
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
          Row(
            children: [
              if (RemoteConfigService().featureFlagPeerChat)
                GestureDetector(
                  onTap: () => context.push('/chat'),
                  child: Container(
                    width: 40,
                    height: 40,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.chat_bubble_outline,
                      color: AppColors.textPrimary,
                      size: 20,
                    ),
                  ),
                ),
              GestureDetector(
                onTap: () => context.push('/notifications'),
                child: Stack(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.notifications_outlined,
                        color: AppColors.textPrimary,
                        size: 22,
                      ),
                    ),
                    ValueListenableBuilder<int>(
                      valueListenable: NotificationService().unreadCount,
                      builder: (context, count, _) {
                        if (count == 0) return const SizedBox.shrink();
                        return Positioned(
                          top: 10,
                          right: 12,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.errorRed,
                              shape: BoxShape.circle,
                            ),
                          ),
                        );
                      },
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

  Widget _buildQuickLink({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        leading: Icon(icon, color: AppColors.primaryRed),
        title: Text(
          label,
          style: GoogleFonts.lexend(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  Widget _buildFeedContent() {
    final statusProvider = context.watch<ReportsStatusProvider>();
    final auth = context.watch<AuthProvider>();
    final selected = effectiveFeedTab(_selectedFilterIndex, auth.userRole);

    if (selected == 0) {
      // To Verify: pending reports this user may still vote on (never
      // their own, EWMs only in their LGA + ward, not already voted).
      // Loaded by fetchToVerify (own reports excluded server-side, with
      // a large page so the client-side filters below still leave enough).
      final uid = auth.currentUser?.id;
      final toVerify = statusProvider
          .toVerifyReports(uid)
          .where(
            (r) => auth.canVoteOn(
              reporterId: r.reporterId,
              reportWard: r.ward,
              reportLga: r.lga,
            ),
          )
          .take(_toVerifyLimit)
          .toList();
      return _buildListFeed(
        toVerify,
        statusProvider.isLoading(ReportStatus.pending, excludeUserId: uid),
        context.l10n.noReportsToVerify,
        error: statusProvider.errorFor(
          ReportStatus.pending,
          excludeUserId: uid,
        ),
        onRetry: statusProvider.fetchToVerify,
      );
    } else if (selected == 2) {
      // My Reports
      final userId = auth.currentUser?.id;
      return _buildListFeed(
        statusProvider.getReports(null, userId: userId),
        statusProvider.isLoading(null, userId: userId),
        context.l10n.homeEmptyMyReports,
        error: statusProvider.errorFor(null, userId: userId),
        onRetry: () => statusProvider.fetchReports(userId: userId),
      );
    } else if (selected == 3) {
      // Nearby — use same feed but prompt to see full screen
      return Column(
        children: [
          GestureDetector(
            onTap: () => context.push('/nearby-reports'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.near_me,
                    size: 16,
                    color: AppColors.successGreen,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    context.l10n.homeOpenNearbyReports,
                    style: GoogleFonts.lexend(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.successGreen,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.arrow_forward_ios,
                    size: 12,
                    color: AppColors.successGreen,
                  ),
                ],
              ),
            ),
          ),
          _buildListFeed(
            statusProvider.getReports(null),
            statusProvider.isLoading(null),
            context.l10n.homeEmptyNearby,
            error: statusProvider.errorFor(null),
            onRetry: () => statusProvider.fetchReports(),
          ),
        ],
      );
    } else {
      // Alerts (All)
      return _buildListFeed(
        statusProvider.getReports(null),
        statusProvider.isLoading(null),
        context.l10n.noRecentAlerts,
        error: statusProvider.errorFor(null),
        onRetry: () => statusProvider.fetchReports(),
      );
    }
  }

  Widget _buildListFeed(
    List<VerificationReport> reports,
    bool isLoading,
    String emptyMessage, {
    LocalizedText? error,
    VoidCallback? onRetry,
  }) {
    if (isLoading && reports.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            ShimmerSkeletons.listTile(),
            ShimmerSkeletons.listTile(),
            ShimmerSkeletons.listTile(),
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
              Icon(Icons.cloud_off, size: 48, color: Colors.red.shade200),
              const SizedBox(height: 12),
              Text(
                error(context.l10n),
                style: GoogleFonts.lexend(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                TextButton.icon(
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

    if (reports.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 48,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                emptyMessage,
                style: GoogleFonts.lexend(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: reports.length > 5
          ? 5
          : reports.length, // Show only top 5 on home
      separatorBuilder: (_, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final report = reports[index];
        return AnimatedListItem(index: index, child: _buildReportItem(report));
      },
    );
  }

  Widget _buildReportItem(VerificationReport report) {
    return GestureDetector(
      onTap: () {
        context.push('/report-view', extra: report);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _getIconBgColor(report.iconColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Hazard.iconFor(report.type),
                color: _getIconColor(report.iconColor),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          report.displayTitle(context.l10n),
                          style: GoogleFonts.lexend(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Status Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _getStatusColor(
                            report.status,
                          ).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _getStatusColor(
                              report.status,
                            ).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          report.status.label(context.l10n),
                          style: GoogleFonts.lexend(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: _getStatusColor(report.status),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (report.isVerificationRequest) ...[
                    const SizedBox(height: 4),
                    const VerificationRequestBadge(),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.reportLocationAndTime(
                      report.displayLocation(context.l10n),
                      report.displayTime(context.l10n),
                    ),
                    style: GoogleFonts.lexend(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

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

  Color _getIconColor(String colorName) => SeverityColors.fromName(colorName);

  Color _getIconBgColor(String colorName) {
    return _getIconColor(colorName).withValues(alpha: 0.1);
  }

  Widget _buildSectionHeader(String title, VoidCallback onViewAll) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.lexend(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        GestureDetector(
          onTap: onViewAll,
          child: Text(
            context.l10n.seeAll,
            style: GoogleFonts.lexend(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryRed,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryCard(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.lexend(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onCategoryTap(String category) {
    // Navigate to Alert History (filtered by category)
    context.push('/alerts', extra: category);
  }

  void _showZoneSelector(BuildContext context) {
    // Build zone list: state-level entries + individual LGAs
    final zones = <String>[];
    for (final state in MVPLocationsData.getAllStates()) {
      zones.add('$state$stateZoneSuffix'); // state-level (stored form)
      for (final lga in MVPLocationsData.getLGAsForState(state)) {
        zones.add('$lga, $state'); // LGA-level
      }
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  context.l10n.homeZoneSheetTitle,
                  style: GoogleFonts.lexend(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Reset option
                      ListTile(
                        leading: const Icon(
                          Icons.public,
                          color: AppColors.primaryRed,
                        ),
                        title: Text(
                          context.l10n.homeZoneAll,
                          style: GoogleFonts.lexend(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryRed,
                          ),
                        ),
                        trailing: Consumer<ProfileProvider>(
                          builder: (context, profile, _) =>
                              profile.monitoringZone == null
                              ? const Icon(
                                  Icons.check,
                                  color: AppColors.primaryRed,
                                )
                              : const SizedBox(),
                        ),
                        onTap: () async {
                          final provider = context.read<ProfileProvider>();
                          final error = await provider.updateMonitoringZone('');
                          if (context.mounted) {
                            final l10n = context.l10n;
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  error == null
                                      ? l10n.homeZoneAllSelected
                                      : l10n.homeZoneAllLocalOnly(error(l10n)),
                                ),
                                backgroundColor: error == null
                                    ? AppColors.successGreen
                                    : null,
                              ),
                            );
                          }
                        },
                      ),
                      const Divider(),
                      ...zones.map((zone) {
                        final isState = zone.endsWith(stateZoneSuffix);
                        return ListTile(
                          contentPadding: EdgeInsets.only(
                            left: isState ? 16 : 40,
                            right: 16,
                          ),
                          leading: isState
                              ? const Icon(
                                  Icons.location_city,
                                  color: AppColors.textPrimary,
                                  size: 20,
                                )
                              : null,
                          title: Text(
                            monitoringZoneLabel(context.l10n, zone),
                            style: GoogleFonts.lexend(
                              fontSize: isState ? 16 : 14,
                              fontWeight: isState
                                  ? FontWeight.bold
                                  : FontWeight.w400,
                              color: isState
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          trailing: Consumer<ProfileProvider>(
                            builder: (context, profile, _) =>
                                profile.monitoringZone == zone
                                ? const Icon(
                                    Icons.check,
                                    color: AppColors.primaryRed,
                                  )
                                : const SizedBox(),
                          ),
                          onTap: () async {
                            final provider = context.read<ProfileProvider>();
                            final error = await provider.updateMonitoringZone(
                              zone,
                            );
                            if (context.mounted) {
                              final l10n = context.l10n;
                              final zoneLabel = monitoringZoneLabel(l10n, zone);
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    error == null
                                        ? l10n.homeZoneChanged(zoneLabel)
                                        : l10n.homeZoneLocalOnly(
                                            zoneLabel,
                                            error(l10n),
                                          ),
                                  ),
                                  backgroundColor: error == null
                                      ? AppColors.successGreen
                                      : null,
                                ),
                              );
                            }
                          },
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
