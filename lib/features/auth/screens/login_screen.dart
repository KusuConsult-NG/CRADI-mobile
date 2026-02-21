import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/profile/providers/profile_provider.dart';
import 'package:climate_app/shared/widgets/custom_button.dart';
import 'package:climate_app/shared/widgets/custom_text_field.dart';
import 'package:climate_app/core/utils/validators.dart';

import 'package:climate_app/core/utils/error_handler.dart';
import 'package:climate_app/core/services/rate_limiter.dart';
import 'package:climate_app/core/design/glass_container.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
// TEMPORARILY DISABLED - Compatibility issue\n// import 'package:flutter_windowmanager/flutter_windowmanager.dart';
import 'dart:io' show Platform;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();

  final _rateLimiter = RateLimiter();
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  String? _errorMessage;
  int _remainingAttempts = 5;

  @override
  void initState() {
    super.initState();
    _enableScreenSecurity();
    _checkRateLimit();
  }

  /// Enable screenshot prevention on Android
  Future<void> _enableScreenSecurity() async {
    if (Platform.isAndroid) {
      // TEMPORARILY DISABLED - flutter_windowmanager compatibility issue
      // try {
      //   await FlutterWindowManager.addFlags(FlutterWindowManager.FLAG_SECURE);
      // } on Exception catch (e) {
      //   // Silently fail - non-critical security feature
      //   ErrorHandler.logError(e, context: 'LoginScreen.enableScreenSecurity');
      // }
    }
  }

  Future<void> _disableScreenSecurity() async {
    if (Platform.isAndroid) {
      // TEMPORARILY DISABLED
      // try {
      //   await FlutterWindowManager.clearFlags(FlutterWindowManager.FLAG_SECURE);
      // } on Exception {
      //   // Silently fail
      // }
    }
  }

  @override
  void dispose() {
    _disableScreenSecurity();
    _identifierController.dispose();
    _passwordController.dispose();
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

        final identifier = _identifierController.text.trim();
        final password = _passwordController.text;

        // Check if input is email or phone
        final isEmail = Validators.isValidEmail(identifier);

        if (!isEmail) {
          // Assume phone number logic here
          // For now, blocking phone login as per plan until backend supports lookup
          setState(() {
            _errorMessage =
                'Login with Phone Number is coming soon. Please use your Email Address.';
            _isLoading = false;
          });
          return;
        }

        // Direct email/password login
        final success = await authProvider.signInWithEmail(
          email: identifier,
          password: password,
        );

        if (!mounted) return;

        setState(() => _isLoading = false);

        if (success) {
          // Reload profile to get fresh user data from Appwrite
          if (!mounted) return;
          await context.read<ProfileProvider>().loadProfile();

          // Route directly to dashboard since approval is removed
          if (!mounted) return;
          context.go('/dashboard');
        } else {
          setState(() {
            _errorMessage = 'Login failed. Please check your credentials.';
          });
        }
      } on AuthException catch (e) {
        if (!mounted) return;
        setState(() {
          _errorMessage = e.userMessage;
          _isLoading = false;
        });
        await _checkRateLimit();
      } on Exception catch (e) {
        if (!mounted) return;
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
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        if (authProvider.isLocked) {
          return _buildLockScreen(authProvider);
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 48),
                  // EWER Logo with glass effect
                  Center(
                    child: GlassContainer(
                      width: 140,
                      height: 140,
                      borderRadius: 70,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryRed.withValues(
                                alpha: 0.3,
                              ),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/images/ewer_logo.jpg',
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFFE53935),
                                        Color(0xFFB71C1C),
                                        Color(0xFF5D5D5D),
                                      ],
                                    ),
                                  ),
                                  child: const Center(
                                    child: Text(
                                      'EWER',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 32,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                  ),
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  Text(
                    'Welcome Back',
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontSize: 34, // Explicit larger size
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in to your account',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 18, // Increased from default
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),

                  // Glassmorphic form container
                  GlassCard(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
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
                                border: Border.all(
                                  color: Colors.orange.shade200,
                                ),
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

                          // Email/Phone field
                          CustomTextField(
                            label: 'Email or Phone Number',
                            controller: _identifierController,
                            keyboardType: TextInputType.emailAddress,
                            prefixIcon: const Icon(
                              Icons.person_outline,
                            ), // Generic icon
                            hint: 'email@example.com or +234...',
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your email or phone number';
                              }
                              return null; // We allow both, so no strict email validation here
                            },
                            enabled: !_isLoading,
                          ),

                          // Password field
                          CustomTextField(
                            label: 'Password',
                            controller: _passwordController,
                            obscureText: !_isPasswordVisible,
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _isPasswordVisible
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () {
                                setState(() {
                                  _isPasswordVisible = !_isPasswordVisible;
                                });
                              },
                            ),
                            validator: (value) =>
                                Validators.validateRequired(value, 'Password'),
                            enabled: !_isLoading,
                          ),
                          const SizedBox(height: 16),

                          // Forgot Password
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _isLoading
                                  ? null
                                  : () => context.push('/forgot-password'),
                              child: const Text(
                                'Forgot Password?',
                                style: TextStyle(
                                  fontSize: 16, // Increased
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Login button
                          CustomButton(
                            text: 'Login',
                            onPressed: _isLoading ? null : _submit,
                            isLoading: _isLoading,
                          ),
                          const SizedBox(height: 16),

                          // Sign Up Link
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "Don't have an account? ",
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 16, // Increased
                                ),
                              ),
                              TextButton(
                                onPressed: _isLoading
                                    ? null
                                    : () => context.push('/register'),
                                child: const Text(
                                  'Sign Up',
                                  style: TextStyle(
                                    fontSize: 18, // Increased
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ), // Close GlassCard

                  const SizedBox(height: 24),

                  // Biometric login option
                  FutureBuilder<bool>(
                    future: Future.wait([
                      authProvider.isBiometricAvailable(),
                    ]).then((results) => results[0]),
                    builder: (context, snapshot) {
                      if (snapshot.data == true) {
                        return Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Divider(color: Colors.grey.shade300),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: Text(
                                    'OR',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Divider(color: Colors.grey.shade300),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            CustomButton(
                              text: 'Login with Biometrics',
                              onPressed: _isLoading
                                  ? null
                                  : () async {
                                      // Capture router before async gap
                                      final router = GoRouter.of(context);

                                      setState(() => _isLoading = true);
                                      final enabled = await authProvider
                                          .isBiometricEnabled();
                                      if (!enabled) {
                                        setState(() {
                                          _isLoading = false;
                                          _errorMessage =
                                              'Biometric login is not enabled. Please login with your email/code once and enable it in Settings.';
                                        });
                                        return;
                                      }

                                      final success = await authProvider
                                          .authenticateWithBiometrics();

                                      if (!mounted) return;

                                      setState(() => _isLoading = false);

                                      if (!mounted) return;

                                      if (success) {
                                        router.go('/dashboard');
                                      } else {
                                        setState(() {
                                          _errorMessage =
                                              'Biometric authentication failed. Please try again or use email login.';
                                        });
                                      }
                                    },
                              icon: Icons.fingerprint,
                              type: ButtonType.secondary,
                            ),
                            const SizedBox(height: 24),
                          ],
                        );
                      }
                      return const SizedBox.shrink();
                    },
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
                        Icon(
                          Icons.security,
                          color: Colors.blue.shade700,
                          size: 20,
                        ),
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
      },
    );
  }

  Widget _buildLockScreen(AuthProvider authProvider) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.lock_outline,
                size: 80,
                color: AppColors.textPrimary,
              ),
              const SizedBox(height: 24),
              Text(
                'CRADI Mobile Locked',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Please authenticate to continue',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              CustomButton(
                text: 'Unlock with Biometrics',
                onPressed: () async {
                  final success = await authProvider.unlockApp();
                  if (success && mounted) {
                    context.go('/dashboard');
                  }
                },
                icon: Icons.fingerprint,
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () {
                  context.read<ProfileProvider>().clearProfile();
                  authProvider.logout();
                },
                child: const Text('Log out and use different account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
