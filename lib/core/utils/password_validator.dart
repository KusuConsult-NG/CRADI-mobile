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

  /// Validate password meets all requirements
  static String? validate(String password) {
    if (password.length < 8) {
      return 'Password must be at least 8 characters';
    }

    if (password.length > 128) {
      return 'Password is too long (max 128 characters)';
    }

    if (!password.contains(RegExp(r'[A-Z]'))) {
      return 'Password must contain at least one uppercase letter';
    }

    if (!password.contains(RegExp(r'[a-z]'))) {
      return 'Password must contain at least one lowercase letter';
    }

    if (!password.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain at least one number';
    }

    if (!password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\;/]'))) {
      return 'Password must contain at least one special character';
    }

    if (isCommonPassword(password.toLowerCase())) {
      return 'This password is too common. Please choose a stronger password';
    }

    // Check for sequential characters
    if (_hasSequentialChars(password)) {
      return 'Password should not contain sequential characters (e.g., 123, abc)';
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
  static String getStrengthLabel(int score) {
    if (score < 30) return 'Weak';
    if (score < 60) return 'Fair';
    if (score < 80) return 'Good';
    return 'Strong';
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
  static List<PasswordRequirement> getRequirements(String password) {
    return [
      PasswordRequirement('At least 8 characters', password.length >= 8),
      PasswordRequirement(
        'Uppercase letter',
        password.contains(RegExp(r'[A-Z]')),
      ),
      PasswordRequirement(
        'Lowercase letter',
        password.contains(RegExp(r'[a-z]')),
      ),
      PasswordRequirement('Number', password.contains(RegExp(r'[0-9]'))),
      PasswordRequirement(
        'Special character',
        password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\;/]')),
      ),
      PasswordRequirement(
        'Not a common password',
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
