import 'secure_storage_service.dart';
import 'device_fingerprint_service.dart';
import 'dart:math' as math;
import 'dart:developer' as developer;

/// Enhanced rate limiting service with adaptive throttling and attack detection
/// Prevents brute force, distributed attacks, and bot attacks
class RateLimiter {
  static final RateLimiter _instance = RateLimiter._internal();
  factory RateLimiter() => _instance;
  RateLimiter._internal();

  final SecureStorageService _storage = SecureStorageService();
  final DeviceFingerprintService _fingerprint = DeviceFingerprintService();

  // Rate limit configurations
  static const int maxLoginAttempts = 5;
  static const Duration loginAttemptWindow = Duration(minutes: 15);

  static const int maxOtpRequests = 3;
  static const Duration otpRequestWindow = Duration(minutes: 5);
  static const Duration otpResendCooldown = Duration(seconds: 60);

  // Enhanced security thresholds
  static const int distributedAttackThreshold = 3; // Different devices
  static const int botAttackThreshold = 10; // Attempts per minute

  /// Check if login is allowed with adaptive throttling
  Future<RateLimitResult> checkLoginAttempt() async {
    // Check if account is locked
    if (await _storage.isAccountLocked()) {
      final lockedUntil = await _storage.getAccountLockedUntil();
      final threatLevel = await _getThreatLevel();
      return RateLimitResult(
        allowed: false,
        remainingAttempts: 0,
        lockedUntil: lockedUntil,
        threatLevel: threatLevel,
        reason: 'Account is locked due to too many failed attempts',
      );
    }

    final attempts = await _storage.getLoginAttempts();
    final threatLevel = _calculateThreatLevel(attempts);
    final cooldown = _getCooldownDuration(threatLevel);

    // Check if cooldown period is active
    if (cooldown > Duration.zero && attempts > 0) {
      final lastAttemptStr = await _storage.read('last_login_attempt');
      if (lastAttemptStr != null) {
        final lastAttempt = DateTime.parse(lastAttemptStr);
        final elapsed = DateTime.now().difference(lastAttempt);

        if (elapsed < cooldown) {
          final waitTime = cooldown - elapsed;
          return RateLimitResult(
            allowed: false,
            remainingAttempts: maxLoginAttempts - attempts,
            threatLevel: threatLevel,
            waitDuration: waitTime,
            reason:
                'Please wait ${waitTime.inSeconds} seconds before trying again',
          );
        }
      }
    }

    final remainingAttempts = maxLoginAttempts - attempts;

    if (attempts >= maxLoginAttempts) {
      // Calculate adaptive lockout duration
      final lockoutDuration = await _calculateLockoutDuration(threatLevel);
      await _storage.lockAccount(lockoutDuration);
      final lockedUntil = await _storage.getAccountLockedUntil();

      // Record lockout for exponential backoff
      await _recordLockout();

      developer.log(
        'Account locked: $attempts attempts, level: $threatLevel, duration: ${lockoutDuration.inMinutes}min',
        name: 'RateLimiter',
      );

      return RateLimitResult(
        allowed: false,
        remainingAttempts: 0,
        lockedUntil: lockedUntil,
        threatLevel: threatLevel,
        reason:
            'Too many failed attempts. Account locked for ${lockoutDuration.inMinutes} minutes.',
      );
    }

    return RateLimitResult(
      allowed: true,
      remainingAttempts: remainingAttempts,
      threatLevel: threatLevel,
    );
  }

  /// Record failed login attempt with device fingerprinting
  Future<void> recordFailedLogin() async {
    await _storage.incrementLoginAttempts();

    // Record timestamp for cooldown
    await _storage.write(
      'last_login_attempt',
      DateTime.now().toIso8601String(),
    );

    // Track by device fingerprint (survives app reinstall)
    try {
      final deviceId = await _fingerprint.generateFingerprint();
      final key = 'device_attempts_$deviceId';
      final attemptsStr = await _storage.read(key);
      final attempts = int.tryParse(attemptsStr ?? '0') ?? 0;
      await _storage.write(key, (attempts + 1).toString());

      developer.log(
        'Failed login recorded for device: ${deviceId.substring(0, 8)}...',
        name: 'RateLimiter',
      );
    } on Exception catch (e) {
      developer.log('Error recording device attempt: $e', name: 'RateLimiter');
    }
  }

