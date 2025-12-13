import 'secure_storage_service.dart';

/// Rate limiting service to prevent brute force attacks
class RateLimiter {
  static final RateLimiter _instance = RateLimiter._internal();
  factory RateLimiter() => _instance;
  RateLimiter._internal();

  final SecureStorageService _storage = SecureStorageService();

  // Rate limit configurations
  static const int maxLoginAttempts = 5;
  static const Duration loginAttemptWindow = Duration(minutes: 15);
  static const Duration accountLockDuration = Duration(minutes: 30);
  
  static const int maxOtpRequests = 3;
  static const Duration otpRequestWindow = Duration(minutes: 5);
  static const Duration otpResendCooldown = Duration(seconds: 60);

  /// Check if login is allowed
  Future<RateLimitResult> checkLoginAttempt() async {
    // Check if account is locked
    if (await _storage.isAccountLocked()) {
      final lockedUntil = await _storage.getAccountLockedUntil();
      return RateLimitResult(
        allowed: false,
        remainingAttempts: 0,
        lockedUntil: lockedUntil,
        reason: 'Account is locked due to too many failed attempts',
      );
    }

    final attempts = await _storage.getLoginAttempts();
    final remainingAttempts = maxLoginAttempts - attempts;

    if (attempts >= maxLoginAttempts) {
      // Lock the account
      await _storage.lockAccount(accountLockDuration);
      final lockedUntil = await _storage.getAccountLockedUntil();
      
      return RateLimitResult(
        allowed: false,
        remainingAttempts: 0,
        lockedUntil: lockedUntil,
        reason: 'Too many failed attempts. Account locked for ${accountLockDuration.inMinutes} minutes.',
      );
    }

    return RateLimitResult(
      allowed: true,
      remainingAttempts: remainingAttempts,
    );
  }

  /// Record failed login attempt
  Future<void> recordFailedLogin() async {
    await _storage.incrementLoginAttempts();
  }

  /// Reset login attempts after successful login
  Future<void> resetLoginAttempts() async {
    await _storage.resetLoginAttempts();
  }

  /// Check if OTP request is allowed
  Future<RateLimitResult> checkOtpRequest(String phoneNumber) async {
    final key = 'otp_requests_$phoneNumber';
    final requestData = await _storage.readJson(key);
    
    if (requestData == null) {
      // First request
      return RateLimitResult(allowed: true, remainingAttempts: maxOtpRequests - 1);
    }

    final lastRequest = DateTime.parse(requestData['lastRequest'] as String);
    final requests = requestData['count'] as int;
    final windowStart = DateTime.parse(requestData['windowStart'] as String);

    // Check if we're still in the rate limit window
    if (DateTime.now().difference(windowStart) > otpRequestWindow) {
      // Window expired, reset counter
      return RateLimitResult(allowed: true, remainingAttempts: maxOtpRequests - 1);
    }

    // Check cooldown period
    if (DateTime.now().difference(lastRequest) < otpResendCooldown) {
      final waitTime = otpResendCooldown - DateTime.now().difference(lastRequest);
      return RateLimitResult(
        allowed: false,
        remainingAttempts: maxOtpRequests - requests,
        waitDuration: waitTime,
        reason: 'Please wait ${waitTime.inSeconds} seconds before requesting another code',
      );
    }

    // Check if max requests reached
    if (requests >= maxOtpRequests) {
      final waitTime = otpRequestWindow - DateTime.now().difference(windowStart);
      return RateLimitResult(
        allowed: false,
        remainingAttempts: 0,
        waitDuration: waitTime,
        reason: 'Too many OTP requests. Please try again in ${waitTime.inMinutes} minutes.',
      );
    }

    return RateLimitResult(
      allowed: true,
      remainingAttempts: maxOtpRequests - requests - 1,
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
}

/// Result of rate limit check
class RateLimitResult {
  final bool allowed;
  final int remainingAttempts;
  final DateTime? lockedUntil;
  final Duration? waitDuration;
  final String? reason;

  RateLimitResult({
    required this.allowed,
    this.remainingAttempts = 0,
    this.lockedUntil,
    this.waitDuration,
    this.reason,
  });

  String get userMessage {
    if (allowed) {
      return remainingAttempts > 0 
          ? '$remainingAttempts attempts remaining'
          : '';
    }
    return reason ?? 'Rate limit exceeded';
  }
}
