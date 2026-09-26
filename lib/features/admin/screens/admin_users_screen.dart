import 'package:climate_app/core/services/supabase_service.dart';
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
  final SupabaseService _supabase = SupabaseService();
  List<Map<String, dynamic>> _users = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _loading = true);
    try {
      final docs = await _supabase.listDocuments(
        collectionId: 'users',
        queries: [SQuery.orderDesc('created_at'), SQuery.limit(200)],
      );
      if (mounted) setState(() => _users = docs);
    } on Exception catch (e) {
      developer.log('Error loading users: $e', name: 'AdminUsersScreen');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

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

  Future<void> _setApproval(String uid, bool approved) async {
    try {
      await _supabase.updateDocument(
        collectionId: 'users',
        documentId: uid,
        data: {'is_approved': approved},
      );
      _loadUsers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approved ? 'User approved' : 'User rejected'),
            backgroundColor: approved ? Colors.green : Colors.red,
          ),
        );
      }
    } on Exception catch (e) {
      developer.log('Error setting approval: $e', name: 'AdminUsersScreen');
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
                await _supabase.updateDocument(
                  collectionId: 'users',
                  documentId: uid,
                  data: {'role': selected},
                );
                developer.log(
                  'Role changed: $uid → $selected',
                  name: 'AdminUsersScreen',
                );
                _loadUsers();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Role updated successfully.'),
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
    try {
      await _supabase.updateDocument(
        collectionId: 'users',
        documentId: uid,
        data: {'is_disabled': disabled},
      );
      _loadUsers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(disabled ? 'User disabled' : 'User re-enabled'),
            backgroundColor: disabled ? Colors.red : Colors.green,
          ),
        );
      }
    } on Exception catch (e) {
      developer.log('Error updating disabled status: $e', name: 'AdminUsersScreen');
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredUsers = _users.where((data) {
      if (_roleFilter != 'all') {
        final role = data['role'] as String? ?? 'user';
        if (role != _roleFilter) return false;
      }
      final isApproved = (data['is_approved'] ?? data['isApproved']) as bool? ?? false;
      if (_pendingOnly) {
        if (isApproved) return false;
      }

      if (_searchQuery.isNotEmpty) {
        final name = (data['full_name'] ?? data['name'] as String? ?? '').toLowerCase();
        final email = (data['email'] as String? ?? '').toLowerCase();
        if (!name.contains(_searchQuery) && !email.contains(_searchQuery)) {
          return false;
        }
      }

      return true;
    }).toList();

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
          // Search & Filter Bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search by name or email...',
                    hintStyle: GoogleFonts.lexend(fontSize: 13),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.all(10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _roleFilter,
                        decoration: InputDecoration(
                          labelText: 'Role',
                          labelStyle: GoogleFonts.lexend(fontSize: 12),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        items: _roles
                            .map(
                              (r) => DropdownMenuItem(
                                value: r,
                                child: Text(
                                  r == 'all' ? 'All Roles' : (_roleLabels[r] ?? r),
                                  style: GoogleFonts.lexend(fontSize: 12),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _roleFilter = v ?? 'all'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text(
                        'Pending only',
                        style: GoogleFonts.lexend(fontSize: 12),
                      ),
                      selected: _pendingOnly,
                      selectedColor: AppColors.primaryRed.withValues(alpha: 0.2),
                      checkmarkColor: AppColors.primaryRed,
                      onSelected: (v) => setState(() => _pendingOnly = v),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // User List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadUsers,
                    child: filteredUsers.isEmpty
                        ? Center(
                            child: Text(
                              'No users found',
                              style: GoogleFonts.lexend(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredUsers.length,
                            itemBuilder: (_, i) {
                              final d = filteredUsers[i];
                              final uid = (d['id'] ?? d['\$id'] ?? '').toString();
                              final name = (d['full_name'] ?? d['name'] ?? 'Unknown').toString();
                              final email = (d['email'] ?? '').toString();
                              final role = (d['role'] ?? 'user').toString();
                              final approved = (d['is_approved'] ?? d['isApproved']) as bool? ?? false;
                              final verified = (d['is_verified'] ?? d['isVerified']) as bool? ?? false;
                              final disabled = (d['is_disabled'] ?? d['isDisabled']) as bool? ?? false;

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
                                          if (disabled)
                                            const _Chip('Disabled', Colors.red),
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
                                          child: Text('Approve'),
                                        ),
                                      if (approved)
                                        const PopupMenuItem(
                                          value: 'reject',
                                          child: Text('Revoke access'),
                                        ),
                                      const PopupMenuItem(
                                        value: 'role',
                                        child: Text('Change role'),
                                      ),
                                      const PopupMenuDivider(),
                                      PopupMenuItem(
                                        value: disabled ? 'enable' : 'disable',
                                        child: Text(
                                          disabled ? 'Re-enable user' : 'Disable user',
                                          style: TextStyle(
                                            color: disabled ? Colors.green : Colors.red,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  isThreeLine: true,
                                ),
                              );
                            },
                          ),
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
