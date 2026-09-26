import 'package:climate_app/core/constants/hazards.dart';
import 'package:climate_app/core/services/offline_storage_service.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/shared/widgets/app_card.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart';
import 'package:climate_app/shared/widgets/custom_button.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/core/providers/connectivity_provider.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';

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
    return DateFormat('MMM d, h:mm a').format(date);
  }

  /// Drafts plus unsynced sync-queue items of the signed-in user, newest
  /// first. Empty while offline storage is not initialised.
  List<_PendingItem> _pendingItems() {
    final storage = OfflineStorageService();
    if (!storage.isInitialized) return const [];
    final uid = context.read<AuthProvider>().currentUser?.id;
    final items = <_PendingItem>[
      for (final d in storage.getAllDrafts())
        _PendingItem(
          title: Hazard.labelFor(d['hazardType']),
          subtitle: (d['locationDetails'] ?? '').toString(),
          date: d['createdAt'],
          failed: d['status'] == OfflineStorageService.statusRejected,
          error: d['lastError']?.toString(),
        ),
      for (final q in storage.getUnsyncedItems(userId: uid))
        _PendingItem(
          title: Hazard.labelFor(_queueData(q)['hazardType']),
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
    ).showSnackBar(const SnackBar(content: Text('Syncing pending data...')));
    await reporting.syncPendingReports(context);
  }

  Future<void> _onFailedItemAction(String action, String queueId) async {
    final storage = OfflineStorageService();
    if (action == 'retry') {
      await storage.retryQueueItem(queueId);
    } else {
      await storage.discardQueueItem(queueId);
    }
    if (mounted) setState(() {});
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
        title: const Text('Offline Mode'),
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
              'No Internet Connection',
              style: Theme.of(context).textTheme.displayMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isSignedIn
                  ? 'You can still view your saved guides and draft reports.'
                  : 'Reconnect to sign in.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Pending Reports Section
            Text(
              'Pending Reports',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildPendingList()),
            const SizedBox(height: 16),

            CustomButton(
              text: 'Try Reconnecting & Sync',
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
                      content: const Text(
                        'Offline Mode is enabled in Settings.',
                      ),
                      backgroundColor: Colors.orange,
                      action: isSignedIn
                          ? SnackBarAction(
                              label: 'Settings',
                              onPressed: () => context.push('/settings'),
                              textColor: Colors.white,
                            )
                          : SnackBarAction(
                              label: 'Go online',
                              onPressed: () =>
                                  connectivityProvider.setManualOffline(false),
                              textColor: Colors.white,
                            ),
                    ),
                  );
                }

                if (!isOnline && !connectivityProvider.manualOffline) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Still no internet connection'),
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
                text: 'Create New Report',
                onPressed: () => context.push('/report'),
                icon: Icons.add_circle_outline,
              ),
              const SizedBox(height: 16),
              CustomButton(
                text: 'Open Settings',
                type: ButtonType.secondary,
                onPressed: () => context.push('/settings'),
                icon: Icons.settings,
              ),
              const SizedBox(height: 16),
              CustomButton(
                text: 'View Saved Guides',
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

  Widget _buildPendingList() {
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
              'No pending reports',
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
          final status = item.failed
              ? 'Failed, will not sync automatically'
                    '${item.error != null ? ': ${item.error}' : ''}'
              : 'Waiting to sync';
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppCard(
              child: ListTile(
                leading: Icon(
                  item.failed ? Icons.error_outline : Icons.schedule,
                  color: item.failed ? Colors.red : AppColors.primaryRed,
                ),
                title: Text(
                  item.title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${item.subtitle}\n${_formatDate(item.date)} • $status',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                isThreeLine: true,
                trailing: item.failed && item.queueId != null
                    ? PopupMenuButton<String>(
                        onSelected: (action) =>
                            _onFailedItemAction(action, item.queueId!),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'retry', child: Text('Retry')),
                          PopupMenuItem(
                            value: 'discard',
                            child: Text('Discard'),
                          ),
                        ],
                      )
                    : null,
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
  });

  final String title;
  final String subtitle;
  final Object? date;
  final bool failed;
  final String? error;
  final String? queueId;
}
