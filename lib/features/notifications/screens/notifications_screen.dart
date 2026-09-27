import 'package:climate_app/core/constants/hazards.dart';
import 'package:climate_app/core/services/notification_service.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/shared/widgets/app_card.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:climate_app/core/l10n/l10n.dart';
import 'package:climate_app/core/l10n/relative_time.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationService _notificationService = NotificationService();
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    final notifications = _notificationService.getNotifications();
    setState(() {
      _notifications = notifications;
      _isLoading = false;
    });
  }

  /// Marks [notif] read, then opens what it is about (the push text is
  /// generic; the details are shown in the app).
  Future<void> _open(Map<String, dynamic> notif, {required bool isRead}) async {
    // Navigate first. Marking the entry read is bookkeeping: it writes to
    // Hive and reloads the list, and while those were awaited ahead of the
    // push, anything that made them slow or fail — a stalled box, a storage
    // error — swallowed the tap entirely and the row looked dead. Opening
    // what the entry is about is the thing the user asked for, so it does
    // not wait on housekeeping.
    final route = notificationRouteFor(notif);
    if (route != null) context.push(route);
    if (isRead) return;
    await _notificationService.markAsRead(notif['id'] as String);
    if (!mounted) return;
    await _loadNotifications();
  }

  Future<void> _markAllAsRead() async {
    await _notificationService.markAllAsRead();
    await _loadNotifications();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.notificationsAllRead)),
      );
    }
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.notificationsClearAll),
        content: Text(context.l10n.notificationsClearConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              context.l10n.delete,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _notificationService.clearAll();
      await _loadNotifications();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.l10n.back,
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: AppColors.primaryRed,
          ),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/dashboard');
            }
          },
        ),
        title: Text(
          context.l10n.shellNotificationsTooltip,
          style: GoogleFonts.lexend(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        actions: [
          if (_notifications.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.textPrimary),
              onSelected: (value) {
                if (value == 'read') _markAllAsRead();
                if (value == 'clear') _clearAll();
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'read',
                  child: Text(context.l10n.notificationsMarkAllRead),
                ),
                PopupMenuItem(
                  value: 'clear',
                  child: Text(context.l10n.notificationsClearAllMenu),
                ),
              ],
            ),
        ],
        backgroundColor: AppColors.background.withValues(alpha: 0.95),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.grey.shade200, height: 1.0),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_off_outlined,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.l10n.notificationsEmpty,
                    style: GoogleFonts.lexend(
                      color: Colors.grey.shade500,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadNotifications,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _notifications.length,
                itemBuilder: (context, index) {
                  final notif = _notifications[index];
                  final isRead = notif['isRead'] as bool? ?? false;
                  final timestamp =
                      DateTime.tryParse(notif['timestamp'] ?? '') ??
                      DateTime.now();

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      onTap: () => _open(notif, isRead: isRead),
                      child: AppCard(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              margin: const EdgeInsets.only(top: 6),
                              decoration: BoxDecoration(
                                color: isRead
                                    ? Colors.transparent
                                    : AppColors.primaryRed,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          notificationTitleFor(
                                            context.l10n,
                                            notif,
                                          ),
                                          style: GoogleFonts.lexend(
                                            fontWeight: isRead
                                                ? FontWeight.w500
                                                : FontWeight.bold,
                                            fontSize: 16,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        _formatTime(timestamp),
                                        style: GoogleFonts.lexend(
                                          fontSize: 12,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    notificationBodyFor(context.l10n, notif),
                                    style: GoogleFonts.lexend(
                                      fontSize: 14,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  String _formatTime(DateTime time) {
    final difference = DateTime.now().difference(time);
    if (difference.inHours < 24) return relativeTimeLabel(context.l10n, time);
    return localizedDateFormat(context, 'd/M').format(time);
  }
}

/// The `data` payload of a history entry, as string-keyed map.
Map<String, dynamic> _dataOf(Map<String, dynamic> notif) {
  final raw = notif['data'];
  return raw is Map
      ? raw.map((k, v) => MapEntry(k.toString(), v))
      : <String, dynamic>{};
}

/// Title of a history entry.
///
/// Push entries carry the text the backend sent. Entries produced in the
/// app store no text at all (see `NotificationService.recordOwnReportStatuses`)
/// and are written here from their payload, so they read in whatever
/// language the user is using now — including after they change it.
@visibleForTesting
String notificationTitleFor(AppLocalizations l10n, Map<String, dynamic> notif) {
  final stored = (notif['title'] as String?)?.trim() ?? '';
  if (stored.isNotEmpty) return stored;
  if (_dataOf(notif)['type'] == 'report_status') {
    return l10n.notificationReportStatusTitle;
  }
  return l10n.notificationsDefaultTitle;
}

/// Body of a history entry (see [notificationTitleFor]).
@visibleForTesting
String notificationBodyFor(AppLocalizations l10n, Map<String, dynamic> notif) {
  final stored = (notif['body'] as String?)?.trim() ?? '';
  if (stored.isNotEmpty) return stored;
  final data = _dataOf(notif);
  switch (data['type']) {
    case 'report_status':
      final hazard = Hazard.labelFor(data['hazardType'], l10n);
      switch ((data['status'] ?? '').toString().toLowerCase()) {
        case 'approved':
          return l10n.notificationReportApproved(hazard);
        case 'verified':
          return l10n.notificationReportVerified(hazard);
        case 'rejected':
          return l10n.notificationReportRejected(hazard);
        case 'pending':
          return l10n.notificationReportPending(hazard);
      }
      return '';
    case 'admin_alert':
    case 'alert':
      return l10n.notificationAlertBody;
  }
  return '';
}

/// Route a history entry opens, or null when it has no target beyond this
/// screen.
@visibleForTesting
String? notificationRouteFor(Map<String, dynamic> notif) {
  final data = _dataOf(notif);
  if (data.isEmpty) return null;
  final route = NotificationService.routeForData(data);
  return route == '/notifications' ? null : route;
}
