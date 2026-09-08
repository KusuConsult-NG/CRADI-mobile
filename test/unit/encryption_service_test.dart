import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:climate_app/core/services/encryption_service.dart';

/// Tests for EncryptionService — AES-256-GCM string/json/byte encryption,
/// key derivation, and hashing.
void main() {
  late EncryptionService svc;

  setUp(() {
    svc = EncryptionService();
  });

  group('String Encryption / Decryption (GCM)', () {
    test('encrypt then decrypt returns original text', () {
      const plain = 'Hello, CRADI!';
      const passphrase = 'test-pass-123';
      final cipher = svc.encryptString(plain, passphrase);
      final result = svc.decryptString(cipher, passphrase);
      expect(result, equals(plain));
    });

    test('ciphertext has 3 colon-separated base64 segments', () {
      final cipher = svc.encryptString('data', 'key');
      final parts = cipher.split(':');
      expect(parts.length, equals(3));
      // Each segment should be valid base64
      for (final p in parts) {
        expect(() => base64.decode(p), returnsNormally);
      }
    });

    test('two encryptions of same plaintext produce different ciphertext', () {
      const plain = 'same data';
      const pass = 'pass';
      final c1 = svc.encryptString(plain, pass);
      final c2 = svc.encryptString(plain, pass);
      expect(c1, isNot(equals(c2)));
    });

    test('wrong passphrase fails to decrypt', () {
      final cipher = svc.encryptString('secret', 'correct');
      expect(() => svc.decryptString(cipher, 'wrong'), throwsException);
    });

    test('handles empty string', () {
      final cipher = svc.encryptString('', 'key');
      final result = svc.decryptString(cipher, 'key');
      expect(result, equals(''));
    });

    test('handles unicode text', () {
      const plain = 'Ọjọ́ rere! 🌍🇳🇬';
      final cipher = svc.encryptString(plain, 'unicode-pass');
      final result = svc.decryptString(cipher, 'unicode-pass');
      expect(result, equals(plain));
    });

    test('handles long text', () {
      final plain = 'A' * 10000;
      final cipher = svc.encryptString(plain, 'long-key');
      final result = svc.decryptString(cipher, 'long-key');
      expect(result, equals(plain));
    });
  });

  group('JSON Encryption / Decryption', () {
    test('encrypt then decrypt returns original JSON', () {
      final data = {'name': 'CRADI', 'version': 1, 'active': true};
      final cipher = svc.encryptJson(data, 'json-key');
      final result = svc.decryptJson(cipher, 'json-key');
      expect(result, equals(data));
    });

    test('handles nested JSON', () {
      final data = {
        'user': {
          'name': 'Test',
          'roles': ['admin', 'user'],
        },
        'score': 42.5,
      };
      final cipher = svc.encryptJson(data, 'nested');
      final result = svc.decryptJson(cipher, 'nested');
      expect(result['user']['name'], equals('Test'));
      expect((result['user']['roles'] as List).length, equals(2));
    });
  });

  group('Byte Encryption / Decryption (GCM)', () {
    test('encrypt then decrypt returns original bytes', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final cipher = svc.encryptBytes(data, 'byte-key');
      final result = svc.decryptBytes(cipher, 'byte-key');
      expect(result, equals(data));
    });

    test('encrypted bytes are longer than original (salt + IV + tag)', () {
      final data = Uint8List.fromList([10, 20, 30]);
      final cipher = svc.encryptBytes(data, 'size-key');
      // 16 salt + 12 IV + input + 16 tag = at minimum 47 bytes
      expect(cipher.length, greaterThan(data.length + 28));
    });
  });

  group('Hashing', () {
    test('SHA-256 hash is deterministic', () {
      expect(svc.hashData('hello'), equals(svc.hashData('hello')));
    });

    test('different input produces different hash', () {
      expect(svc.hashData('a'), isNot(equals(svc.hashData('b'))));
    });

    test('verifyHash returns true for matching data', () {
      final hash = svc.hashData('verify-me');
      expect(svc.verifyHash('verify-me', hash), isTrue);
    });

    test('verifyHash returns false for mismatched data', () {
      final hash = svc.hashData('original');
      expect(svc.verifyHash('modified', hash), isFalse);
    });
  });

  group('Secure Token Generation', () {
    test('generates base64-encoded token', () {
      final token = svc.generateSecureToken();
      expect(() => base64.decode(token), returnsNormally);
    });

    test('two tokens are different', () {
      final t1 = svc.generateSecureToken();
      final t2 = svc.generateSecureToken();
      expect(t1, isNot(equals(t2)));
    });

    test('custom length changes output size', () {
      final short = svc.generateSecureToken(16);
      final long = svc.generateSecureToken(64);
      expect(short.length, lessThan(long.length));
    });
  });

  group('Invalid Data Handling', () {
    test('invalid segment count throws', () {
      expect(
        () => svc.decryptString('only-one-segment', 'key'),
        throwsException,
      );
    });

    test('four segments throws', () {
      expect(() => svc.decryptString('a:b:c:d', 'key'), throwsException);
    });
  });
}
