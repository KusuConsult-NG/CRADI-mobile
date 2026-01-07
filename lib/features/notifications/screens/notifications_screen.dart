import 'package:climate_app/core/services/notification_service.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/shared/widgets/app_card.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

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

  Future<void> _markAllAsRead() async {
    await _notificationService.markAllAsRead();
    await _loadNotifications();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All notifications marked as read')),
      );
    }
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All'),
        content: const Text(
          'Are you sure you want to delete all notifications?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
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
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: AppColors.primaryRed,
          ),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Notifications',
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
                const PopupMenuItem(
                  value: 'read',
                  child: Text('Mark all as read'),
                ),
                const PopupMenuItem(value: 'clear', child: Text('Clear all')),
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
                    'No notifications yet',
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
                      onTap: () async {
                        if (!isRead) {
                          await _notificationService.markAsRead(notif['id']);
                          _loadNotifications();
                        }
                      },
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
                                          notif['title'] ?? 'Notification',
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
                                    notif['body'] ?? '',
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
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${time.day}/${time.month}';
  }
}
