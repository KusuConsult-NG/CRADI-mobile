import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:climate_app/core/theme/app_colors.dart';

/// Admin Dashboard — entry point for admin and techSupport roles.
/// Shows live summary cards for pending users, open reports, and system health.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  Future<int> _count(String collection, {Map<String, dynamic>? where}) async {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection(
      collection,
    );
    if (where != null) {
      where.forEach((k, v) => q = q.where(k, isEqualTo: v));
    }
    final snap = await q.count().get();
    return snap.count ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Admin Portal',
          style: GoogleFonts.lexend(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.primaryRed,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<int>>(
        future: Future.wait([
          _count('users', where: {'isApproved': false}),
          _count('reports', where: {'status': 'pending'}),
          _count('reports', where: {'status': 'escalated'}),
          _count('users'),
          _count('alerts', where: {'isActive': true}),
          _count('reports'),
        ]),
        builder: (context, snap) {
          final counts = snap.data ?? [0, 0, 0, 0, 0, 0];
          return RefreshIndicator(
            onRefresh: () async => (context as Element).markNeedsBuild(),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // ── System Overview header ──
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'System Overview',
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
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _SummaryGrid(counts: counts),
                const SizedBox(height: 28),

                // ── Quick Actions ──
                Text(
                  'Quick Actions',
                  style: GoogleFonts.lexend(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),

                _ActionTile(
                  icon: Icons.supervised_user_circle_outlined,
                  title: 'User Management',
                  subtitle: 'Approve accounts, assign roles, deactivate users',
                  badge: counts[0] > 0 ? counts[0] : null,
                  onTap: () => context.push('/admin/users'),
                ),
                _ActionTile(
                  icon: Icons.assessment_outlined,
                  title: 'Reports Overview',
                  subtitle: 'View, validate, or reject reports across all LGAs',
                  badge: counts[2] > 0 ? counts[2] : null,
                  badgeColor: Colors.orange,
                  onTap: () => context.push('/admin/reports'),
                ),
                _ActionTile(
                  icon: Icons.campaign_outlined,
                  title: 'Alerts & Broadcast',
                  subtitle: 'Send emergency alerts to users or specific areas',
                  badge: counts[4] > 0 ? counts[4] : null,
                  badgeColor: Colors.deepOrange,
                  onTap: () => context.push('/admin/alerts'),
                ),
                _ActionTile(
                  icon: Icons.menu_book_outlined,
                  title: 'Knowledge Management',
                  subtitle: 'Add, edit, or remove emergency knowledge guides',
                  onTap: () => context.push('/admin/knowledge'),
                ),

                const SizedBox(height: 28),

                // ── System Health ──
                Text(
                  'System Health',
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
  final List<int> counts;
  const _SummaryGrid({required this.counts});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.35,
      children: [
        _StatCard(
          'Pending Approvals',
          counts[0],
          Colors.orange,
          Icons.hourglass_top,
        ),
        _StatCard(
          'Pending Reports',
          counts[1],
          AppColors.primaryRed,
          Icons.report_outlined,
        ),
        _StatCard(
          'Escalated Reports',
          counts[2],
          Colors.deepOrange,
          Icons.warning_amber,
        ),
        _StatCard('Total Users', counts[3], Colors.teal, Icons.group_outlined),
        _StatCard(
          'Active Alerts',
          counts[4],
          Colors.red.shade800,
          Icons.campaign_outlined,
        ),
        _StatCard(
          'Total Reports',
          counts[5],
          Colors.indigo,
          Icons.bar_chart_outlined,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;
  const _StatCard(this.label, this.count, this.color, this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
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
            '$count',
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
  final int totalReports;
  final int activeAlerts;

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
          const _HealthRow(
            label: 'Firestore',
            status: 'Connected',
            icon: Icons.cloud_done_outlined,
            color: Colors.green,
          ),
          const Divider(height: 16),
          _HealthRow(
            label: 'Active Alerts',
            status: activeAlerts == 0 ? 'None' : '$activeAlerts active',
            icon: Icons.campaign_outlined,
            color: activeAlerts > 0 ? Colors.orange : Colors.green,
          ),
          const Divider(height: 16),
          _HealthRow(
            label: 'Total Reports',
            status: '$totalReports reports',
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
