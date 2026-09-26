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

  /// Optional. ImageKit URL endpoint (e.g. `https://ik.imagekit.io/cradi`)
  /// used as a CDN in front of Supabase Storage. When empty — the default —
  /// images are fetched straight from Supabase Storage and every URL is left
  /// untouched (see `ImageUrlResolver`). Delivery only: no SDK, no uploads.
  static const String imageKitUrlEndpoint = String.fromEnvironment(
    'IMAGEKIT_URL_ENDPOINT',
  );

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

  static const String profileImagesBucket = 'profile-images';
  static const String reportImagesBucket = 'report-images';
}
