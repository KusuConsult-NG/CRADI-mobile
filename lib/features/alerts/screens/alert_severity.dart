import 'package:flutter/material.dart';

/// Severity levels of staff broadcast alerts (`alerts.severity`).
const List<String> alertSeverities = ['info', 'warning', 'critical'];

String? _normalize(Object? severity) {
  if (severity == null) return null;
  final s = severity.toString().trim().toLowerCase().replaceAll(
    RegExp(r'\s*severity$'),
    '',
  );
  return s.isEmpty ? null : s;
}

/// Colour for an alert severity. Staff alerts use info / warning / critical;
/// report-derived alerts may carry low / medium / high / critical.
Color alertSeverityColor(Object? severity) {
  switch (_normalize(severity)) {
    case 'info':
      return Colors.blue;
    case 'warning':
      return Colors.orange;
    case 'critical':
    case 'severe':
    case 'extreme':
      return Colors.red;
    case 'low':
      return Colors.green;
    case 'medium':
    case 'moderate':
      return Colors.orange;
    case 'high':
      return Colors.deepOrange;
    default:
      return Colors.blueGrey;
  }
}

/// Icon for an alert severity.
IconData alertSeverityIcon(Object? severity) {
  switch (_normalize(severity)) {
    case 'info':
    case 'low':
      return Icons.info_outline;
    case 'critical':
    case 'severe':
    case 'extreme':
      return Icons.crisis_alert;
    default:
      return Icons.warning_amber_rounded;
  }
}

/// Human readable label for an alert severity (e.g. 'Warning').
String alertSeverityLabel(Object? severity) {
  final raw = severity?.toString().trim() ?? '';
  if (raw.isEmpty) return 'Unspecified severity';
  return raw
      .split(RegExp(r'\s+'))
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}
