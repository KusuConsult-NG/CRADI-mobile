import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/core/utils/validators.dart';
import 'package:climate_app/core/utils/input_sanitizer.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:climate_app/core/services/rate_limiter.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _rateLimiter = RateLimiter();
  bool _isLoading = false;
  String? _errorMessage;
  int _remainingAttempts = 5;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;

  @override
  void initState() {
    super.initState();
    _checkRateLimit();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    try {
      final authProvider = context.read<AuthProvider>();
      final available = await authProvider.isBiometricAvailable();
      final enabled = await authProvider.isBiometricEnabled();

      if (mounted) {
        setState(() {
          _biometricAvailable = available;
          _biometricEnabled = enabled;
        });
      }
    } catch (e) {
      // Biometric check failed, continue without it
    }
  }

  Future<void> _authenticateWithBiometric() async {
    setState(() => _isLoading = true);

    try {
      final authProvider = context.read<AuthProvider>();
      final success = await authProvider.authenticateWithBiometrics();

      if (!mounted) return; // Check mounted after async call

      setState(() => _isLoading = false);

      if (success) {
        context.go('/dashboard');
      } else {
        setState(() {
          _errorMessage = 'Biometric authentication failed. Please try again.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          // strip "Exception: " if present
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
      ErrorHandler.logError(
        e,
        context: 'LoginScreen._authenticateWithBiometric',
      );
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _checkRateLimit() async {
    final result = await _rateLimiter.checkLoginAttempt();
    if (mounted) {
      setState(() {
        _remainingAttempts = result.remainingAttempts;
      });
    }
  }

  Future<void> _submit() async {
    // Clear previous error
    setState(() => _errorMessage = null);

    if (_formKey.currentState!.validate()) {
      // Read provider before any async operations
      final authProvider = context.read<AuthProvider>();

      setState(() => _isLoading = true);

      try {
        // Check rate limiting before attempting login
        final rateLimitResult = await _rateLimiter.checkLoginAttempt();

        if (!rateLimitResult.allowed) {
          setState(() {
            _errorMessage = rateLimitResult.userMessage;
            _isLoading = false;
          });
          return;
        }

        // Sanitize inputs
        final sanitizedCode = InputSanitizer.sanitizeAlphanumeric(
          _codeController.text,
        );
        final sanitizedPhone = InputSanitizer.sanitizePhoneNumber(
          _phoneController.text,
        );
        final normalizedPhone = Validators.normalizePhoneNumber(sanitizedPhone);

        // Attempt verification
        final success = await authProvider.verifyRegistrationCode(
          sanitizedCode,
          normalizedPhone,
        );

        if (!mounted) return;

        setState(() => _isLoading = false);

        if (success) {
          if (!mounted) return;
          context.push('/otp');
        } else if (mounted) {
          await _checkRateLimit();
          setState(() {
            _errorMessage = 'Invalid registration code or phone number';
          });
        }
      } on AuthException catch (e) {
        setState(() {
          _errorMessage = e.userMessage;
          _isLoading = false;
        });
        await _checkRateLimit();
      } catch (e) {
        setState(() {
          _errorMessage = ErrorHandler.getUserMessage(e);
          _isLoading = false;
        });
        ErrorHandler.logError(e, context: 'LoginScreen._submit');
        await _checkRateLimit();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
              // Logo
              Image.asset(
                'assets/images/cradi_logo.jpg',
                height: 100,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.shield,
                  size: 80,
                  color: AppColors.primaryRed,
                ),
              ),
              const SizedBox(height: 32),

              Text(
                'Welcome Back',
                style: Theme.of(context).textTheme.displayMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your details to access the\nEarly Warning System',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),

              // Error message display
              if (_errorMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Colors.red.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Rate limit warning
              if (_remainingAttempts < 5 && _remainingAttempts > 0)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber,
                        color: Colors.orange.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$_remainingAttempts login attempts remaining',
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                        prefixIcon: Icon(Icons.phone),
                        hintText: '08012345678',
                      ),
                      validator: Validators.validatePhoneNumber,
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _codeController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Registration Code',
                        prefixIcon: Icon(Icons.vpn_key),
                        hintText: 'e.g. EWM123',
                      ),
                      validator: Validators.validateRegistrationCode,
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 8),
                    // Security hint
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 14,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Your registration code was provided by your coordinator',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submit,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Continue'),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Biometric login option
              if (_biometricAvailable && _biometricEnabled)
                Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: Divider(color: Colors.grey.shade300)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'OR',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: Colors.grey.shade300)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: _isLoading ? null : _authenticateWithBiometric,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryRed,
                        side: BorderSide(color: AppColors.primaryRed, width: 2),
                        padding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 24,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: Icon(
                        Icons.fingerprint,
                        size: 28,
                        color: AppColors.primaryRed,
                      ),
                      label: const Text(
                        'Login with Biometrics',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),

              // Security info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.security, color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your data is encrypted and secure',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
