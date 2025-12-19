/// Application configuration constants
///
/// This file contains configuration flags and constants that can be
/// modified for development, testing, and production environments.
class AppConfig {
  AppConfig._();

  /// Enable development bypass for OTP verification
  /// When enabled, entering "1111" as the OTP will bypass Firebase authentication
  /// This allows testing without actual SMS verification
  ///
  /// IMPORTANT: Set this to false in production builds!
  static const bool enableOtpBypass = true;

  /// The development bypass OTP code
  static const String devBypassOtp = "1111";

  /// Enable verbose logging
  static const bool verboseLogging = true;

  /// Session timeout duration (in minutes)
  static const int sessionTimeoutMinutes = 30;

  /// Maximum login attempts before account lock
  static const int maxLoginAttempts = 5;
}
