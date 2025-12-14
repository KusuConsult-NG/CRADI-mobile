import 'package:climate_app/core/providers/connectivity_provider.dart';
import 'package:climate_app/core/services/sync_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Banner widget that displays connectivity status and sync progress
///
/// Shows offline state and triggers sync when connection is restored
class ConnectivityBanner extends StatefulWidget {
  final Widget child;

  const ConnectivityBanner({super.key, required this.child});

  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner> {
  final SyncService _syncService = SyncService();
  bool _isSyncing = false;
  String _syncMessage = '';

  @override
  void initState() {
    super.initState();
    _initSync();
  }

  Future<void> _initSync() async {
    await _syncService.initialize();
  }

  Future<void> _triggerSync() async {
    if (_isSyncing) return;

    setState(() {
      _isSyncing = true;
      _syncMessage = 'Syncing...';
    });

    try {
      final count = await _syncService.syncAll();

      if (mounted) {
        setState(() {
          _syncMessage = count > 0
              ? 'Synced $count ${count == 1 ? "item" : "items"}'
              : 'All synced';
        });

        // Hide success message after 3 seconds
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _isSyncing = false;
              _syncMessage = '';
            });
          }
        });
      }
    } on Exception {
      if (mounted) {
        setState(() {
          _syncMessage = 'Sync failed';
          _isSyncing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectivityProvider>(
      builder: (context, connectivity, _) {
        // Trigger sync when coming back online
        if (connectivity.isOnline &&
            connectivity.initialCheckDone &&
            !_isSyncing &&
            _syncService.hasPendingItems()) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _triggerSync();
          });
        }

        return Column(
          children: [
            // Show banner when offline or syncing
            if (connectivity.isOffline || _isSyncing)
              Material(
                elevation: 4,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  color: connectivity.isOffline
                      ? Colors.orange.shade100
                      : Colors.blue.shade100,
                  child: Row(
                    children: [
                      Icon(
                        _isSyncing ? Icons.sync : Icons.cloud_off,
                        size: 20,
                        color: connectivity.isOffline
                            ? Colors.orange.shade900
                            : Colors.blue.shade900,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _isSyncing
                              ? _syncMessage
                              : 'Offline - Data will sync when connection is restored',
                          style: TextStyle(
                            color: connectivity.isOffline
                                ? Colors.orange.shade900
                                : Colors.blue.shade900,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (_isSyncing)
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.blue.shade900,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            Expanded(child: widget.child),
          ],
        );
      },
    );
  }
}
