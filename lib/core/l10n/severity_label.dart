import 'package:climate_app/features/reporting/providers/reporting_provider.dart'
    show normalizeSeverity;
import 'package:climate_app/l10n/app_localizations.dart';

/// Display label for a report severity (canonical 'low' | 'medium' | 'high'
/// | 'critical' or a legacy spelling). Unknown values are shown as stored;
/// missing ones as "Unknown".
String severityLabel(AppLocalizations l10n, Object? raw) {
  switch (normalizeSeverity(raw)) {
    case 'low':
      return l10n.severityLow;
    case 'medium':
      return l10n.severityMedium;
    case 'high':
      return l10n.severityHigh;
    case 'critical':
      return l10n.severityCritical;
  }
  final s = raw?.toString().trim() ?? '';
  return s.isEmpty ? l10n.commonUnknown : s;
}
