import 'package:cloud_firestore/cloud_firestore.dart';
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

  // Benue/CRADI LGAs — expand as needed
  static const _lgas = [
    'All',
    'Makurdi',
    'Otukpo',
    'Gboko',
    'Katsina-Ala',
    'Lafia',
    'Nasarawa',
    'Akwanga',
    'Keffi',
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
      await FirebaseFirestore.instance.collection('alerts').add({
        'title': _titleCtrl.text.trim(),
        'message': _messageCtrl.text.trim(),
        'severity': _severity,
        'targetLga': _targetLga,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': 'admin',
        'isActive': true,
      });

      developer.log(
        'Alert broadcast: ${_titleCtrl.text} → $_targetLga',
        name: 'AdminAlertsScreen',
      );

      if (mounted) {
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
    await FirebaseFirestore.instance.collection('alerts').doc(id).update({
      'isActive': false,
    });
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

          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('alerts')
                .where('isActive', isEqualTo: true)
                .orderBy('createdAt', descending: true)
                .limit(20)
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data?.docs ?? [];
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
                children: docs.map((doc) {
                  final d = doc.data();
                  final severity = d['severity'] as String? ?? 'info';
                  final color = _severityColors[severity] ?? Colors.blue;
                  final createdAt = d['createdAt'];
                  String timeStr = '';
                  if (createdAt is Timestamp) {
                    final dt = createdAt.toDate();
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
                        onPressed: () => _dismissAlert(doc.id),
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
