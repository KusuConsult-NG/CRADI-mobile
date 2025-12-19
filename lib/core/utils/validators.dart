/// Input validators for security
class Validators {
  /// Validate Nigerian phone number
  /// Formats: 08012345678, +2348012345678, 2348012345678
  static String? validatePhoneNumber(String? value) {
    if (value == null || value.isEmpty) {
      return 'Phone number is required';
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
      return 'Please enter a valid Nigerian phone number';
    }

    return null;
  }

  /// Normalize phone number to international format for Firebase
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

  /// Validate registration code
  /// Format: Alphanumeric, 6-10 characters
  static String? validateRegistrationCode(String? value) {
    if (value == null || value.isEmpty) {
      return 'Registration code is required';
    }

    final cleaned = value.trim().toUpperCase();

    if (cleaned.length < 6 || cleaned.length > 10) {
      return 'Registration code must be 6-10 characters';
    }

    // Allow only alphanumeric characters
    if (!RegExp(r'^[A-Z0-9]+$').hasMatch(cleaned)) {
      return 'Registration code can only contain letters and numbers';
    }

    return null;
  }

  /// Validate OTP code
  /// Format: 4-6 digits
  static String? validateOTP(String? value, {int length = 4}) {
    if (value == null || value.isEmpty) {
      return 'OTP is required';
    }

    if (value.length != length) {
      return 'OTP must be $length digits';
    }

    if (!RegExp(r'^\d+$').hasMatch(value)) {
      return 'OTP must contain only numbers';
    }

    return null;
  }

  /// Validate required field
  static String? validateRequired(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  /// Validate text input (general purpose)
  /// Prevents extremely long inputs and some special characters
  static String? validateText(
    String? value, {
    String? fieldName,
    int? maxLength,
    int? minLength,
    bool allowSpecialChars = true,
  }) {
    if (value == null || value.trim().isEmpty) {
      return '${fieldName ?? 'This field'} is required';
    }

    if (minLength != null && value.length < minLength) {
      return '${fieldName ?? 'This field'} must be at least $minLength characters';
    }

    if (maxLength != null && value.length > maxLength) {
      return '${fieldName ?? 'This field'} must not exceed $maxLength characters';
    }

    // Check for SQL injection patterns
    if (_containsSQLInjection(value)) {
      return 'Invalid characters detected';
    }

    // Check for script injection
    if (_containsScriptInjection(value)) {
      return 'Invalid characters detected';
    }

    return null;
  }

  /// Validate description/notes field
  static String? validateDescription(String? value, {int maxLength = 500}) {
    if (value == null || value.trim().isEmpty) {
      return 'Description is required';
    }

    if (value.length > maxLength) {
      return 'Description must not exceed $maxLength characters';
    }

    if (_containsSQLInjection(value) || _containsScriptInjection(value)) {
      return 'Invalid characters detected';
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
  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Email is required';
    }

    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );

    if (!emailRegex.hasMatch(value)) {
      return 'Please enter a valid email address';
    }

    return null;
  }

  /// Validate location name
  static String? validateLocation(String? value, String locationType) {
    if (value == null || value.trim().isEmpty) {
      return '$locationType is required';
    }

    if (value.length < 2) {
      return '$locationType must be at least 2 characters';
    }

    if (value.length > 100) {
      return '$locationType must not exceed 100 characters';
    }

    // Allow only letters, numbers, spaces, hyphens, and apostrophes
    if (!RegExp(r"^[a-zA-Z0-9\s\-']+$").hasMatch(value)) {
      return '$locationType contains invalid characters';
    }

    return null;
  }
}
