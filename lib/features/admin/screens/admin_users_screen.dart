import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'dart:developer' as developer;

/// Admin User Management screen.
/// Lists all users with approval status, allows role changes and approval.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  String _roleFilter = 'all';
  bool _pendingOnly = false;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  static const _roles = [
    'all',
    'user',
    'ewm',
    'ewv',
    'ewr',
    'admin',
    'techSupport',
  ];
  static const _roleLabels = {
    'user': 'User',
    'ewm': 'EW Monitor',
    'ewv': 'EW Verifier',
    'ewr': 'EW Responder',
    'admin': 'Admin',
    'techSupport': 'Tech Support',
  };

  Query<Map<String, dynamic>> get _query {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('users')
        .orderBy('createdAt', descending: true);
    if (_roleFilter != 'all') q = q.where('role', isEqualTo: _roleFilter);
    if (_pendingOnly) q = q.where('isApproved', isEqualTo: false);
    return q;
  }

  Future<void> _setApproval(String uid, bool approved) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'isApproved': approved,
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approved ? 'User approved' : 'User rejected'),
          backgroundColor: approved ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _changeRole(String uid, String currentRole) async {
    final roleOptions = _roleLabels.keys.toList();
    String? selected = currentRole;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Change Role', style: GoogleFonts.lexend()),
        content: StatefulBuilder(
          builder: (ctx, setS) => SizedBox(
            width: double.maxFinite,
            child: RadioGroup<String>(
              groupValue: selected ?? '',
              onChanged: (v) => setS(() => selected = v),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: roleOptions
                    .map(
                      (r) => RadioListTile<String>(
                        dense: true,
                        title: Text(
                          _roleLabels[r] ?? r,
                          style: GoogleFonts.lexend(fontSize: 14),
                        ),
                        value: r,
                        activeColor: AppColors.primaryRed,
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryRed,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              if (selected != null && selected != currentRole) {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .update({'role': selected});
                developer.log(
                  'Role changed: $uid → $selected',
                  name: 'AdminUsersScreen',
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Role updated. User must re-login for it to take effect.',
                      ),
                    ),
                  );
                }
              }
            },
            child: const Text('Apply', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _setDisabled(String uid, bool disabled) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'isDisabled': disabled,
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(disabled ? 'User disabled' : 'User re-enabled'),
          backgroundColor: disabled ? Colors.red : Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'User Management',
          style: GoogleFonts.lexend(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.primaryRed,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // ── Search bar ──
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Column(
              children: [
                // Search
                TextField(
                  controller: _searchCtrl,
                  onChanged: (v) =>
                      setState(() => _searchQuery = v.toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Search by name or email…',
                    hintStyle: GoogleFonts.lexend(
                      fontSize: 13,
                      color: Colors.grey.shade400,
                    ),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // Role filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _roles
                        .map(
                          (r) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(
                                r == 'all'
                                    ? 'All Roles'
                                    : (_roleLabels[r] ?? r),
                                style: GoogleFonts.lexend(fontSize: 12),
                              ),
                              selected: _roleFilter == r,
                              selectedColor: AppColors.primaryRed,
                              labelStyle: TextStyle(
                                color: _roleFilter == r ? Colors.white : null,
                              ),
                              onSelected: (_) =>
                                  setState(() => _roleFilter = r),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    'Pending approval only',
                    style: GoogleFonts.lexend(fontSize: 13),
                  ),
                  value: _pendingOnly,
                  activeThumbColor: AppColors.primaryRed,
                  onChanged: (v) => setState(() => _pendingOnly = v),
                ),
              ],
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
                final allDocs = snap.data?.docs ?? [];
                // Apply in-memory search filter
                final docs = _searchQuery.isEmpty
                    ? allDocs
                    : allDocs.where((d) {
                        final data = d.data();
                        final name = (data['name'] as String? ?? '')
                            .toLowerCase();
                        final email = (data['email'] as String? ?? '')
                            .toLowerCase();
                        return name.contains(_searchQuery) ||
                            email.contains(_searchQuery);
                      }).toList();
                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      'No users found',
                      style: GoogleFonts.lexend(color: AppColors.textSecondary),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final d = docs[i].data();
                    final uid = docs[i].id;
                    final name = d['name'] as String? ?? 'Unknown';
                    final email = d['email'] as String? ?? '';
                    final role = d['role'] as String? ?? 'user';
                    final approved = d['isApproved'] as bool? ?? false;
                    final verified = d['isVerified'] as bool? ?? false;

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: approved
                              ? AppColors.primaryRed.withValues(alpha: 0.15)
                              : Colors.orange.withValues(alpha: 0.15),
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: TextStyle(
                              color: approved
                                  ? AppColors.primaryRed
                                  : Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          name,
                          style: GoogleFonts.lexend(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              email,
                              style: GoogleFonts.lexend(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                _Chip(_roleLabels[role] ?? role, Colors.blue),
                                const SizedBox(width: 4),
                                if (!approved)
                                  const _Chip('Pending', Colors.orange),
                                if (approved && !verified)
                                  const _Chip('Unverified', Colors.grey),
                                if (approved && verified)
                                  const _Chip('Active', Colors.green),
                              ],
                            ),
                          ],
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) {
                            if (action == 'approve') _setApproval(uid, true);
                            if (action == 'reject') _setApproval(uid, false);
                            if (action == 'role') _changeRole(uid, role);
                            if (action == 'disable') _setDisabled(uid, true);
                            if (action == 'enable') _setDisabled(uid, false);
                          },
                          itemBuilder: (_) => [
                            if (!approved)
                              const PopupMenuItem(
                                value: 'approve',
                                child: Text('✅ Approve'),
                              ),
                            if (approved)
                              const PopupMenuItem(
                                value: 'reject',
                                child: Text('❌ Revoke access'),
                              ),
                            const PopupMenuItem(
                              value: 'role',
                              child: Text('🔄 Change role'),
                            ),
                            const PopupMenuDivider(),
                            PopupMenuItem(
                              value: d['isDisabled'] == true
                                  ? 'enable'
                                  : 'disable',
                              child: Text(
                                d['isDisabled'] == true
                                    ? '🔓 Re-enable user'
                                    : '🚫 Disable user',
                                style: TextStyle(
                                  color: d['isDisabled'] == true
                                      ? Colors.green
                                      : Colors.red,
                                ),
                              ),
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
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
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
}
