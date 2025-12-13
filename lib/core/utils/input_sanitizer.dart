/// Input sanitizer to prevent injection attacks
class InputSanitizer {
  /// Sanitize string input by escaping special characters
  static String sanitize(String input) {
    if (input.isEmpty) return input;

    String sanitized = input;

    // HTML entity encoding for common special characters
    sanitized = sanitized
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#x27;')
        .replaceAll('/', '&#x2F;');

    return sanitized;
  }

  /// Sanitize for SQL (though we should use parameterized queries)
  static String sanitizeForSQL(String input) {
    if (input.isEmpty) return input;

    // Escape single quotes and remove SQL keywords
    String sanitized = input.replaceAll("'", "''");
    
    // Remove dangerous SQL keywords
    final dangerousKeywords = [
      'DROP', 'DELETE', 'INSERT', 'UPDATE', 'CREATE', 'ALTER',
      'EXEC', 'EXECUTE', 'SCRIPT', 'UNION', 'SELECT', '--', ';'
    ];

    for (final keyword in dangerousKeywords) {
      final pattern = RegExp(r'\b' + keyword + r'\b', caseSensitive: false);
      sanitized = sanitized.replaceAll(pattern, '');
    }

    return sanitized.trim();
  }

  /// Remove all HTML tags
  static String stripHtml(String input) {
    if (input.isEmpty) return input;
    
    return input.replaceAll(RegExp(r'<[^>]*>'), '');
  }

  /// Sanitize filename to prevent path traversal
  static String sanitizeFilename(String filename) {
    if (filename.isEmpty) return filename;

    // Remove path separators and special characters
    String sanitized = filename
        .replaceAll(RegExp(r'[/\\]'), '')
        .replaceAll('..', '')
        .replaceAll('~', '')
        .trim();

    // Allow only alphanumeric, dash, underscore, and dot
    sanitized = sanitized.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

    // Ensure it doesn't start with a dot
    if (sanitized.startsWith('.')) {
      sanitized = sanitized.substring(1);
    }

    return sanitized;
  }

  /// Sanitize URL to prevent javascript: and data: protocols
  static String? sanitizeUrl(String url) {
    if (url.isEmpty) return null;

    final lowercaseUrl = url.toLowerCase().trim();

    // Block dangerous protocols
    final dangerousProtocols = ['javascript:', 'data:', 'vbscript:', 'file:'];
    
    for (final protocol in dangerousProtocols) {
      if (lowercaseUrl.startsWith(protocol)) {
        return null; // Reject the URL
      }
    }

    // Only allow http and https
    if (!lowercaseUrl.startsWith('http://') && 
        !lowercaseUrl.startsWith('https://')) {
      return null;
    }

    return url;
  }

  /// Sanitize phone number (remove non-numeric characters)
  static String sanitizePhoneNumber(String phone) {
    return phone.replaceAll(RegExp(r'[^\d+]'), '');
  }

  /// Sanitize alphanumeric code (remove non-alphanumeric)
  static String sanitizeAlphanumeric(String code) {
    return code.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
  }

  /// Trim and normalize whitespace
  static String normalizeWhitespace(String input) {
    return input.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Sanitize text for display (prevent XSS)
  static String sanitizeForDisplay(String input) {
    return sanitize(stripHtml(input));
  }

  /// Full sanitization for user input
  static String fullSanitize(String input) {
    String sanitized = input;
    sanitized = normalizeWhitespace(sanitized);
    sanitized = sanitize(sanitized);
    return sanitized;
  }
}
