import 'package:climate_app/core/router/route_guard.dart';
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
import 'package:climate_app/core/l10n/l10n.dart';

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
  bool _rememberMe = false;
  // Phone accounts have no password: they sign in with an SMS code.
  bool _usePhone = false;
  String? _errorMessage;
  int _remainingAttempts = 5;

  @override
  void initState() {
    super.initState();
    _checkRateLimit();
  }

  @override
  void dispose() {
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

  /// Where to continue after sign-in / unlock: the page that sent the user
  /// here (`from`, e.g. a notification tap) or the dashboard.
  String _destination() {
    final from = GoRouterState.of(context).uri.queryParameters['from'];
    return sanitizeRedirectTarget(from) ?? '/dashboard';
  }

  /// Phone sign-in: sends an SMS code to an existing account and opens the
  /// code entry screen (which verifies it as an `sms` OTP).
  Future<void> _submitPhone() async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final phone = Validators.normalizePhoneNumber(
      _identifierController.text.trim(),
    );
    setState(() => _isLoading = true);
    try {
      await authProvider.sendOtpForPhone(phone, loginOnly: true);
      if (!mounted) return;
      setState(() => _isLoading = false);
      await context.push('/verify-otp?phone=${Uri.encodeComponent(phone)}');
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.userMessage(context.l10n);
        _isLoading = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = ErrorHandler.getUserMessage(e, context.l10n);
        _isLoading = false;
      });
      ErrorHandler.logError(e, context: 'LoginScreen._submitPhone');
    }
  }

  Widget _buildMethodToggle() {
    Widget option(String label, bool phone) {
      final selected = _usePhone == phone;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _isLoading || selected
              ? null
              : () => setState(() {
                  _usePhone = phone;
                  _errorMessage = null;
                  _identifierController.clear();
                }),
          child: Container(
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryRed : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 44,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          option(context.l10n.authMethodEmail, false),
          option(context.l10n.authMethodPhone, true),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_usePhone) return _submitPhone();

    // Clear previous error
    setState(() => _errorMessage = null);

    if (_formKey.currentState!.validate()) {
      // Read providers before any async operations
      final authProvider = context.read<AuthProvider>();
      final profileProvider = context.read<ProfileProvider>();
      final destination = _destination();

      setState(() => _isLoading = true);

      try {
        // Check rate limiting before attempting login
        final rateLimitResult = await _rateLimiter.checkLoginAttempt();

        if (!rateLimitResult.allowed) {
          if (!mounted) return;
          setState(() {
            _errorMessage = rateLimitResult.userMessage(context.l10n);
            _isLoading = false;
          });
          return;
        }

        final identifier = _identifierController.text.trim();
        final password = _passwordController.text;

        // Direct email/password login
        final success = await authProvider.signInWithEmail(
          email: identifier,
          password: password,
          rememberMe: _rememberMe,
        );

        if (mounted) setState(() => _isLoading = false);

        if (success) {
          // Reload profile to get fresh user data. The router may already
          // have left this screen (signed-in users are redirected away from
          // /login), so this must not depend on `mounted`.
          await profileProvider.loadProfile();

          // Same destination the router redirect picks.
          if (!mounted) return;
          context.go(destination);
        } else {
          if (!mounted) return;
          setState(() {
            _errorMessage = context.l10n.authLoginCheckCredentials;
          });
        }
      } on EmailNotConfirmedException catch (e) {
        // Account exists but the email was never confirmed: a new code was
        // sent — take the user to the code entry screen.
        if (!mounted) return;
        setState(() {
          _errorMessage = e.userMessage(context.l10n);
          _isLoading = false;
        });
        context.push('/verify-otp?phone=${Uri.encodeComponent(e.email)}');
      } on AuthException catch (e) {
        if (!mounted) return;
        setState(() {
          _errorMessage = e.userMessage(context.l10n);
          _isLoading = false;
        });
        await _checkRateLimit();
      } on Exception catch (e) {
        if (!mounted) return;
        setState(() {
          _errorMessage = ErrorHandler.getUserMessage(e, context.l10n);
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
                    context.l10n.loginWelcomeBack,
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontSize: 34, // Explicit larger size
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.loginSubtitle,
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
                                      context.l10n.rateLimitAttemptsRemaining(
                                        _remainingAttempts,
                                      ),
                                      style: TextStyle(
                                        color: Colors.orange.shade700,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          if (AuthProvider.phoneAuthEnabled)
                            _buildMethodToggle(),

                          if (_usePhone)
                            CustomTextField(
                              key: const ValueKey('login-phone'),
                              label: context.l10n.authPhoneNumber,
                              controller: _identifierController,
                              keyboardType: TextInputType.phone,
                              prefixIcon: const Icon(Icons.phone_outlined),
                              hint: '+234 801 234 5678',
                              validator: (v) => Validators.validatePhoneNumber(
                                v,
                                context.l10n,
                              ),
                              enabled: !_isLoading,
                            )
                          else
                            // Email field
                            CustomTextField(
                              key: const ValueKey('login-email'),
                              label: context.l10n.emailAddress,
                              controller: _identifierController,
                              keyboardType: TextInputType.emailAddress,
                              prefixIcon: const Icon(Icons.email_outlined),
                              hint: 'email@example.com',
                              // Validated as it is submitted: trimmed (a
                              // pasted / autofilled address often carries
                              // a trailing space).
                              validator: (v) => Validators.validateEmail(
                                v?.trim(),
                                context.l10n,
                              ),
                              enabled: !_isLoading,
                            ),

                          // Password field
                          if (!_usePhone)
                            CustomTextField(
                              label: context.l10n.authPassword,
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
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return context.l10n.validatorPasswordRequired;
                                }
                                return null;
                              },
                              enabled: !_isLoading,
                            ),
                          const SizedBox(height: 16),

                          // Remember me and Forgot Password
                          if (!_usePhone)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Checkbox(
                                      value: _rememberMe,
                                      activeColor: AppColors.primaryRed,
                                      onChanged: _isLoading
                                          ? null
                                          : (value) {
                                              setState(() {
                                                _rememberMe = value ?? false;
                                              });
                                            },
                                    ),
                                    Text(
                                      context.l10n.loginRememberMe,
                                      style: const TextStyle(
                                        fontSize:
                                            15, // Matched somewhat with other texts
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                TextButton(
                                  onPressed: _isLoading
                                      ? null
                                      : () => context.push('/forgot-password'),
                                  child: Text(
                                    context.l10n.forgotTitle,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 24),

                          // Login button
                          CustomButton(
                            text: _usePhone
                                ? context.l10n.loginSendCode
                                : context.l10n.authLogin,
                            onPressed: _isLoading ? null : _submit,
                            isLoading: _isLoading,
                          ),
                          const SizedBox(height: 16),

                          // Sign Up Link
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                context.l10n.loginNoAccount,
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 16, // Increased
                                ),
                              ),
                              TextButton(
                                onPressed: _isLoading
                                    ? null
                                    : () => context.push('/register'),
                                child: Text(
                                  context.l10n.authSignUp,
                                  style: const TextStyle(
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
                            context.l10n.loginDataSecure,
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
                context.l10n.loginLockedTitle,
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                context.l10n.biometricPromptDefault,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              CustomButton(
                text: context.l10n.loginUnlockBiometrics,
                onPressed: () async {
                  final destination = _destination();
                  final success = await authProvider.unlockApp(
                    promptReason: context.l10n.biometricLoginPrompt,
                  );
                  if (success && mounted) {
                    context.go(destination);
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
                child: Text(context.l10n.loginLogoutDifferentAccount),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
