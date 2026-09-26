import 'package:climate_app/l10n/app_localizations.dart';

/// Compact "time ago" text ("5m ago", "3h ago", "2d ago", "1w ago") for
/// [date], in the language of [l10n]. [now] is for tests.
String relativeTimeLabel(
  AppLocalizations l10n,
  DateTime date, {
  DateTime? now,
}) {
  final diff = (now ?? DateTime.now()).difference(date);
  if (diff.isNegative || diff.inMinutes < 1) return l10n.timeJustNow;
  if (diff.inMinutes < 60) return l10n.timeMinutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return l10n.timeHoursAgo(diff.inHours);
  if (diff.inDays < 7) return l10n.timeDaysAgo(diff.inDays);
  return l10n.timeWeeksAgo(diff.inDays ~/ 7);
}
