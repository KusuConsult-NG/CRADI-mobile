import 'package:hive/hive.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'dart:developer' as developer;

/// Service for managing Hive database encryption
/// Generates and securely stores AES-256 encryption keys
class HiveEncryptionService {
  static final HiveEncryptionService _instance =
      HiveEncryptionService._internal();
  factory HiveEncryptionService() => _instance;
  HiveEncryptionService._internal();

  static const String _keyStorageKey = 'hive_encryption_key';
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  List<int>? _encryptionKey;

  /// Get or generate encryption key for Hive boxes
  /// Key is stored securely in platform Keychain (iOS) or KeyStore (Android)
  Future<List<int>> getEncryptionKey() async {
    if (_encryptionKey != null) return _encryptionKey!;

    try {
      // Try to retrieve existing key
      final storedKey = await _secureStorage.read(key: _keyStorageKey);

      if (storedKey != null && storedKey.isNotEmpty) {
        _encryptionKey = base64Decode(storedKey);
        developer.log(
          'Retrieved existing Hive encryption key',
          name: 'HiveEncryptionService',
        );
      } else {
        // Generate new 256-bit encryption key
        _encryptionKey = Hive.generateSecureKey();
        await _secureStorage.write(
          key: _keyStorageKey,
          value: base64Encode(_encryptionKey!),
        );
        developer.log(
          'Generated new Hive encryption key (AES-256)',
          name: 'HiveEncryptionService',
        );
      }

      return _encryptionKey!;
    } on Exception catch (e) {
      developer.log(
        'Error managing encryption key: $e',
        name: 'HiveEncryptionService',
      );
      rethrow;
    }
  }

  /// Get HiveAesCipher for opening encrypted boxes
  Future<HiveAesCipher> getCipher() async {
    final key = await getEncryptionKey();
    return HiveAesCipher(key);
  }

  /// Check if an encryption key exists
  Future<bool> hasEncryptionKey() async {
    final storedKey = await _secureStorage.read(key: _keyStorageKey);
    return storedKey != null && storedKey.isNotEmpty;
  }

  /// Delete encryption key (WARNING: Will make encrypted data unreadable!)
  /// Only call during complete app data reset
  Future<void> deleteEncryptionKey() async {
    await _secureStorage.delete(key: _keyStorageKey);
    _encryptionKey = null;
    developer.log('Deleted Hive encryption key', name: 'HiveEncryptionService');
  }
}
