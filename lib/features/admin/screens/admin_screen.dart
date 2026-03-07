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
        ]),
        builder: (context, snap) {
          final counts = snap.data ?? [0, 0, 0, 0];
          return RefreshIndicator(
            onRefresh: () async => (context as Element).markNeedsBuild(),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'System Overview',
                  style: GoogleFonts.lexend(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                _SummaryGrid(counts: counts),
                const SizedBox(height: 28),
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
                  subtitle: 'Approve accounts, change roles, deactivate users',
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
              ],
            ),
          );
        },
      ),
    );
  }
}

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
      childAspectRatio: 1.4,
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
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const Spacer(),
          Text(
            '$count',
            style: GoogleFonts.lexend(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.lexend(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

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
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon, color: AppColors.primaryRed, size: 28),
        title: Row(
          children: [
            Text(title, style: GoogleFonts.lexend(fontWeight: FontWeight.w600)),
            if (badge != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
          ],
        ),
        subtitle: Text(
          subtitle,
          style: GoogleFonts.lexend(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
