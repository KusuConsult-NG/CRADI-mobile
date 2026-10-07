/// Application configuration constants
///
/// This file contains configuration flags and constants that can be
/// modified for development, testing, and production environments.
class AppConfig {
  AppConfig._();

  // ─────────────────────── Runtime configuration ───────────────────────────
  // Supplied at build time: flutter run --dart-define-from-file=env.json
  // (see env.example.json). Never commit real values.

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );
  static const String oneSignalAppId = String.fromEnvironment(
    'ONESIGNAL_APP_ID',
  );

  /// Optional. Crash reporting is disabled when empty.
  static const String sentryDsn = String.fromEnvironment('SENTRY_DSN');

  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  // ─────────────────────── Store listing ───────────────────────────────────

  /// Android applicationId (android/app/build.gradle.kts). Keep in sync.
  static const String androidApplicationId =
      'com.westgatestratagem.climate_app.climate_app';

  /// Google Play listing opened by the force-update screen.
  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=$androidApplicationId';

  // No App Store id exists yet, so there is no iOS store link: the
  // force-update screen hides its "Update" button on iOS.

  // ─────────────────────── Table names ─────────────────────────────────────

  static const String usersCollection = 'profiles';
  static const String reportsCollection = 'reports';
  static const String verificationsCollection = 'verifications';
  static const String alertsCollection = 'alerts';
  static const String messagesCollection = 'messages';
  static const String contactsCollection = 'contacts';
  static const String knowledgeBaseCollection = 'knowledge_base';
  static const String trustedDevicesCollection = 'trusted_devices';
  static const String loginHistoryCollection = 'login_history';
  static const String scheduledEscalationsCollection = 'scheduled_escalations';
  static const String verificationsOverrideCollection =
      'verification_overrides';
  static const String authoritiesCollection = 'authorities';
  static const String ndpaConsentsCollection = 'ndpa_consents';
  static const String appSettingsCollection = 'app_settings';
  static const String newsLinksCollection = 'news_links';

  // ─────────────────────── Storage buckets ─────────────────────────────────
  // Object paths must start with the uploader's user id (storage RLS).
  //
  // Overridable at build time because an Appwrite tier that allows only
  // one bucket makes both of these the same bucket, separated by the
  // path prefix. The previous Appwrite project ran exactly that way —
  // its config says "Due to Appwrite free tier limits (max 1 bucket)".
  // Safe there as long as file-level permissions stay on; see
  // `infra/appwrite/plan.mjs`.
  //
  // The Cloud plan was upgraded on 7 October 2026 and provisions the two
  // buckets named below, so neither define needs passing for it. The
  // escape hatch stays for a one-bucket tier.

  static const String profileImagesBucket = String.fromEnvironment(
    'PROFILE_IMAGES_BUCKET',
    defaultValue: 'profile-images',
  );
  static const String reportImagesBucket = String.fromEnvironment(
    'REPORT_IMAGES_BUCKET',
    defaultValue: 'report-images',
  );
}
