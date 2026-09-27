import 'package:climate_app/features/reporting/providers/reporting_provider.dart'
    show normalizeSeverity;
import 'package:flutter/material.dart';

/// The colour a report severity is drawn in, wherever severity is shown:
/// the verification list's dot, the review screen's icon, and anything added
/// later. Accepts the canonical 'low' | 'medium' | 'high' | 'critical' or a
/// legacy spelling; anything unknown is grey.
Color severityColor(Object? raw) {
  switch (normalizeSeverity(raw)) {
    case 'critical':
      return Colors.red;
    case 'high':
      return Colors.deepOrange;
    case 'medium':
      return Colors.amber.shade700;
    case 'low':
      return Colors.green;
  }
  return Colors.grey;
}
