import 'dart:developer' as developer;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service for managing registration codes
class RegistrationCodeService {
  static final RegistrationCodeService _instance =
      RegistrationCodeService._internal();
  factory RegistrationCodeService() => _instance;
  RegistrationCodeService._internal();

  final _storage = const FlutterSecureStorage();
  static const _registrationCodeKey = 'registration_code';

  /// Get or generate registration code
  Future<String> getRegistrationCode() async {
    try {
      // Check if code already exists
      final existingCode = await _storage.read(key: _registrationCodeKey);
      if (existingCode != null && existingCode.isNotEmpty) {
        return existingCode;
      }

      // Generate new code
      final code = _generateCode();
      await _storage.write(key: _registrationCodeKey, value: code);
      developer.log(
        'Generated registration code: $code',
        name: 'RegistrationCodeService',
      );
      return code;
    } on Exception catch (e) {
      developer.log(
        'Error with registration code: $e',
        name: 'RegistrationCodeService',
      );
      return _generateCode(); // Fallback to new code
    }
  }

  /// Generate a unique registration code with format: CRD######
  String _generateCode() {
    // Generate 6 random digits
    final random = DateTime.now().millisecondsSinceEpoch % 1000000;
    final digits = random.toString().padLeft(6, '0');
    return 'CRD$digits';
  }

  /// Clear registration code (for testing)
  Future<void> clearCode() async {
    await _storage.delete(key: _registrationCodeKey);
  }
}
