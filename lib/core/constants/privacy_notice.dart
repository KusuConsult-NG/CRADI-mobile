/// NDPA data-processing notice shown at registration (consent) and from
/// About → Privacy Policy. The notice text itself is translated: see
/// `privacyNoticeText` in lib/l10n/app_*.arb. Bump [kNdpaPolicyVersion]
/// whenever its content changes.
library;

// Bumped for the Supabase / OneSignal migration (processors changed).
// Storage region: the notice deliberately says data "may be transferred to and
// stored on servers outside Nigeria" rather than naming a region, so it stays
// accurate if the Supabase project moves. Naming a region would mean bumping
// this version and re-consenting every user.
const String kNdpaPolicyVersion = '1.1.0';
