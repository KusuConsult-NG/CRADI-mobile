/// NDPA data-processing notice shown at registration (consent) and from
/// About → Privacy Policy.
library;

// Bumped for the Supabase / OneSignal migration (processors changed).
// TODO(legal): confirm the storage region wording below before release.
const String kNdpaPolicyVersion = '1.1.0';

const String kNdpaPolicyText = '''
Nigeria Data Protection Act (NDPA) — Data Processing Notice

Your data is processed by EWER Mobile (a CRADI / KusuConsult-NG service) for climate hazard early warning purposes.

• Data collected: name, phone, email, location (state/LGA/ward), hazard reports, and a push-notification device identifier.
• Purpose: community hazard reporting, peer verification, and emergency alerts.
• Storage: Supabase (PostgreSQL) cloud database; push notifications are delivered via OneSignal and crash diagnostics may be sent to Sentry.
• International transfer: Pursuant to NDPA Article 24, we disclose that your data may be transferred to and stored on servers outside Nigeria. This transfer is necessary to provide the service. You have the right to withdraw consent at any time by deleting your account.
• Retention: Data is retained for 5 years after your last activity, then anonymised.
• Your rights: access, rectification, erasure, and data portability under the NDPA 2023.

By tapping "I Agree", you consent to these terms and the international transfer of your personal data.''';
