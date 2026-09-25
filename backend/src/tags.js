// OneSignal tag contract shared with the Flutter app.
//
// The app sets these tags on login: role, lga, state, ward, monitoring_zone.
// Every tag VALUE is sanitised with exactly this rule (no trimming, no
// collapsing of repeated underscores):
//   1. lowercase
//   2. replace every character not in [a-z0-9_] with '_'
// e.g. "Port Harcourt" -> "port_harcourt", "Obio/Akpor" -> "obio_akpor".
export function sanitizeTag(value) {
  return String(value ?? '')
    .toLowerCase()
    .replace(/[^a-z0-9_]/g, '_');
}
