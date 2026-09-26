import 'dart:async';

import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/core/data/mvp_locations_data.dart';
import 'package:climate_app/features/alerts/providers/alerts_provider.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/core/services/supabase_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'dart:developer' as developer;

/// Admin Alerts & Broadcast screen.
/// Allows admins to send emergency alerts to all users or specific LGAs.
class AdminAlertsScreen extends StatefulWidget {
  const AdminAlertsScreen({super.key});

  @override
  State<AdminAlertsScreen> createState() => _AdminAlertsScreenState();
}

class _AdminAlertsScreenState extends State<AdminAlertsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  late final Stream<List<Map<String, dynamic>>> _alertsStream;

  @override
  void initState() {
    super.initState();
    // is_active is mutable, so it must not be a realtime server filter (a
    // dismissed row would never leave the filtered stream). Subscribe to the
    // newest rows and filter on the client instead.
    _alertsStream = SupabaseService().subscribeToCollection(
      collectionId: AppConfig.alertsCollection,
      queries: [FQuery.orderDesc('createdAt'), FQuery.limit(100)],
    );
  }

  /// Alerts dismissed in this session (hidden before the stream catches up).
  final Set<String> _dismissedIds = {};

  String _severity = 'warning';
  String _targetLga = 'All';
  bool _sending = false;

  static const _severities = ['info', 'warning', 'critical'];
  static const _severityColors = {
    'info': Colors.blue,
    'warning': Colors.orange,
    'critical': Colors.red,
  };
  static const _severityIcons = {
    'info': Icons.info_outline,
    'warning': Icons.warning_amber_outlined,
    'critical': Icons.crisis_alert,
  };

  /// 'All' plus every LGA in the location data (names must match the
  /// profile LGA values alerts are matched against).
  static final List<String> _lgas = [
    'All',
    ...MVPLocationsData.getAllLGAs().toSet().toList()..sort(),
  ];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendAlert() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);

    try {
      // created_by defaults to auth.uid(); the backend pushes the alert
      // from the resulting alert_created event.
      await SupabaseService().createDocument(
        collectionId: AppConfig.alertsCollection,
        data: {
          'title': _titleCtrl.text.trim(),
          'message': _messageCtrl.text.trim(),
          'severity': _severity,
          'targetLga': _targetLga,
          'isActive': true,
        },
      );

      developer.log(
        'Alert broadcast: ${_titleCtrl.text} → $_targetLga',
        name: 'AdminAlertsScreen',
      );

      if (mounted) {
        unawaited(context.read<AlertsProvider>().fetchAlerts());
        _titleCtrl.clear();
        _messageCtrl.clear();
        setState(() {
          _severity = 'warning';
          _targetLga = 'All';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Alert broadcast successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on Exception catch (e) {
      developer.log('Alert send error: $e', name: 'AdminAlertsScreen');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send alert: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _dismissAlert(String id) async {
    try {
      await SupabaseService().updateDocument(
        collectionId: AppConfig.alertsCollection,
        documentId: id,
        data: {'isActive': false},
      );
      if (!mounted) return;
      setState(() => _dismissedIds.add(id));
      unawaited(context.read<AlertsProvider>().fetchAlerts());
    } on Exception catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not dismiss alert.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Alerts & Broadcast',
          style: GoogleFonts.lexend(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.primaryRed,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Compose form ──
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Compose Alert',
                    style: GoogleFonts.lexend(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Severity picker
                  Text(
                    'Severity',
                    style: GoogleFonts.lexend(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: _severities.map((s) {
                      final color = _severityColors[s]!;
                      final selected = _severity == s;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: GestureDetector(
                            onTap: () => setState(() => _severity = s),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: selected
                                    ? color
                                    : color.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: color.withValues(
                                    alpha: selected ? 1 : 0.3,
                                  ),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    _severityIcons[s] ??
                                        Icons.warning_amber_outlined,
                                    color: selected ? Colors.white : color,
                                    size: 20,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    s[0].toUpperCase() + s.substring(1),
                                    style: GoogleFonts.lexend(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: selected ? Colors.white : color,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 16),

                  // Target LGA
                  Text(
                    'Target Area',
                    style: GoogleFonts.lexend(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _targetLga,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    style: GoogleFonts.lexend(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                    items: _lgas
                        .map(
                          (l) => DropdownMenuItem(
                            value: l,
                            child: Text(
                              l == 'All' ? '🌍 All Areas' : l,
                              style: GoogleFonts.lexend(fontSize: 14),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _targetLga = v!),
                  ),

                  const SizedBox(height: 16),

                  // Title
                  TextFormField(
                    controller: _titleCtrl,
                    style: GoogleFonts.lexend(),
                    decoration: InputDecoration(
                      labelText: 'Alert Title',
                      labelStyle: GoogleFonts.lexend(fontSize: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      prefixIcon: const Icon(Icons.title),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                    textCapitalization: TextCapitalization.sentences,
                  ),

                  const SizedBox(height: 12),

                  // Message
                  TextFormField(
                    controller: _messageCtrl,
                    style: GoogleFonts.lexend(),
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: 'Message',
                      labelStyle: GoogleFonts.lexend(fontSize: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignLabelWithHint: true,
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(bottom: 60),
                        child: Icon(Icons.message_outlined),
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                    textCapitalization: TextCapitalization.sentences,
                  ),

                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _sending ? null : _sendAlert,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _severityColors[_severity] ?? AppColors.primaryRed,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(_severityIcons[_severity]),
                      label: Text(
                        _sending ? 'Sending…' : 'Broadcast Alert',
                        style: GoogleFonts.lexend(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Recent active alerts ──
          Text(
            'Active Alerts',
            style: GoogleFonts.lexend(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),

          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _alertsStream,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Could not load alerts. You may not have permission to view them.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.lexend(color: Colors.red),
                    ),
                  ),
                );
              }
              final docs = (snap.data ?? const <Map<String, dynamic>>[])
                  .where(
                    (d) =>
                        d['isActive'] != false &&
                        !_dismissedIds.contains(d[r'$id']?.toString()),
                  )
                  .take(20)
                  .toList();
              if (docs.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No active alerts',
                      style: GoogleFonts.lexend(color: AppColors.textSecondary),
                    ),
                  ),
                );
              }
              return Column(
                children: docs.map((d) {
                  final severity = d['severity'] as String? ?? 'info';
                  final color = _severityColors[severity] ?? Colors.blue;
                  final createdAt = d['createdAt'];
                  String timeStr = '';
                  final dt = parseTimestamp(createdAt);
                  if (dt != null) {
                    timeStr = '${dt.day}/${dt.month}/${dt.year}';
                  }
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: color.withValues(alpha: 0.3)),
                    ),
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _severityIcons[severity] ?? Icons.info_outline,
                          color: color,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        d['title'] as String? ?? '',
                        style: GoogleFonts.lexend(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d['message'] as String? ?? '',
                            style: GoogleFonts.lexend(fontSize: 12),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              _alertChip(
                                d['targetLga'] as String? ?? 'All',
                                Colors.teal,
                              ),
                              const SizedBox(width: 6),
                              _alertChip(severity, color),
                              if (timeStr.isNotEmpty) ...[
                                const SizedBox(width: 6),
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
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Dismiss alert',
                        onPressed: () => _dismissAlert(d['\$id'] as String),
                      ),
                      isThreeLine: true,
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _alertChip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
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
