import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/core/widgets/location_selector_widget.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'dart:developer' as developer;

/// Admin User Management screen.
/// Lists all users with approval status, allows role changes and approval.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key, this.pendingOnly = false});

  /// Open with the "pending approval" filter on (Admin → Pending approvals).
  final bool pendingOnly;

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  String _roleFilter = 'all';
  bool _pendingOnly = false;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  static const int _pageSize = 50;

  final List<Map<String, dynamic>> _users = [];
  bool _loading = false;
  bool _hasMore = true;
  String? _error;

  /// Bumped on every reload so responses for a stale filter are dropped.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _pendingOnly = widget.pendingOnly;
    _reload();
  }

  Future<void> _reload() {
    _generation++;
    setState(() {
      _users.clear();
      _hasMore = true;
      _error = null;
      _loading = false;
    });
    return _loadMore();
  }

  /// Loads the next page, newest first. Role and approval filters are
  /// applied by the server; the name/email search filters loaded rows.
  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    final generation = _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await SupabaseService().listDocuments(
        collectionId: AppConfig.usersCollection,
        queries: [
          if (_roleFilter != 'all') FQuery.equal('role', _roleFilter),
          FQuery.equal('isApproved', !_pendingOnly),
          FQuery.orderDesc('createdAt'),
        ],
        limitCount: _pageSize,
        offset: _users.length,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        final known = _users.map((u) => u[r'$id']).toSet();
        _users.addAll(page.where((u) => !known.contains(u[r'$id'])));
        _hasMore = page.length == _pageSize;
      });
    } on Exception catch (e) {
      developer.log('Users load failed: $e', name: 'AdminUsersScreen');
      if (mounted && generation == _generation) {
        setState(
          () => _error =
              'Could not load users. You may not have permission to view them.',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  bool _matchesFilters(Map<String, dynamic> data) {
    if (_roleFilter != 'all' && (data['role'] ?? 'user') != _roleFilter) {
      return false;
    }
    final isApproved = data['isApproved'] as bool? ?? false;
    return _pendingOnly ? !isApproved : isApproved;
  }

  /// Replaces [uid] with the updated row, dropping it when it no longer
  /// matches the active filters.
  void _applyUpdate(String uid, Map<String, dynamic> updated) {
    if (!mounted) return;
    setState(() {
      final i = _users.indexWhere((u) => u[r'$id'] == uid);
      if (i == -1) return;
      if (_matchesFilters(updated)) {
        _users[i] = updated;
      } else {
        _users.removeAt(i);
      }
    });
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
    'ldp_coordinator',
    'project_staff',
    'admin',
    'techSupport',
  ];
  static const _roleLabels = {
    'user': 'User',
    'ewm': 'EW Monitor',
    'ewv': 'EW Verifier',
    'ewr': 'EW Responder',
    'ldp_coordinator': 'LDP Coordinator',
    'project_staff': 'Project Staff',
    'admin': 'Admin',
    'techSupport': 'Tech Support',
  };

  void _showWriteError(Object e) {
    developer.log('User update failed: $e', name: 'AdminUsersScreen');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          SupabaseService.isPermissionDenied(e) ||
                  e is DocumentNotFoundException
              ? 'You do not have permission to change this user.'
              : 'Update failed. Please try again.',
        ),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _update(String uid, Map<String, dynamic> data) async {
    final updated = await SupabaseService().updateDocument(
      collectionId: AppConfig.usersCollection,
      documentId: uid,
      data: data,
    );
    _applyUpdate(uid, updated);
  }

  Future<void> _setApproval(String uid, bool approved) async {
    try {
      await _update(uid, {'isApproved': approved});
    } on Exception catch (e) {
      _showWriteError(e);
      return;
    }
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
                try {
                  await _update(uid, {'role': selected});
                } on Exception catch (e) {
                  _showWriteError(e);
                  return;
                }
                developer.log(
                  'Role changed: $uid → $selected',
                  name: 'AdminUsersScreen',
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Role updated. It takes effect once the user is approved.',
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

  /// Moves a user to another state / LGA / ward. Approved staff can't
  /// change their own area (ward-scoped access), so admins do it here.
  Future<void> _changeLocation(String uid, Map<String, dynamic> user) async {
    String? state = user['state'] as String?;
    String? lga = user['lga'] as String?;
    String? ward = user['ward'] as String?;
    final apply = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final complete =
              (state?.isNotEmpty ?? false) &&
              (lga?.isNotEmpty ?? false) &&
              (ward?.isNotEmpty ?? false);
          return AlertDialog(
            title: Text('Change location', style: GoogleFonts.lexend()),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: LocationSelectorWidget(
                  initialState: state,
                  initialLGA: lga,
                  initialWard: ward,
                  required: true,
                  onLocationChanged: (s, l, w) => setS(() {
                    state = s;
                    lga = l;
                    ward = w;
                  }),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryRed,
                ),
                onPressed: complete ? () => Navigator.pop(ctx, true) : null,
                child: const Text(
                  'Apply',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          );
        },
      ),
    );
    if (apply != true || !mounted) return;
    try {
      await _update(uid, {'state': state, 'lga': lga, 'ward': ward});
    } on Exception catch (e) {
      _showWriteError(e);
      return;
    }
    developer.log(
      'Location changed: $uid → $ward, $lga',
      name: 'AdminUsersScreen',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Location updated to $ward, $lga, $state')),
      );
    }
  }

  Future<void> _setDisabled(String uid, bool disabled) async {
    try {
      await _update(uid, {'isDisabled': disabled});
    } on Exception catch (e) {
      _showWriteError(e);
      return;
    }
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
                              onSelected: (_) {
                                if (_roleFilter == r) return;
                                setState(() => _roleFilter = r);
                                _reload();
                              },
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
                    _pendingOnly
                        ? 'Showing Pending Approvals'
                        : 'Showing Approved Users',
                    style: GoogleFonts.lexend(fontSize: 13),
                  ),
                  value: _pendingOnly,
                  activeThumbColor: AppColors.primaryRed,
                  onChanged: (v) {
                    setState(() => _pendingOnly = v);
                    _reload();
                  },
                ),
              ],
            ),
          ),
          // ── List ──
          Expanded(
            child: Builder(
              builder: (context) {
                final docs = _users.where((data) {
                  if (_searchQuery.isEmpty) return true;
                  final name = (data['name'] as String? ?? '').toLowerCase();
                  final email = (data['email'] as String? ?? '').toLowerCase();
                  return name.contains(_searchQuery) ||
                      email.contains(_searchQuery);
                }).toList();

                if (docs.isEmpty && _loading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (docs.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: _reload,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(48),
                      children: [
                        Text(
                          _error ?? 'No users found',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.lexend(
                            color: _error != null
                                ? Colors.red
                                : AppColors.textSecondary,
                          ),
                        ),
                        if (_error == null && _hasMore) ...[
                          const SizedBox(height: 12),
                          Center(
                            child: OutlinedButton(
                              onPressed: _loadMore,
                              child: const Text('Load more'),
                            ),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Center(
                            child: OutlinedButton(
                              onPressed: _reload,
                              child: const Text('Retry'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: docs.length + 1,
                    itemBuilder: (_, i) {
                      if (i == docs.length) return _buildFooter();
                      final d = docs[i];
                      final uid = d['\$id'] as String;
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
                              if (action == 'location') {
                                _changeLocation(uid, d);
                              }
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
                              const PopupMenuItem(
                                value: 'location',
                                child: Text('📍 Change location'),
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
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: TextButton(
            onPressed: _loadMore,
            child: const Text('Could not load more. Tap to retry.'),
          ),
        ),
      );
    }
    if (!_hasMore) return const SizedBox(height: 24);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: _loadMore,
          icon: const Icon(Icons.expand_more),
          label: const Text('Load more'),
        ),
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
