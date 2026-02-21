/// Extension methods for String manipulation
extension StringNormalization on String {
  /// Normalizes a location string for backend matching by stripping special characters
  /// (underscores, hyphens, spaces) and converting to lowercase.
  ///
  /// This ensures that "Akoko-Edo", "Akoko Edo", and "akokoedo" all resolve
  /// to the same backend string for routing and verification.
  String normalizeForBackend() {
    return toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
}
