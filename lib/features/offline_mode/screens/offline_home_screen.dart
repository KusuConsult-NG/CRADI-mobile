import 'package:climate_app/core/constants/hazards.dart';
import 'package:climate_app/core/services/offline_storage_service.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/shared/widgets/app_card.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart';
import 'package:climate_app/shared/widgets/custom_button.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/core/providers/connectivity_provider.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/core/l10n/l10n.dart';

class OfflineHomeScreen extends StatefulWidget {
  const OfflineHomeScreen({super.key});

  @override
  State<OfflineHomeScreen> createState() => _OfflineHomeScreenState();
}

class _OfflineHomeScreenState extends State<OfflineHomeScreen> {
  String _formatDate(Object? isoString) {
    if (isoString == null) return '';
    final date = DateTime.tryParse(isoString.toString())?.toLocal();
    if (date == null) return '';
    return localizedDateFormat(context, 'MMM d, h:mm a').format(date);
  }

  /// Drafts plus unsynced sync-queue items of the signed-in user, newest
  /// first. Empty while offline storage is not initialised.
  List<_PendingItem> _pendingItems() {
    final storage = OfflineStorageService();
    if (!storage.isInitialized) return const [];
    final uid = context.read<AuthProvider>().currentUser?.id;
    final items = <_PendingItem>[
      for (final d in storage.getDraftsFor(uid))
        _PendingItem(
          title: Hazard.labelFor(d['hazardType'], context.l10n),
          subtitle: (d['locationDetails'] ?? '').toString(),
          date: d['createdAt'],
          failed: d['status'] == OfflineStorageService.statusRejected,
          error: d['lastError']?.toString(),
          draftId: d['id'] as String?,
          ownerless: OfflineStorageService.draftOwner(d) == null,
        ),
      for (final q in storage.getUnsyncedItems(userId: uid))
        _PendingItem(
          title: Hazard.labelFor(_queueData(q)['hazardType'], context.l10n),
          subtitle: (_queueData(q)['locationDetails'] ?? '').toString(),
          date: q['addedToQueueAt'],
          failed: OfflineStorageService.isTerminalFailure(q),
          error: q['lastError']?.toString(),
          queueId: q['queueId'] as String?,
        ),
    ];
    items.sort((a, b) => '${b.date}'.compareTo('${a.date}'));
    return items;
  }

  static Map _queueData(Map<String, dynamic> item) =>
      item['data'] is Map ? item['data'] as Map : item;

