import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/core/design/animated_card.dart';
import 'package:climate_app/core/design/typography.dart';
import 'package:climate_app/core/providers/language_provider.dart';
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
import 'package:climate_app/l10n/app_localizations.dart';
import 'package:climate_app/shared/widgets/shimmer_loading.dart';
import 'package:climate_app/shared/widgets/animated_list_item.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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
                      Consumer2<LanguageProvider, ProfileProvider>(
                        builder: (context, language, profile, child) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              language.greeting.replaceAll(
                                '{name}',
                                profile.name,
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
                                    AppLocalizations.of(context)!.syncStatus,
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
                                              ? AppLocalizations.of(
                                                  context,
                                                )!.offline
                                              : (isSyncing
                                                    ? AppLocalizations.of(
                                                        context,
                                                      )!.syncing
                                                    : AppLocalizations.of(
                                                        context,
                                                      )!.onlineJustNow),
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
                                  onTap: () => context.push('/reports-status'),
                                  child: _buildStatCard(
                                    count: '$activeCount',
                                    label: AppLocalizations.of(context)!.active,
                                    icon: Icons.warning_amber,
                                    color: AppColors.warningYellow,
                                    bgColor: AppColors.warningYellow.withValues(
                                      alpha: 0.1,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => context.push('/reports-status'),
                                  child: _buildStatCard(
                                    count: '$pendingCount',
                                    label: AppLocalizations.of(
                                      context,
                                    )!.pending,
                                    icon: Icons.schedule,
                                    color: Colors.orange,
                                    bgColor: Colors.orange.withValues(
                                      alpha: 0.1,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => context.push('/reports-status'),
                                  child: _buildStatCard(
                                    count: '$approvedCount',
                                    label: AppLocalizations.of(
                                      context,
                                    )!.approved,
                                    icon: Icons.check_circle,
                                    color: AppColors.successGreen,
                                    bgColor: AppColors.successGreen.withValues(
                                      alpha: 0.1,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 24),

                      // Browse Categories
                      _buildSectionHeader(
                        AppLocalizations.of(context)!.browseCategories,
                        () => context.push('/alerts'),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildCategoryCard(
                              AppLocalizations.of(context)!.floodsCategory,
                              Icons.flood,
                              Colors.blue,
                              () => _onCategoryTap('Flooding'),
                            ),
                            _buildCategoryCard(
                              AppLocalizations.of(context)!.droughtsCategory,
                              Icons.wb_sunny,
                              Colors.orange,
                              () => _onCategoryTap('Drought'),
                            ),
                            _buildCategoryCard(
                              AppLocalizations.of(context)!.pestsCategory,
                              Icons.pest_control,
                              Colors.green,
                              () => _onCategoryTap('Pest/Disease'),
                            ),
                            _buildCategoryCard(
                              AppLocalizations.of(context)!.conflictsCategory,
                              Icons.shield,
                              Colors.red,
                              () => _onCategoryTap('Conflict'),
                            ),
                            _buildCategoryCard(
                              AppLocalizations.of(context)!.erosion,
                              Icons.landscape,
                              Colors.brown,
                              () => _onCategoryTap('Erosion'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Biometrics Card Removed

                      // Filter Tabs (Sticky-ish behavior handled by placement here)
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFE7F3EB,
                          ), // Light greenish tint from design, adapted
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.all(6),
                        child: Row(
                          children: [
                            _buildFilterTab(
                              0,
                              AppLocalizations.of(context)!.toVerify,
                            ),
                            _buildFilterTab(
                              1,
                              AppLocalizations.of(context)!.alerts,
                            ),
                            _buildFilterTab(
                              2,
                              AppLocalizations.of(context)!.myReports,
                            ),
                            _buildFilterTab(3, 'Nearby'),
                          ],
                        ),
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
                          AppLocalizations.of(context)!.monitoringZone,
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
                                  '${profile.monitoringZone ?? AppLocalizations.of(context)!.selectZone} • ${profile.monitoringZone != null ? AppLocalizations.of(context)!.activeZone : AppLocalizations.of(context)!.notSetZone}',
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
                onTap: () {
                  // Notification action
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLocalizations.of(context)!.noNewNotifications,
                      ),
                    ),
                  );
                },
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

  Widget _buildStatCard({
    required String count,
    required String label,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return AnimatedCard(
      borderRadius: 20,
      backgroundColor: Colors.white,
      padding: const EdgeInsets.all(18),
      shadows: [
        BoxShadow(
          color: color.withValues(alpha: 0.15),
          blurRadius: 25,
          offset: const Offset(0, 12),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 15,
          offset: const Offset(0, 6),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      color.withValues(alpha: 0.2),
                      color.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: color.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.arrow_forward, color: color, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            count,
            style: PremiumTypography.heading2(
              context,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: PremiumTypography.subtitle(context)),
        ],
      ),
    );
  }

  Widget _buildFilterTab(int index, String label) {
    final bool isSelected = _selectedFilterIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedFilterIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.lexend(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected
                  ? AppColors.textPrimary
                  : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeedContent() {
    final statusProvider = context.watch<ReportsStatusProvider>();

    if (_selectedFilterIndex == 0) {
      // To Verify
      return _buildListFeed(
        statusProvider.getReports(ReportStatus.pending),
        statusProvider.isLoading(ReportStatus.pending),
        'No reports to verify',
      );
    } else if (_selectedFilterIndex == 2) {
      // My Reports
      final userId = context.read<AuthProvider>().currentUser?.id;
      return _buildListFeed(
        statusProvider.getReports(null, userId: userId),
        statusProvider.isLoading(null, userId: userId),
        'You haven\'t submitted any reports yet',
      );
    } else if (_selectedFilterIndex == 3) {
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
                    'Open Nearby Reports',
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
            'No nearby reports',
          ),
        ],
      );
    } else {
      // Alerts (All)
      return _buildListFeed(
        statusProvider.getReports(null),
        statusProvider.isLoading(null),
        'No recent alerts',
      );
    }
  }

  Widget _buildListFeed(
    List<VerificationReport> reports,
    bool isLoading,
    String emptyMessage,
  ) {
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
                _getIconData(report.iconName),
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
                          report.title,
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
                          report.status.displayName,
                          style: GoogleFonts.lexend(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: _getStatusColor(report.status),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${report.location} • ${report.time}',
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
            'See All',
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
      zones.add('$state State'); // state-level
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
                  'Select Monitoring Zone',
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
                          'All Zones (No Filter)',
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
                          await provider.updateMonitoringZone('');
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Showing all zones'),
                                backgroundColor: AppColors.successGreen,
                              ),
                            );
                          }
                        },
                      ),
                      const Divider(),
                      ...zones.map((zone) {
                        final isState = zone.contains('State');
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
                            zone,
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
                            await provider.updateMonitoringZone(zone);
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Monitoring zone changed to $zone',
                                  ),
                                  backgroundColor: AppColors.successGreen,
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
