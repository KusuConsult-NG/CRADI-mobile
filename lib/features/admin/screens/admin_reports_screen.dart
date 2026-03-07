import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'dart:developer' as developer;

/// Admin Reports Overview screen.
/// Lists all reports across all LGAs with status filters and manual actions.
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  String _statusFilter = 'all';

  static const _statuses = [
    'all',
    'pending',
    'escalated',
    'validated',
    'rejected',
  ];
  static const _statusColors = {
    'pending': Colors.orange,
    'escalated': Colors.deepOrange,
    'validated': Colors.green,
    'rejected': Colors.red,
  };

  Query<Map<String, dynamic>> get _query {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('reports')
        .orderBy('createdAt', descending: true);
    if (_statusFilter != 'all') {
      q = q.where('status', isEqualTo: _statusFilter);
    }
    return q;
  }

  Future<void> _updateStatus(String reportId, String newStatus) async {
    await FirebaseFirestore.instance
        .collection('reports')
        .doc(reportId)
        .update({
          'status': newStatus,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': 'admin',
        });
    developer.log('Report $reportId → $newStatus', name: 'AdminReportsScreen');
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Report marked as $newStatus')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Reports Overview',
          style: GoogleFonts.lexend(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.primaryRed,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // ── Status filters ──
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _statuses
                    .map(
                      (s) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(
                            s == 'all' ? 'All' : s.capitalize(),
                            style: GoogleFonts.lexend(fontSize: 12),
                          ),
                          selected: _statusFilter == s,
                          selectedColor: _statusFilter == s
                              ? (_statusColors[s] ?? AppColors.primaryRed)
                              : null,
                          labelStyle: TextStyle(
                            color: _statusFilter == s ? Colors.white : null,
                          ),
                          onSelected: (_) => setState(() => _statusFilter = s),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          // ── List ──
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _query.snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      'No reports found',
                      style: GoogleFonts.lexend(color: AppColors.textSecondary),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final d = docs[i].data();
                    final id = docs[i].id;
                    final hazard = d['hazardType'] as String? ?? 'Unknown';
                    final lga = d['lga'] as String? ?? '';
                    final ward = d['ward'] as String? ?? '';
                    final status = d['status'] as String? ?? 'pending';
                    final severity = d['severity'] as String? ?? '';
                    final createdAt = d['createdAt'];
                    String timeStr = '';
                    if (createdAt is Timestamp) {
                      final dt = createdAt.toDate();
                      timeStr = '${dt.day}/${dt.month}/${dt.year}';
                    }

                    final statusColor = _statusColors[status] ?? Colors.grey;

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.report_outlined,
                            color: statusColor,
                            size: 24,
                          ),
                        ),
                        title: Text(
                          hazard,
                          style: GoogleFonts.lexend(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$ward, $lga',
                              style: GoogleFonts.lexend(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                _chip(status.capitalize(), statusColor),
                                if (severity.isNotEmpty) ...[
                                  const SizedBox(width: 4),
                                  _chip(severity, Colors.purple),
                                ],
                                if (timeStr.isNotEmpty) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    timeStr,
                                    style: GoogleFonts.lexend(
                                      fontSize: 10,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) => _updateStatus(id, action),
                          itemBuilder: (_) => [
                            if (status != 'validated')
                              const PopupMenuItem(
                                value: 'validated',
                                child: Text('✅ Validate'),
                              ),
                            if (status != 'rejected')
                              const PopupMenuItem(
                                value: 'rejected',
                                child: Text('❌ Reject'),
                              ),
                            if (status != 'escalated')
                              const PopupMenuItem(
                                value: 'escalated',
                                child: Text('⚠️ Escalate'),
                              ),
                            if (status != 'pending')
                              const PopupMenuItem(
                                value: 'pending',
                                child: Text('🔄 Reset to pending'),
                              ),
                          ],
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: GoogleFonts.lexend(
        fontSize: 10,
        color: color,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

extension _StringExt on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