  Future<void> _sync() async {
    final reporting = context.read<ReportingProvider>();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.offlineSyncingPending)));
    await reporting.syncPendingReports(context);
  }

  /// Discarding deletes the report for good: ask first.
  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(context.l10n.offlineDiscardTitle),
        content: Text(context.l10n.offlineDiscardBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(
              context.l10n.offlineDiscard,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _onQueueItemAction(String action, String queueId) async {
    final storage = OfflineStorageService();
    if (action == 'retry') {
      await storage.retryQueueItem(queueId);
    } else {
      if (!await _confirmDiscard()) return;
      await storage.discardQueueItem(queueId);
    }
    if (mounted) setState(() {});
  }

  /// Retry (a refused draft), submit as the signed-in user (an ownerless
  /// draft of an older build) or discard a draft.
  Future<void> _onDraftAction(String action, String draftId) async {
    final storage = OfflineStorageService();
    final uid = context.read<AuthProvider>().currentUser?.id;
    final connectivity = context.read<ConnectivityProvider>();
    switch (action) {
      case 'discard':
        if (!await _confirmDiscard()) return;
        await storage.deleteDraft(draftId);
      case 'retry':
        await storage.updateDraft(draftId, {'status': 'draft'});
      case 'submit':
        if (uid == null) return;
        await storage.updateDraft(draftId, {'userId': uid, 'status': 'draft'});
    }
    if (!mounted) return;
    setState(() {});
    if (action != 'discard' && connectivity.isOnline) {
      await _sync();
      if (mounted) setState(() {});
    }
  }

  /// Every pending item can be discarded (e.g. a draft the user no longer
  /// wants, or one that keeps failing); failed / ownerless ones also offer
  /// retry / submit.
  Widget? _itemActions(_PendingItem item, bool isSignedIn) {
    final draftId = item.draftId;
    if (draftId != null) {
      return PopupMenuButton<String>(
        tooltip: context.l10n.offlineActions,
        onSelected: (action) => _onDraftAction(action, draftId),
        itemBuilder: (_) => [
          if (item.ownerless && isSignedIn)
            PopupMenuItem(
              value: 'submit',
              child: Text(context.l10n.offlineSubmitAsMe),
            )
          else if (item.failed && !item.ownerless)
            PopupMenuItem(value: 'retry', child: Text(context.l10n.retry)),
          PopupMenuItem(
            value: 'discard',
            child: Text(context.l10n.offlineDiscard),
          ),
        ],
      );
    }
    final queueId = item.queueId;
    if (queueId == null) return null;
    return PopupMenuButton<String>(
      tooltip: context.l10n.offlineActions,
      onSelected: (action) => _onQueueItemAction(action, queueId),
      itemBuilder: (_) => [
        if (item.failed)
          PopupMenuItem(value: 'retry', child: Text(context.l10n.retry)),
        PopupMenuItem(
          value: 'discard',
          child: Text(context.l10n.offlineDiscard),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Reporting, settings and guides are signed-in features; a logged-out
    // user would just be bounced to the login screen.
    final isSignedIn = context.select<AuthProvider, bool>(
      (a) => a.isAuthenticated && !a.isLocked,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.settingsOfflineMode),
        backgroundColor: AppColors.primaryGrey,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.wifi_off, size: 64, color: AppColors.primaryGrey),
            const SizedBox(height: 16),
            Text(
              context.l10n.offlineNoInternet,
              style: Theme.of(context).textTheme.displayMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isSignedIn
                  ? context.l10n.offlineCanViewSaved
                  : context.l10n.offlineReconnectToSignIn,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Pending Reports Section
            Text(
              context.l10n.pendingReports,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildPendingList(isSignedIn)),
            const SizedBox(height: 16),

            CustomButton(
              text: context.l10n.offlineTryReconnect,
              onPressed: () async {
                final connectivityProvider = context
                    .read<ConnectivityProvider>();

                // Force check connectivity
                final isOnline = await connectivityProvider.checkConnectivity();
                if (!context.mounted) return;

                // If manually offline, we should probably tell the user
                if (connectivityProvider.manualOffline) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.l10n.offlineModeEnabledInSettings),
                      backgroundColor: Colors.orange,
                      action: isSignedIn
                          ? SnackBarAction(
                              label: context.l10n.navSettings,
                              onPressed: () => context.push('/settings'),
                              textColor: Colors.white,
                            )
                          : SnackBarAction(
                              label: context.l10n.offlineGoOnline,
                              onPressed: () =>
                                  connectivityProvider.setManualOffline(false),
                              textColor: Colors.white,
                            ),
                    ),
                  );
                }

                if (!isOnline && !connectivityProvider.manualOffline) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.l10n.offlineStillNoInternet),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                if (isOnline) {
                  await _sync();
                  if (!context.mounted) return;
                  // Refresh the pending list.
                  setState(() {});
                  if (_pendingItems().isEmpty) {
                    // Everything synced: back to the dashboard.
                    context.go('/dashboard');
                  }
                }
              },
            ),
            if (isSignedIn) ...[
              const SizedBox(height: 16),
              CustomButton(
                text: context.l10n.myReportsNewReport,
                onPressed: () => context.push('/report'),
                icon: Icons.add_circle_outline,
              ),
              const SizedBox(height: 16),
              CustomButton(
                text: context.l10n.offlineOpenSettings,
                type: ButtonType.secondary,
                onPressed: () => context.push('/settings'),
                icon: Icons.settings,
              ),
              const SizedBox(height: 16),
              CustomButton(
                text: context.l10n.offlineViewSavedGuides,
                type: ButtonType.secondary,
                onPressed: () => context.push('/knowledge-base'),
                icon: Icons.menu_book,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPendingList(bool isSignedIn) {
    final items = _pendingItems();
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 48,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.offlineNoPending,
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        // Trigger sync check
        final isOnline = await context
            .read<ConnectivityProvider>()
            .checkConnectivity();
        if (!mounted) return;
        if (isOnline) {
          await _sync();
          if (!mounted) return;
        }
        // Refresh UI to show what is still pending
        setState(() {});
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final status = item.ownerless
              ? context.l10n.offlineStatusOwnerless
              : item.failed
              ? (item.error != null
                    ? context.l10n.offlineStatusFailedWithError(item.error!)
                    : context.l10n.offlineStatusFailed)
              : context.l10n.offlineStatusWaiting;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppCard(
              child: ListTile(
                leading: Icon(
                  item.failed
                      ? Icons.error_outline
                      : item.ownerless
                      ? Icons.help_outline
                      : Icons.schedule,
                  color: item.failed ? Colors.red : AppColors.primaryRed,
                ),
                title: Text(
                  item.title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  context.l10n.offlineItemSubtitle(
                    item.subtitle,
                    _formatDate(item.date),
                    status,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                isThreeLine: true,
                trailing: _itemActions(item, isSignedIn),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A draft or sync-queue entry shown in the pending list.
class _PendingItem {
  const _PendingItem({
    required this.title,
    required this.subtitle,
    required this.date,
    required this.failed,
    this.error,
    this.queueId,
    this.draftId,
    this.ownerless = false,
  });

  final String title;
  final String subtitle;
  final Object? date;
  final bool failed;
  final String? error;
  final String? queueId;

  /// Set for drafts (null for sync-queue items).
  final String? draftId;

  /// A draft saved by an older build without an author: never synced
  /// automatically; the user submits it as their own or discards it.
  final bool ownerless;
}