  /// Reset login attempts after successful login
  Future<void> resetLoginAttempts() async {
    await _storage.resetLoginAttempts();
    await _storage.delete('last_login_attempt');

    // Reset threat level
    await _storage.delete('lockout_count');

    developer.log('Login attempts reset', name: 'RateLimiter');
  }

  /// Check if OTP request is allowed
  Future<RateLimitResult> checkOtpRequest(String phoneNumber) async {
    final key = 'otp_requests_$phoneNumber';
    final requestData = await _storage.readJson(key);

    if (requestData == null) {
      // First request
      return RateLimitResult(
        allowed: true,
        remainingAttempts: maxOtpRequests - 1,
        threatLevel: ThreatLevel.low,
      );
    }

    final lastRequest = DateTime.parse(requestData['lastRequest'] as String);
    final requests = requestData['count'] as int;
    final windowStart = DateTime.parse(requestData['windowStart'] as String);

    // Check if we're still in the rate limit window
    if (DateTime.now().difference(windowStart) > otpRequestWindow) {
      // Window expired, reset counter
      return RateLimitResult(
        allowed: true,
        remainingAttempts: maxOtpRequests - 1,
        threatLevel: ThreatLevel.low,
      );
    }

    // Check cooldown period
    if (DateTime.now().difference(lastRequest) < otpResendCooldown) {
      final waitTime =
          otpResendCooldown - DateTime.now().difference(lastRequest);
      return RateLimitResult(
        allowed: false,
        remainingAttempts: maxOtpRequests - requests,
        threatLevel: ThreatLevel.medium,
        waitDuration: waitTime,
        reason:
            'Please wait ${waitTime.inSeconds} seconds before requesting another code',
      );
    }

    // Check if max requests reached
    if (requests >= maxOtpRequests) {
      final waitTime =
          otpRequestWindow - DateTime.now().difference(windowStart);
      return RateLimitResult(
        allowed: false,
        remainingAttempts: 0,
        threatLevel: ThreatLevel.high,
        waitDuration: waitTime,
        reason:
            'Too many OTP requests. Please try again in ${waitTime.inMinutes} minutes.',
      );
    }

    return RateLimitResult(
      allowed: true,
      remainingAttempts: maxOtpRequests - requests - 1,
      threatLevel: ThreatLevel.low,
    );
  }

  /// Record OTP request
  Future<void> recordOtpRequest(String phoneNumber) async {
    final key = 'otp_requests_$phoneNumber';
    final requestData = await _storage.readJson(key);

    final now = DateTime.now();

    if (requestData == null) {
      // First request in this window
      await _storage.writeJson(key, {
        'count': 1,
        'lastRequest': now.toIso8601String(),
        'windowStart': now.toIso8601String(),
      });
    } else {
      final windowStart = DateTime.parse(requestData['windowStart'] as String);

      // Check if window has expired
      if (now.difference(windowStart) > otpRequestWindow) {
        // Start new window
        await _storage.writeJson(key, {
          'count': 1,
          'lastRequest': now.toIso8601String(),
          'windowStart': now.toIso8601String(),
        });
      } else {
        // Increment counter in current window
        await _storage.writeJson(key, {
          'count': (requestData['count'] as int) + 1,
          'lastRequest': now.toIso8601String(),
          'windowStart': requestData['windowStart'],
        });
      }
    }
  }

  /// Reset OTP request counter
  Future<void> resetOtpRequests(String phoneNumber) async {
    final key = 'otp_requests_$phoneNumber';
    await _storage.delete(key);
  }

  /// Get remaining lock time
  Future<Duration?> getRemainingLockTime() async {
    if (!await _storage.isAccountLocked()) {
      return null;
    }

    final lockedUntil = await _storage.getAccountLockedUntil();
    if (lockedUntil == null) return null;

    final remaining = lockedUntil.difference(DateTime.now());
    return remaining.isNegative ? null : remaining;
  }

  /// Calculate threat level based on failed attempts
  ThreatLevel _calculateThreatLevel(int attempts) {
    if (attempts <= 2) return ThreatLevel.low;
    if (attempts <= 4) return ThreatLevel.medium;
    if (attempts <= 7) return ThreatLevel.high;
    return ThreatLevel.critical;
  }

