import 'package:encrypt/encrypt.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:typed_data';

/// Encryption service for data security
class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  // Generate a secure key from a passphrase
  Key _generateKey(String passphrase) {
    final bytes = utf8.encode(passphrase);
    final digest = sha256.convert(bytes);
    return Key(Uint8List.fromList(digest.bytes));
  }

  // Generate initialization vector
  IV _generateIV() {
    return IV.fromSecureRandom(16);
  }

  /// Encrypt string data
  String encryptString(String plainText, String passphrase) {
    final key = _generateKey(passphrase);
    final iv = _generateIV();
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    
    // Return IV + encrypted data (both base64 encoded)
    return '${iv.base64}:${encrypted.base64}';
  }

  /// Decrypt string data
  String decryptString(String encryptedData, String passphrase) {
    try {
      final parts = encryptedData.split(':');
      if (parts.length != 2) {
        throw Exception('Invalid encrypted data format');
      }

      final iv = IV.fromBase64(parts[0]);
      final encrypted = Encrypted.fromBase64(parts[1]);
      
      final key = _generateKey(passphrase);
      final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
      
      return encrypter.decrypt(encrypted, iv: iv);
    } catch (e) {
      throw Exception('Decryption failed: ${e.toString()}');
    }
  }

  /// Encrypt JSON data
  String encryptJson(Map<String, dynamic> data, String passphrase) {
    final jsonString = json.encode(data);
    return encryptString(jsonString, passphrase);
  }

  /// Decrypt JSON data
  Map<String, dynamic> decryptJson(String encryptedData, String passphrase) {
    final decryptedString = decryptString(encryptedData, passphrase);
    return json.decode(decryptedString) as Map<String, dynamic>;
  }

  /// Hash password or sensitive data (one-way)
  String hashData(String data) {
    final bytes = utf8.encode(data);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Verify hashed data
  bool verifyHash(String data, String hash) {
    return hashData(data) == hash;
  }

  /// Generate secure random string for tokens
  String generateSecureToken([int length = 32]) {
    final iv = IV.fromSecureRandom(length);
    return iv.base64;
  }

  /// Encrypt file data
  Uint8List encryptBytes(Uint8List data, String passphrase) {
    final key = _generateKey(passphrase);
    final iv = _generateIV();
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    
    final encrypted = encrypter.encryptBytes(data, iv: iv);
    
    // Prepend IV to encrypted data
    final result = Uint8List(iv.bytes.length + encrypted.bytes.length);
    result.setRange(0, iv.bytes.length, iv.bytes);
    result.setRange(iv.bytes.length, result.length, encrypted.bytes);
    
    return result;
  }

  /// Decrypt file data
  Uint8List decryptBytes(Uint8List encryptedData, String passphrase) {
    try {
      // Extract IV from the beginning
      final iv = IV(encryptedData.sublist(0, 16));
      final encrypted = Encrypted(encryptedData.sublist(16));
      
      final key = _generateKey(passphrase);
      final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
      
      return Uint8List.fromList(encrypter.decryptBytes(encrypted, iv: iv));
    } catch (e) {
      throw Exception('Decryption failed: ${e.toString()}');
    }
  }
}
