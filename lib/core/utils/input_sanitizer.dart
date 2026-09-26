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
      'DROP',
      'DELETE',
      'INSERT',
      'UPDATE',
      'CREATE',
      'ALTER',
      'EXEC',
      'EXECUTE',
      'SCRIPT',
      'UNION',
      'SELECT',
      '--',
      ';',
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

  /// Prepare free text for STORAGE: strips control characters, collapses
  /// whitespace and trims, but does NOT HTML-escape. Escaping belongs at the
  /// point of rendering into HTML; storing entity-encoded text corrupts data
  /// (e.g. "don't" -> "don&#x27;t") shown in native widgets.
  ///
  /// When [preserveNewlines] is true, line breaks are kept (runs of spaces and
  /// tabs are collapsed per line) so multi-line descriptions survive.
  /// When [maxLength] is set the result is truncated to that many characters.
  static String cleanForStorage(
    String input, {
    bool preserveNewlines = false,
    int? maxLength,
  }) {
    if (input.isEmpty) return input;
    // Normalise CRLF/CR to LF, then drop C0/C1 control chars except \n and \t.
    var text = input.replaceAll(RegExp(r'\r\n?'), '\n');
    text = text.replaceAll(
      RegExp(r'[\u0000-\u0008\u000B-\u001F\u007F-\u009F]'),
      '',
    );
    if (preserveNewlines) {
      text = text
          .split('\n')
          .map((line) => line.replaceAll(RegExp(r'[ \t\f\v]+'), ' ').trim())
          .join('\n')
          .replaceAll(RegExp(r'\n{3,}'), '\n\n')
          .trim();
    } else {
      text = normalizeWhitespace(text);
    }
    if (maxLength != null && text.length > maxLength) {
      text = text.substring(0, maxLength).trimRight();
    }
    return text;
  }

  /// Full sanitization for user input.
  ///
  /// NOTE: this HTML-escapes the result and is only suitable for text that
  /// will be embedded into HTML. Use [cleanForStorage] for persisted data.
  static String fullSanitize(String input) {
    String sanitized = input;
    sanitized = normalizeWhitespace(sanitized);
    sanitized = sanitize(sanitized);
    return sanitized;
  }
}
