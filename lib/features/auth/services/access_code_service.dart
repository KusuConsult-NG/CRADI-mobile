import 'dart:math';
import 'dart:developer' as developer;
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/core/services/appwrite_service.dart';

/// Service to handle Access Code generation and verification
class AccessCodeService {
  // Singleton pattern
  static final AccessCodeService _instance = AccessCodeService._internal();
  factory AccessCodeService() => _instance;
  AccessCodeService._internal();

  final AppwriteService _appwrite = AppwriteService();

  /// Generate a random 6-character alphanumeric code
  String _generateRandomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random();
    return String.fromCharCodes(
      Iterable.generate(6, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))),
    );
  }

  Future<String> generateCodeForUser({
    required String userId,
    required UserRole role,
  }) async {
    final prefix = _getRolePrefix(role);
    final randomPart = _generateRandomCode();
    return '$prefix$randomPart';
  }

  String _getRolePrefix(UserRole role) {
    switch (role) {
      case UserRole.ewm:
        return 'EWM-';
      case UserRole.coordinator:
        return 'COO-';
      case UserRole.projectStaff:
        return 'STF-';
      case UserRole.earlyResponder:
        return 'RES-';
      case UserRole.media:
        return 'MED-';
    }
  }

  /// Verify an access code against the user's document
  Future<Map<String, dynamic>> verifyCode(String code, String userId) async {
    try {
      final userDoc = await _appwrite.getDocument(
        collectionId: AppwriteService.usersCollectionId,
        documentId: userId,
      );

      final storedCode = userDoc.data['accessCode'] as String?;
      final isVerified = userDoc.data['isVerified'] as bool? ?? false;
      final roleStr = userDoc.data['role'] as String?;

      developer.log(
        'Verifying code for $userId: Input="$code", Stored="$storedCode", Verified=$isVerified',
        name: 'AccessCodeService',
      );
      // DEBUG: Print all data to check for permission issues
      developer.log(
        'Full Doc Data: ${userDoc.data}',
        name: 'AccessCodeService',
      );

      if (isVerified) {
        return {
          'isValid': true,
          'role': _parseUserRole(roleStr),
          'alreadyVerified': true,
        };
      }

      if (storedCode != null &&
          storedCode.trim().toUpperCase() == code.trim().toUpperCase()) {
        return {'isValid': true, 'role': _parseUserRole(roleStr)};
      }

      developer.log('Code mismatch', name: 'AccessCodeService');
      return {'isValid': false};
    } on Exception catch (e) {
      developer.log('Verification failed: $e', name: 'AccessCodeService');
      return {'isValid': false, 'error': e.toString()};
    }
  }

  /// Consume code (No-op now as we just check against DB, but keeping for API compatibility or future logic)
  Future<void> consumeCode(String code) async {
    // In the new flow, AuthProvider updates 'isVerified' to true, which effectively "consumes" the code
    // for the purpose of the gate.
  }

  UserRole? _parseUserRole(String? roleStr) {
    if (roleStr == null) return null;
    try {
      return UserRole.values.firstWhere((role) => role.name == roleStr);
    } on Exception catch (_) {
      return null;
    }
  }
}
