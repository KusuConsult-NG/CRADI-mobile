import 'package:climate_app/core/l10n/l10n.dart';

/// Enhanced password validation for security
///
/// Enforces strong password requirements and checks against common passwords
class PasswordValidator {
  // Common passwords to block (add more as needed)
  static const _commonPasswords = [
    'password',
    'password123',
    '12345678',
    'qwerty123',
    'abc123456',
    'password1',
    'welcome123',
    'admin123',
    'letmein',
    'monkey123',
  ];

  /// Validate password meets all requirements; the message is in the
  /// language of [l10n].
  static String? validate(String password, AppLocalizations l10n) {
    if (password.length < 8) {
      return l10n.validatorPasswordMinLength(8);
    }

    if (password.length > 128) {
      return l10n.passwordErrorTooLong(128);
    }

    if (!password.contains(RegExp(r'[A-Z]'))) {
      return l10n.validatorPasswordUppercase;
    }

    if (!password.contains(RegExp(r'[a-z]'))) {
      return l10n.validatorPasswordLowercase;
    }

    if (!password.contains(RegExp(r'[0-9]'))) {
      return l10n.validatorPasswordNumber;
    }

    if (!password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\;/]'))) {
      return l10n.validatorPasswordSpecial;
    }

    if (isCommonPassword(password.toLowerCase())) {
      return l10n.passwordErrorCommon;
    }

    // Check for sequential characters
    if (_hasSequentialChars(password)) {
      return l10n.passwordErrorSequential;
    }

    return null; // Valid password
  }

  /// Check if password is in common passwords list
  static bool isCommonPassword(String password) {
    return _commonPasswords.contains(password.toLowerCase());
  }

  /// Calculate password strength score (0-100)
  static int calculateStrength(String password) {
    int score = 0;

    // Length score (max 30 points)
    if (password.length >= 8) score += 10;
    if (password.length >= 12) score += 10;
    if (password.length >= 16) score += 10;

    // Character variety (max 40 points)
    if (password.contains(RegExp(r'[a-z]'))) score += 10; // Lowercase
    if (password.contains(RegExp(r'[A-Z]'))) score += 10; // Uppercase
    if (password.contains(RegExp(r'[0-9]'))) score += 10; // Numbers
    if (password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\;/]'))) {
      score += 10; // Special chars
    }

    // Complexity bonus (max 30 points)
    final uniqueChars = password.split('').toSet().length;
    if (uniqueChars >= 8) score += 10;
    if (uniqueChars >= 12) score += 10;

    // Penalty for common passwords
    if (isCommonPassword(password.toLowerCase())) {
      score -= 30;
    }

    // Penalty for sequential characters
    if (_hasSequentialChars(password)) {
      score -= 10;
    }

    // Ensure score is between 0 and 100
    return score.clamp(0, 100);
  }

  /// Get password strength label
  static String getStrengthLabel(int score, AppLocalizations l10n) {
    if (score < 30) return l10n.passwordStrengthWeak;
    if (score < 60) return l10n.passwordStrengthFair;
    if (score < 80) return l10n.passwordStrengthGood;
    return l10n.passwordStrengthStrong;
  }

  /// Check for sequential characters
  static bool _hasSequentialChars(String password) {
    final sequences = [
      '0123456789',
      'abcdefghijklmnopqrstuvwxyz',
      'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
    ];

    for (final sequence in sequences) {
      for (int i = 0; i < sequence.length - 2; i++) {
        final substring = sequence.substring(i, i + 3);
        if (password.contains(substring)) {
          return true;
        }
      }
    }

    return false;
  }

  /// Get password requirements as a list for UI display
  static List<PasswordRequirement> getRequirements(
    String password,
    AppLocalizations l10n,
  ) {
    return [
      PasswordRequirement(
        l10n.passwordRequirementLength(8),
        password.length >= 8,
      ),
      PasswordRequirement(
        l10n.passwordRequirementUppercase,
        password.contains(RegExp(r'[A-Z]')),
      ),
      PasswordRequirement(
        l10n.passwordRequirementLowercase,
        password.contains(RegExp(r'[a-z]')),
      ),
      PasswordRequirement(
        l10n.passwordRequirementNumber,
        password.contains(RegExp(r'[0-9]')),
      ),
      PasswordRequirement(
        l10n.passwordRequirementSpecial,
        password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\;/]')),
      ),
      PasswordRequirement(
        l10n.passwordRequirementNotCommon,
        !isCommonPassword(password.toLowerCase()),
      ),
    ];
  }
}

/// Represents a password requirement for UI display
class PasswordRequirement {
  final String description;
  final bool isMet;

  PasswordRequirement(this.description, this.isMet);
}
