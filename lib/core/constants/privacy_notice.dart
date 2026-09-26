/// NDPA data-processing notice shown at registration (consent) and from
/// About → Privacy Policy. The notice text itself is translated: see
/// `privacyNoticeText` in lib/l10n/app_*.arb. Bump [kNdpaPolicyVersion]
/// whenever its content changes.
library;

// Bumped for the Supabase / OneSignal migration (processors changed).
// TODO(legal): confirm the storage region wording (privacyNoticeText) before release.
const String kNdpaPolicyVersion = '1.1.0';
