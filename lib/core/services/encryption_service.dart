import 'package:encrypt/encrypt.dart'
    show Encrypter, AES, AESMode, Encrypted, IV, Key;
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart' as pc;
import 'dart:convert';
import 'dart:typed_data';
import 'dart:developer' as developer;

/// Encryption service for data security — AES-256-GCM with PBKDF2 key derivation.
///
/// Format (all base64, colon-separated):
///   GCM path:  "salt:iv:ciphertext"  (3 segments)
///   CBC legacy: "iv:ciphertext"      (2 segments — read-only migration path)
class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  static const int _pbkdf2Iterations = 100000;
  static const int _saltLength = 16;
  static const int _ivLengthGcm = 12; // 96-bit IV recommended for GCM
  static const int _gcmTagLength = 128; // bits

  // ─────────────────────────────────────────────────────────────────────────
  // Key Derivation (PBKDF2-SHA256)
  // ─────────────────────────────────────────────────────────────────────────

  /// Derive a 256-bit key from a passphrase and salt using PBKDF2-SHA256.
  Uint8List _deriveKey(String passphrase, Uint8List salt) {
    final pbkdf2 = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64));
    pbkdf2.init(pc.Pbkdf2Parameters(salt, _pbkdf2Iterations, 32));
    return pbkdf2.process(Uint8List.fromList(utf8.encode(passphrase)));
  }

  /// Generate a secure random [length]-byte buffer.
  Uint8List _randomBytes(int length) {
    final iv = IV.fromSecureRandom(length);
    return iv.bytes;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // String Encryption / Decryption
  // ─────────────────────────────────────────────────────────────────────────

  /// Encrypt a string using AES-256-GCM.
  /// Returns base64 segments joined by ':' → "salt:iv:ciphertext+tag"
  String encryptString(String plainText, String passphrase) {
    final salt = _randomBytes(_saltLength);
    final iv = _randomBytes(_ivLengthGcm);
    final keyBytes = _deriveKey(passphrase, salt);

    final gcm = pc.GCMBlockCipher(pc.AESEngine());
    gcm.init(
      true,
      pc.AEADParameters(
        pc.KeyParameter(keyBytes),
        _gcmTagLength,
        iv,
        Uint8List(0),
      ),
    );

    final input = Uint8List.fromList(utf8.encode(plainText));
    final output = Uint8List(gcm.getOutputSize(input.length));
    var outOff = 0;
    outOff += gcm.processBytes(input, 0, input.length, output, outOff);
    gcm.doFinal(output, outOff);

    return '${base64.encode(salt)}:${base64.encode(iv)}:${base64.encode(output)}';
  }

  /// Decrypt a string. Handles both GCM (3 segments) and legacy CBC (2 segments).
  String decryptString(String encryptedData, String passphrase) {
    final parts = encryptedData.split(':');

    if (parts.length == 3) {
      // GCM path
      return _decryptGcm(parts, passphrase);
    } else if (parts.length == 2) {
      // Legacy CBC migration path — decrypt and note for re-encryption
      developer.log(
        'Decrypting legacy CBC data. Re-encrypt after this call.',
        name: 'EncryptionService',
      );
      return _decryptLegacyCbc(parts, passphrase);
    } else {
      throw Exception(
        'Invalid encrypted data format (${parts.length} segments)',
      );
    }
  }

  String _decryptGcm(List<String> parts, String passphrase) {
    try {
      final salt = base64.decode(parts[0]);
      final iv = base64.decode(parts[1]);
      final ciphertext = base64.decode(parts[2]);
      final keyBytes = _deriveKey(passphrase, salt);

      final gcm = pc.GCMBlockCipher(pc.AESEngine());
      gcm.init(
        false,
        pc.AEADParameters(
          pc.KeyParameter(keyBytes),
          _gcmTagLength,
          iv,
          Uint8List(0),
        ),
      );

      final output = Uint8List(gcm.getOutputSize(ciphertext.length));
      var outOff = 0;
      outOff += gcm.processBytes(
        ciphertext,
        0,
        ciphertext.length,
        output,
        outOff,
      );
      gcm.doFinal(output, outOff);

      return utf8.decode(output.sublist(0, outOff));
    } on Exception catch (e) {
      throw Exception('GCM decryption failed: $e');
    }
  }

  String _decryptLegacyCbc(List<String> parts, String passphrase) {
    try {
      final iv = IV.fromBase64(parts[0]);
      final encrypted = Encrypted.fromBase64(parts[1]);
      final keyBytes = _deriveLegacyKey(passphrase);
      final encrypter = Encrypter(AES(Key(keyBytes), mode: AESMode.cbc));
      return encrypter.decrypt(encrypted, iv: iv);
    } on Exception catch (e) {
      throw Exception('CBC decryption failed: $e');
    }
  }

  /// Legacy SHA-256 key derivation — used only for migrating old CBC data.
  Uint8List _deriveLegacyKey(String passphrase) {
    final bytes = utf8.encode(passphrase);
    final digest = sha256.convert(bytes);
    return Uint8List.fromList(digest.bytes);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // JSON Encryption / Decryption
  // ─────────────────────────────────────────────────────────────────────────

  /// Encrypt a JSON map.
  String encryptJson(Map<String, dynamic> data, String passphrase) {
    return encryptString(json.encode(data), passphrase);
  }

  /// Decrypt a JSON map. Auto-migrates CBC → GCM on first access.
  Map<String, dynamic> decryptJson(String encryptedData, String passphrase) {
    final decryptedString = decryptString(encryptedData, passphrase);
    return json.decode(decryptedString) as Map<String, dynamic>;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Byte Encryption / Decryption
  // ─────────────────────────────────────────────────────────────────────────

  /// Encrypt raw bytes using AES-256-GCM.
  /// Returns: [saltBytes][ivBytes][gcmOutput] — a single flat Uint8List.
  /// Layout: first 16 bytes = salt, next 12 bytes = IV, rest = ciphertext+tag.
  Uint8List encryptBytes(Uint8List data, String passphrase) {
    final salt = _randomBytes(_saltLength);
    final iv = _randomBytes(_ivLengthGcm);
    final keyBytes = _deriveKey(passphrase, salt);

    final gcm = pc.GCMBlockCipher(pc.AESEngine());
    gcm.init(
      true,
      pc.AEADParameters(
        pc.KeyParameter(keyBytes),
        _gcmTagLength,
        iv,
        Uint8List(0),
      ),
    );

    final output = Uint8List(gcm.getOutputSize(data.length));
    var outOff = 0;
    outOff += gcm.processBytes(data, 0, data.length, output, outOff);
    gcm.doFinal(output, outOff);

    final result = Uint8List(_saltLength + _ivLengthGcm + output.length);
    result.setRange(0, _saltLength, salt);
    result.setRange(_saltLength, _saltLength + _ivLengthGcm, iv);
    result.setRange(_saltLength + _ivLengthGcm, result.length, output);
    return result;
  }

  /// Decrypt raw bytes. Handles GCM (28+ byte header) and legacy CBC (16-byte IV prefix).
  Uint8List decryptBytes(Uint8List encryptedData, String passphrase) {
    // GCM layout: 16 salt + 12 iv + ciphertext (min 28 bytes before ciphertext)
    // CBC layout: 16 iv + ciphertext (min 16 bytes before ciphertext)
    // We distinguish by trying GCM first when data is long enough.
    if (encryptedData.length > _saltLength + _ivLengthGcm) {
      try {
        return _decryptBytesGcm(encryptedData, passphrase);
      } on Exception {
        // Fall through to legacy CBC
      }
    }
    return _decryptBytesLegacyCbc(encryptedData, passphrase);
  }

  Uint8List _decryptBytesGcm(Uint8List encryptedData, String passphrase) {
    final salt = encryptedData.sublist(0, _saltLength);
    final iv = encryptedData.sublist(_saltLength, _saltLength + _ivLengthGcm);
    final ciphertext = encryptedData.sublist(_saltLength + _ivLengthGcm);
    final keyBytes = _deriveKey(passphrase, salt);

    final gcm = pc.GCMBlockCipher(pc.AESEngine());
    gcm.init(
      false,
      pc.AEADParameters(
        pc.KeyParameter(keyBytes),
        _gcmTagLength,
        iv,
        Uint8List(0),
      ),
    );

    final output = Uint8List(gcm.getOutputSize(ciphertext.length));
    var outOff = 0;
    outOff += gcm.processBytes(
      ciphertext,
      0,
      ciphertext.length,
      output,
      outOff,
    );
    gcm.doFinal(output, outOff);

    return output.sublist(0, outOff);
  }

  Uint8List _decryptBytesLegacyCbc(Uint8List encryptedData, String passphrase) {
    final iv = IV(encryptedData.sublist(0, 16));
    final encrypted = Encrypted(encryptedData.sublist(16));
    final keyBytes = _deriveLegacyKey(passphrase);
    final encrypter = Encrypter(AES(Key(keyBytes), mode: AESMode.cbc));
    return Uint8List.fromList(encrypter.decryptBytes(encrypted, iv: iv));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Hashing (unchanged — SHA-256 is appropriate for one-way hashing)
  // ─────────────────────────────────────────────────────────────────────────

  /// Hash data with SHA-256 (one-way).
  String hashData(String data) {
    final bytes = utf8.encode(data);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Verify hashed data.
  bool verifyHash(String data, String hash) => hashData(data) == hash;

  /// Generate a secure random token.
  String generateSecureToken([int length = 32]) {
    return base64.encode(_randomBytes(length));
  }
}