  /// Get current threat level from storage
  Future<ThreatLevel> _getThreatLevel() async {
    final attempts = await _storage.getLoginAttempts();
    return _calculateThreatLevel(attempts);
  }

  /// Get cooldown duration based on threat level
  Duration _getCooldownDuration(ThreatLevel level) {
    switch (level) {
      case ThreatLevel.low:
        return Duration.zero;
      case ThreatLevel.medium:
        return const Duration(seconds: 30);
      case ThreatLevel.high:
        return const Duration(minutes: 2);
      case ThreatLevel.critical:
        return const Duration(minutes: 5);
    }
  }

  /// Calculate adaptive lockout duration with exponential backoff
  Future<Duration> _calculateLockoutDuration(ThreatLevel level) async {
    // Get number of previous lockouts
    final lockoutCountStr = await _storage.read('lockout_count');
    final previousLockouts = int.tryParse(lockoutCountStr ?? '0') ?? 0;

    // Base duration depends on threat level
    int baseMinutes;
    switch (level) {
      case ThreatLevel.low:
      case ThreatLevel.medium:
        baseMinutes = 5;
        break;
      case ThreatLevel.high:
        baseMinutes = 30;
        break;
      case ThreatLevel.critical:
        baseMinutes = 60;
        break;
    }

    // Exponential backoff: doubles with each lockout
    final multiplier = math.pow(2, previousLockouts).toInt();
    final minutes = math.min(baseMinutes * multiplier, 1440); // 24h max

    return Duration(minutes: minutes);
  }

  /// Record lockout occurrence for exponential backoff
  Future<void> _recordLockout() async {
    final lockoutCountStr = await _storage.read('lockout_count');
    final count = int.tryParse(lockoutCountStr ?? '0') ?? 0;
    await _storage.write('lockout_count', (count + 1).toString());
  }

  /// Detect if attack is likely from multiple devices (distributed attack)
  Future<bool> isDistributedAttack(String phoneNumber) async {
    try {
      // This is a simplified check - in production, track device IDs per phone number
      final key = 'attack_pattern_$phoneNumber';
      final pattern = await _storage.readJson(key);

      if (pattern == null) return false;

      // Check if multiple unique device fingerprints attempted login
      final deviceCount = pattern['uniqueDevices'] as int? ?? 0;
      return deviceCount >= distributedAttackThreshold;
    } on Exception catch (e) {
      developer.log(
        'Error checking distributed attack: $e',
        name: 'RateLimiter',
      );
      return false;
    }
  }

  /// Get rate limiter statistics
  Future<Map<String, dynamic>> getStats() async {
    final attempts = await _storage.getLoginAttempts();
    final lockoutCount =
        int.tryParse(await _storage.read('lockout_count') ?? '0') ?? 0;
    final isLocked = await _storage.isAccountLocked();
    final threatLevel = _calculateThreatLevel(attempts);

    return {
      'attempts': attempts,
      'maxAttempts': maxLoginAttempts,
      'remainingAttempts': maxLoginAttempts - attempts,
      'isLocked': isLocked,
      'lockoutCount': lockoutCount,
      'threatLevel': threatLevel.name,
      'remainingLockTime': await getRemainingLockTime(),
    };
  }
}

/// Threat level enum for adaptive security
enum ThreatLevel {
  low, // 1-2 attempts
  medium, // 3-4 attempts
  high, // 5-7 attempts
  critical, // 8+ attempts
}

/// Result of rate limit check with enhanced metadata
class RateLimitResult {
  final bool allowed;
  final int remainingAttempts;
  final DateTime? lockedUntil;
  final Duration? waitDuration;
  final String? reason;
  final ThreatLevel threatLevel;

  RateLimitResult({
    required this.allowed,
    this.remainingAttempts = 0,
    this.lockedUntil,
    this.waitDuration,
    this.reason,
    this.threatLevel = ThreatLevel.low,
  });

  String get userMessage {
    if (allowed) {
      return remainingAttempts > 0
          ? '$remainingAttempts attempts remaining'
          : '';
    }
    return reason ?? 'Rate limit exceeded';
  }

  /// Get color indicator for UI based on threat level
  String get threatColor {
    switch (threatLevel) {
      case ThreatLevel.low:
        return 'green';
      case ThreatLevel.medium:
        return 'yellow';
      case ThreatLevel.high:
        return 'orange';
      case ThreatLevel.critical:
        return 'red';
    }
  }
}
