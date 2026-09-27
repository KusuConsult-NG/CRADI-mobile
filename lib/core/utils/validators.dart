import 'package:climate_app/core/l10n/l10n.dart';
import 'package:climate_app/core/utils/password_validator.dart';

/// Input validators for security. Messages are returned in the language of
/// the [AppLocalizations] passed in.
class Validators {
  /// Validate Nigerian phone number
  /// Formats: 08012345678, +2348012345678, 2348012345678
  static String? validatePhoneNumber(String? value, AppLocalizations l10n) {
    if (value == null || value.isEmpty) {
      return l10n.validatorPhoneRequired;
    }

    // Remove spaces and special characters
    final cleaned = value.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    // Check various Nigerian phone number formats
    final patterns = [
      RegExp(r'^0[7-9][0-1]\d{8}$'), // 08012345678
      RegExp(r'^\+234[7-9][0-1]\d{8}$'), // +2348012345678
      RegExp(r'^234[7-9][0-1]\d{8}$'), // 2348012345678
    ];

    final isValid = patterns.any((pattern) => pattern.hasMatch(cleaned));

    if (!isValid) {
      return l10n.validatorPhoneInvalid;
    }

    return null;
  }

  /// Normalize phone number to E.164 (used for Supabase phone OTP)
  /// Accepts: 08012345678, +2348012345678, 2348012345678
  /// Returns: +2348012345678
  static String normalizePhoneNumber(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    // Already in international format with +
    if (cleaned.startsWith('+234')) {
      return cleaned;
    }

    // International format without +
    if (cleaned.startsWith('234')) {
      return '+$cleaned';
    }

    // Local format (starts with 0)
    if (cleaned.startsWith('0')) {
      return '+234${cleaned.substring(1)}';
    }

    // Assume it's missing everything, add +234
    return '+234$cleaned';
  }

  /// Validate address
  /// Basic validation for user address
  static String? validateAddress(String? value, AppLocalizations l10n) {
    if (value == null || value.trim().isEmpty) {
      return l10n.validatorAddressRequired;
    }

    final cleaned = value.trim();

    if (cleaned.length < 10) {
      return l10n.validatorAddressTooShort(10);
    }

    if (cleaned.length > 200) {
      return l10n.validatorAddressTooLong(200);
    }

    return null;
  }

  /// Validate required field
  /// [fieldName] is the (already localised) field label.
  static String? validateRequired(
    String? value,
    String fieldName,
    AppLocalizations l10n,
  ) {
    if (value == null || value.trim().isEmpty) {
      return l10n.validatorFieldRequired(fieldName);
    }
    return null;
  }

  /// Validate text input (general purpose)
  /// Prevents extremely long inputs and some special characters
  static String? validateText(
    String? value,
    AppLocalizations l10n, {
    String? fieldName,
    int? maxLength,
    int? minLength,
    bool allowSpecialChars = true,
  }) {
    if (value == null || value.trim().isEmpty) {
      return fieldName != null
          ? l10n.validatorFieldRequired(fieldName)
          : l10n.validation_required;
    }

    if (minLength != null && value.length < minLength) {
      return fieldName != null
          ? l10n.validatorFieldMinLength(fieldName, minLength)
          : l10n.validation_minLength(minLength);
    }

    if (maxLength != null && value.length > maxLength) {
      return fieldName != null
          ? l10n.validatorFieldMaxLength(fieldName, maxLength)
          : l10n.validation_maxLength(maxLength);
    }

    // Check for SQL injection patterns
    if (_containsSQLInjection(value)) {
      return l10n.validatorInvalidCharacters;
    }

    // Check for script injection
    if (_containsScriptInjection(value)) {
      return l10n.validatorInvalidCharacters;
    }

    return null;
  }

  /// Validate description/notes field
  static String? validateDescription(
    String? value,
    AppLocalizations l10n, {
    int maxLength = 500,
  }) {
    if (value == null || value.trim().isEmpty) {
      return l10n.validatorDescriptionRequired;
    }

    if (value.length > maxLength) {
      return l10n.validatorDescriptionTooLong(maxLength);
    }

    if (_containsSQLInjection(value) || _containsScriptInjection(value)) {
      return l10n.validatorInvalidCharacters;
    }

    return null;
  }

