import 'package:climate_app/core/widgets/admin_menu_entry.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/core/widgets/location_selector_widget.dart';
import 'package:flutter/material.dart';
import 'package:climate_app/core/services/backend_failure.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'dart:developer' as developer;
import 'package:climate_app/core/l10n/l10n.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/core/utils/screen_security.dart';

/// Whether the database refused to approve an account because it has not
/// confirmed its email / phone yet: the profiles approval guard refuses, and
/// says so in the message it raises.
bool isUnconfirmedApprovalError(Object error) =>
    backendFailureOf(error) == BackendFailure.refused &&
    (backendMessageOf(error) ?? '').toLowerCase().contains('not confirmed');

/// Snack-bar text for a failed profile update on the users screen.
String adminUserWriteErrorMessage(Object error, AppLocalizations l10n) {
  if (isUnconfirmedApprovalError(error)) {
    return l10n.adminUsersApproveUnconfirmed;
  }
  if (SupabaseService.isPermissionDenied(error) ||
      error is DocumentNotFoundException) {
    return l10n.adminUsersNoPermission;
  }
  return l10n.adminUsersUpdateFailed;
}

/// Admin User Management screen.
/// Lists all users with approval status, allows role changes and approval.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key, this.pendingOnly = false});

  /// Open with the "pending approval" filter on (Admin → Pending approvals).
  final bool pendingOnly;

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen>
    with ScreenSecurityMixin<AdminUsersScreen> {
  String _roleFilter = 'all';
  bool _pendingOnly = false;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  static const int _pageSize = 50;

  final List<Map<String, dynamic>> _users = [];
  bool _loading = false;
  bool _hasMore = true;
  LocalizedText? _error;

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
        setState(() => _error = (l) => l.adminUsersLoadError);
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

  /// Display name of a stored role value.
  String _roleLabel(String role) =>
      UserRoleValue.fromDb(role)?.label(context.l10n) ?? role;

  void _showWriteError(Object e) {
    developer.log('User update failed: $e', name: 'AdminUsersScreen');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(adminUserWriteErrorMessage(e, context.l10n)),
        backgroundColor: Colors.red,
        // Long enough to read the reason an approval was refused.
        duration: const Duration(seconds: 6),
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
          content: Text(
            approved
                ? context.l10n.adminUsersApproved
                : context.l10n.adminUsersRejected,
          ),
          backgroundColor: approved ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _changeRole(String uid, String currentRole) async {
    final roleOptions = _roles.where((r) => r != 'all').toList();
    String? selected = currentRole;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          context.l10n.adminUsersChangeRole,
          style: GoogleFonts.lexend(),
        ),
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
                          _roleLabel(r),
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
            child: Text(context.l10n.cancel),
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
                    SnackBar(content: Text(context.l10n.adminUsersRoleUpdated)),
                  );
                }
              }
            },
            child: Text(
              context.l10n.adminUsersApply,
              style: const TextStyle(color: Colors.white),
            ),
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
            title: Text(
              context.l10n.adminUsersChangeLocationTitle,
              style: GoogleFonts.lexend(),
            ),
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
                child: Text(context.l10n.cancel),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryRed,
                ),
                onPressed: complete ? () => Navigator.pop(ctx, true) : null,
                child: Text(
                  context.l10n.adminUsersApply,
                  style: const TextStyle(color: Colors.white),
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
        SnackBar(
          content: Text(
            context.l10n.adminUsersLocationUpdated(
              ward ?? '',
              lga ?? '',
              state ?? '',
            ),
          ),
        ),
      );
    }
  }

  /// Blocks / unblocks an account. The database applies or lifts the
  /// Auth ban itself when is_disabled changes; its errors surface here.
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
          content: Text(
            disabled
                ? context.l10n.adminUsersDisabled
                : context.l10n.adminUsersReenabled,
          ),
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
          context.l10n.userManagement,
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
                    hintText: context.l10n.adminUsersSearchHint,
                    hintStyle: GoogleFonts.lexend(
                      fontSize: 13,
                      color: Colors.grey.shade400,
                    ),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            tooltip: context.l10n.commonClearSearch,
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
                                    ? context.l10n.adminUsersAllRoles
                                    : (_roleLabel(r)),
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
                        ? context.l10n.adminUsersShowingPending
                        : context.l10n.adminUsersShowingApproved,
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
                          _error?.call(context.l10n) ??
                              context.l10n.adminUsersEmpty,
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
                              child: Text(context.l10n.adminReportsLoadMore),
                            ),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Center(
                            child: OutlinedButton(
                              onPressed: _reload,
                              child: Text(context.l10n.retry),
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
                      final name =
                          d['name'] as String? ?? context.l10n.commonUnknown;
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
                                  _Chip(_roleLabel(role), Colors.blue),
                                  const SizedBox(width: 4),
                                  if (!approved)
                                    _Chip(
                                      context.l10n.adminUsersPendingChip,
                                      Colors.orange,
                                    ),
                                  if (approved && !verified)
                                    _Chip(
                                      context.l10n.profileUnverified,
                                      Colors.grey,
                                    ),
                                  if (approved && verified)
                                    _Chip(
                                      context.l10n.alertStatusActive,
                                      Colors.green,
                                    ),
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
                                PopupMenuItem(
                                  value: 'approve',
                                  child: AdminMenuEntry(
                                    icon: Icons.check_circle_outline,
                                    label: context.l10n.adminUsersApproveMenu,
                                  ),
                                ),
                              if (approved)
                                PopupMenuItem(
                                  value: 'reject',
                                  child: AdminMenuEntry(
                                    icon: Icons.cancel_outlined,
                                    label: context.l10n.adminUsersRevokeMenu,
                                  ),
                                ),
                              PopupMenuItem(
                                value: 'role',
                                child: AdminMenuEntry(
                                  icon: Icons.swap_horiz,
                                  label: context.l10n.adminUsersChangeRoleMenu,
                                ),
                              ),
                              PopupMenuItem(
                                value: 'location',
                                child: AdminMenuEntry(
                                  icon: Icons.place_outlined,
                                  label:
                                      context.l10n.adminUsersChangeLocationMenu,
                                ),
                              ),
                              const PopupMenuDivider(),
                              PopupMenuItem(
                                value: d['isDisabled'] == true
                                    ? 'enable'
                                    : 'disable',
                                child: AdminMenuEntry(
                                  icon: d['isDisabled'] == true
                                      ? Icons.lock_open
                                      : Icons.block,
                                  label: d['isDisabled'] == true
                                      ? context.l10n.adminUsersReenableMenu
                                      : context.l10n.adminUsersDisableMenu,
                                  color: d['isDisabled'] == true
                                      ? Colors.green
                                      : Colors.red,
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
            child: Text(context.l10n.adminReportsLoadMoreError),
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
          label: Text(context.l10n.adminReportsLoadMore),
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
