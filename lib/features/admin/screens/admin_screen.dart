import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/core/l10n/l10n.dart';

/// Admin Dashboard — entry point for admin and techSupport roles.
/// Shows live summary cards for pending users, open reports, and system health.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  /// Created once (and on refresh) so rebuilds do not re-run the counts.
  late Future<List<int?>> _countsFuture;

  @override
  void initState() {
    super.initState();
    _countsFuture = _loadCounts();
  }

  /// Exact row count of [table] (column names are database names). Errors
  /// propagate so the dashboard can show them instead of a misleading 0.
  Future<int> _count(String table, {Map<String, Object>? where}) =>
      SupabaseService().countDocumentsOrThrow(
        collectionId: table,
        queries: [
          for (final e in (where ?? const <String, Object>{}).entries)
            WhereFilter(e.key, FilterOp.eq, e.value),
        ],
      );

  /// Other users' profiles are readable by admins only (tech support sees
  /// just its own row), so profile counts are unknown (null) otherwise.
  Future<int?> _countProfiles({Map<String, Object>? where}) =>
      context.read<AuthProvider>().userRole == UserRole.admin
      ? _count('profiles', where: where)
      : Future<int?>.value();

  Future<List<int?>> _loadCounts() => Future.wait<int?>([
    _countProfiles(where: {'is_approved': false}),
    _count('reports', where: {'status': 'pending'}),
    _count('reports', where: {'status': 'verified'}),
    _countProfiles(),
    _count('alerts', where: {'is_active': true}),
    _count('reports'),
  ]);

  Future<void> _refresh() async {
    final future = _loadCounts();
    setState(() => _countsFuture = future);
    try {
      await future;
    } on Object catch (_) {
      // Shown by the FutureBuilder.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Profile writes (approve / role / disable) are admin-only in the
    // database, so tech support gets no user management.
    final canManageUsers =
        context.watch<AuthProvider>().userRole == UserRole.admin;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          l10n.adminPortal,
          style: GoogleFonts.lexend(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.primaryRed,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<int?>>(
        future: _countsFuture,
        builder: (context, snap) {
          // null = unknown (loading or failed), never a fake 0.
          final List<int?> counts = snap.data ?? List<int?>.filled(6, null);
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                if (snap.hasError)
                  Card(
                    color: Colors.red.shade50,
                    margin: const EdgeInsets.only(bottom: 16),
                    child: ListTile(
                      leading: const Icon(
                        Icons.error_outline,
                        color: Colors.red,
                      ),
                      title: Text(
                        context.l10n.adminCountsError,
                        style: GoogleFonts.lexend(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(context.l10n.adminCountsErrorBody),
                      trailing: TextButton(
                        onPressed: _refresh,
                        child: Text(context.l10n.retry),
                      ),
                    ),
                  ),
                // ── System Overview header ──
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.systemOverview,
                        style: GoogleFonts.lexend(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (snap.connectionState == ConnectionState.waiting)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      IconButton(
                        tooltip: context.l10n.refresh,
                        icon: const Icon(Icons.refresh),
                        onPressed: _refresh,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _SummaryGrid(counts: counts, canManageUsers: canManageUsers),
                const SizedBox(height: 28),

                // ── Quick Actions ──
                Text(
                  l10n.quickActions,
                  style: GoogleFonts.lexend(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),

                if (canManageUsers)
                  _ActionTile(
                    icon: Icons.supervised_user_circle_outlined,
                    title: l10n.userManagement,
                    subtitle: l10n.userManagementDesc,
                    badge: (counts[0] ?? 0) > 0 ? counts[0] : null,
                    onTap: () => context.push('/admin/users'),
                  ),
                _ActionTile(
                  icon: Icons.assessment_outlined,
                  title: l10n.reportsOverview,
                  subtitle: l10n.reportsOverviewDesc,
                  badge: (counts[2] ?? 0) > 0 ? counts[2] : null,
                  badgeColor: Colors.orange,
                  onTap: () => context.push('/admin/reports'),
                ),
                _ActionTile(
                  icon: Icons.campaign_outlined,
                  title: l10n.alertsBroadcast,
                  subtitle: l10n.alertsBroadcastDesc,
                  badge: (counts[4] ?? 0) > 0 ? counts[4] : null,
                  badgeColor: Colors.deepOrange,
                  onTap: () => context.push('/admin/alerts'),
                ),
                _ActionTile(
                  icon: Icons.menu_book_outlined,
                  title: l10n.knowledgeManagement,
                  subtitle: l10n.knowledgeManagementDesc,
                  onTap: () => context.push('/admin/knowledge'),
                ),

                const SizedBox(height: 28),

                // ── System Health ──
                Text(
                  l10n.systemHealth,
                  style: GoogleFonts.lexend(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                _HealthCard(totalReports: counts[5], activeAlerts: counts[4]),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Summary Grid ───────────────────────────────────────────────────────────────
class _SummaryGrid extends StatelessWidget {
  final List<int?> counts;
  final bool canManageUsers;
  const _SummaryGrid({required this.counts, required this.canManageUsers});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.35,
      children: [
        _StatCard(
          l10n.pendingApprovals,
          counts[0],
          Colors.orange,
          Icons.hourglass_top,
          onTap: canManageUsers
              ? () => context.push('/admin/users?filter=pending')
              : null,
        ),
        _StatCard(
          l10n.pendingReports,
          counts[1],
          AppColors.primaryRed,
          Icons.report_outlined,
          onTap: () => context.push('/admin/reports'),
        ),
        _StatCard(
          l10n.verifiedReports,
          counts[2],
          Colors.deepOrange,
          Icons.warning_amber,
          onTap: () => context.push('/admin/reports'),
        ),
        _StatCard(
          l10n.totalUsers,
          counts[3],
          Colors.teal,
          Icons.group_outlined,
          onTap: canManageUsers ? () => context.push('/admin/users') : null,
        ),
        _StatCard(
          l10n.activeAlertsAdmin,
          counts[4],
          Colors.red.shade800,
          Icons.campaign_outlined,
          onTap: () => context.push('/admin/alerts'),
        ),
        _StatCard(
          l10n.totalReports,
          counts[5],
          Colors.indigo,
          Icons.bar_chart_outlined,
          onTap: () => context.push('/admin/reports'),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int? count;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;

  const _StatCard(this.label, this.count, this.color, this.icon, {this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 26),
            const Spacer(),
            Text(
              count?.toString() ?? '—',
              style: GoogleFonts.lexend(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.lexend(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Action Tile ────────────────────────────────────────────────────────────────
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final int? badge;
  final Color badgeColor;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge,
    this.badgeColor = AppColors.primaryRed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primaryRed.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.primaryRed, size: 24),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.lexend(fontWeight: FontWeight.w600),
              ),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$badge',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          subtitle,
          style: GoogleFonts.lexend(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}

// ── System Health Card ─────────────────────────────────────────────────────────
class _HealthCard extends StatelessWidget {
  final int? totalReports;
  final int? activeAlerts;

  const _HealthCard({required this.totalReports, required this.activeAlerts});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          _HealthRow(
            label: context.l10n.adminHealthDatabase,
            status: context.l10n.connected,
            icon: Icons.cloud_done_outlined,
            color: Colors.green,
          ),
          const Divider(height: 16),
          _HealthRow(
            label: context.l10n.activeAlertsAdmin,
            status: activeAlerts == null
                ? context.l10n.commonUnknown
                : activeAlerts == 0
                ? context.l10n.none
                : context.l10n.adminHealthActiveCount(activeAlerts!),
            icon: Icons.campaign_outlined,
            color: activeAlerts == null
                ? Colors.grey
                : activeAlerts! > 0
                ? Colors.orange
                : Colors.green,
          ),
          const Divider(height: 16),
          _HealthRow(
            label: context.l10n.totalReports,
            status: totalReports == null
                ? context.l10n.commonUnknown
                : context.l10n.adminHealthReportCount(totalReports!),
            icon: Icons.bar_chart_outlined,
            color: Colors.indigo,
          ),
        ],
      ),
    );
  }
}

class _HealthRow extends StatelessWidget {
  final String label;
  final String status;
  final IconData icon;
  final Color color;

  const _HealthRow({
    required this.label,
    required this.status,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 10),
        Text(
          label,
          style: GoogleFonts.lexend(
            fontSize: 13,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            status,
            style: GoogleFonts.lexend(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