  /// Check for potential SQL injection patterns
  static bool _containsSQLInjection(String value) {
    final sqlPatterns = [
      RegExp(r"('|(\\')|(--)|(/\\*.*\\*/)|(;))", caseSensitive: false),
      RegExp(
        r'\b(SELECT|INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|EXEC|EXECUTE)\b',
        caseSensitive: false,
      ),
    ];

    return sqlPatterns.any((pattern) => pattern.hasMatch(value));
  }

  /// Check for potential script injection patterns
  static bool _containsScriptInjection(String value) {
    final scriptPatterns = [
      RegExp(r'<script[^>]*>.*?</script>', caseSensitive: false),
      RegExp(r'javascript:', caseSensitive: false),
      RegExp(r'on\w+\s*=', caseSensitive: false), // onclick=, onerror=, etc.
    ];

    return scriptPatterns.any((pattern) => pattern.hasMatch(value));
  }

  /// Validate email (if needed in future)
  static String? validateEmail(String? value, AppLocalizations l10n) {
    if (value == null || value.isEmpty) {
      return l10n.validatorEmailRequired;
    }

    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );

    if (!emailRegex.hasMatch(value)) {
      return l10n.validation_invalidEmail;
    }

    return null;
  }

  /// Check if email is valid (boolean)
  static bool isValidEmail(String? value) {
    if (value == null || value.isEmpty) {
      return false;
    }

    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );

    return emailRegex.hasMatch(value);
  }

  /// Password validation for every screen that takes a password.
  ///
  /// Delegates to [PasswordValidator.validate] so registration, password
  /// reset and the web admin panel all enforce the same rules. They used to
  /// differ: this method carried a weaker copy (no maximum length, no
  /// common-password list, no sequential-run check) while the stricter
  /// [PasswordValidator] was used by nothing at all.
  static String? validatePassword(String? value, AppLocalizations l10n) {
    if (value == null || value.isEmpty) {
      return l10n.validatorPasswordRequired;
    }
    return PasswordValidator.validate(value, l10n);
  }

  /// Get password strength score (0-4)
  /// 0 = Very Weak, 1 = Weak, 2 = Fair, 3 = Good, 4 = Strong
  static int getPasswordStrength(String password) {
    if (password.isEmpty) return 0;

    int strength = 0;

    // Length check
    if (password.length >= 8) strength++;
    if (password.length >= 12) strength++;

    // Character variety checks
    if (RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'[a-z]').hasMatch(password)) {
      strength++;
    }

    if (RegExp(r'[0-9]').hasMatch(password)) {
      strength++;
    }

    if (RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\\/]').hasMatch(password)) {
      strength++;
    }

    // Cap at 4
    return strength > 4 ? 4 : strength;
  }

  /// Get password strength label and color
  static Map<String, dynamic> getPasswordStrengthInfo(
    int strength,
    AppLocalizations l10n,
  ) {
    switch (strength) {
      case 0:
      case 1:
        return {'label': l10n.passwordStrengthWeak, 'color': 0xFFE53935};
      case 2:
        return {'label': l10n.passwordStrengthFair, 'color': 0xFFFB8C00};
      case 3:
        return {'label': l10n.passwordStrengthGood, 'color': 0xFF43A047};
      case 4:
        return {'label': l10n.passwordStrengthStrong, 'color': 0xFF1E88E5};
      default:
        return {'label': l10n.commonUnknown, 'color': 0xFF757575};
    }
  }

  /// Validate location name
  /// [locationType] is the (already localised) field label, e.g. "State".
  static String? validateLocation(
    String? value,
    String locationType,
    AppLocalizations l10n,
  ) {
    if (value == null || value.trim().isEmpty) {
      return l10n.validatorFieldRequired(locationType);
    }

    if (value.length < 2) {
      return l10n.validatorFieldMinLength(locationType, 2);
    }

    if (value.length > 100) {
      return l10n.validatorFieldMaxLength(locationType, 100);
    }

    // Allow only letters, numbers, spaces, hyphens, and apostrophes
    if (!RegExp(r"^[a-zA-Z0-9\s\-']+$").hasMatch(value)) {
      return l10n.validatorFieldInvalidCharacters(locationType);
    }

    return null;
  }
}
