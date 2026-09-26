import 'package:climate_app/l10n/app_localizations.dart';

/// Suffix of state-level monitoring zones as stored ("Benue State"). The
/// stored value is parsed by the report filters, so it stays in English;
/// only the displayed text is localised.
const String stateZoneSuffix = ' State';

/// Display text for a stored monitoring zone ("Benue State" or
/// "Makurdi, Benue"). Place names are proper nouns and are not translated.
String monitoringZoneLabel(AppLocalizations l10n, String zone) {
  if (zone.endsWith(stateZoneSuffix)) {
    return l10n.zoneStateLabel(
      zone.substring(0, zone.length - stateZoneSuffix.length),
    );
  }
  return zone;
}
