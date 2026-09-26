import 'package:climate_app/core/constants/privacy_notice.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/shared/widgets/custom_button.dart';
import 'package:climate_app/shared/widgets/custom_text_field.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:climate_app/core/utils/validators.dart';
import 'package:climate_app/core/utils/input_sanitizer.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/shared/widgets/custom_toast.dart';
import 'package:climate_app/core/design/glass_container.dart';
import 'package:climate_app/core/widgets/location_selector_widget.dart';
import 'dart:developer' as developer;
import 'package:climate_app/core/l10n/l10n.dart';
import 'package:climate_app/core/utils/screen_security.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen>
    with ScreenSecurityMixin<RegistrationScreen> {
  // Form Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  // Selection State

  String? _selectedState;
  String? _selectedLga;
  String? _selectedWard;

  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isPhoneAuth = false;
  bool _ndpaConsented = false;

  static const String _ndpaPolicyVersion = kNdpaPolicyVersion;

  /// Phone Auth stays hidden until an SMS provider is configured for phone
  /// OTP in the Supabase dashboard (shared with the login screen).
  static const bool _phoneAuthEnabled = AuthProvider.phoneAuthEnabled;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showToast(String message, {bool isError = false}) {
    if (isError) {
      CustomToast.showError(context, message);
    } else {
      CustomToast.showSuccess(context, message);
    }
  }

  /// Shows the full NDPA consent dialog. Returns true if user agrees.
  Future<bool> _showNdpaConsentDialog() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                const Icon(
                  Icons.privacy_tip_outlined,
                  color: AppColors.primaryRed,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  context.l10n.registrationPrivacyTitle,
                  style: GoogleFonts.lexend(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Text(
                  context.l10n.privacyNoticeText,
                  style: GoogleFonts.lexend(fontSize: 13, height: 1.6),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  context.l10n.registrationDecline,
                  style: GoogleFonts.lexend(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryRed,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  context.l10n.registrationAgree,
                  style: GoogleFonts.lexend(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    // NDPA: Show consent dialog before any data is submitted
    if (!_ndpaConsented) {
      final agreed = await _showNdpaConsentDialog();
      if (!mounted) return;
      if (!agreed) {
        _showToast(context.l10n.registrationMustAccept, isError: true);
        return;
      }
      setState(() => _ndpaConsented = true);
    }

    // Additional validation for Dropdowns

    if (_selectedState == null) {
      _showToast(context.l10n.registrationSelectState, isError: true);
      return;
    }
    if (_selectedLga == null) {
      _showToast(context.l10n.registrationSelectLga, isError: true);
      return;
    }
    if (_selectedWard == null || _selectedWard!.trim().isEmpty) {
      _showToast(context.l10n.registrationSelectWard, isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authProvider = context.read<AuthProvider>();

      // Stored as typed: trimmed, whitespace/control characters normalised,
      // never HTML-escaped (escaping turned "O'Brien" into "O&#x27;Brien").
      final name = InputSanitizer.cleanForStorage(_nameController.text);
      final address = InputSanitizer.cleanForStorage(_addressController.text);
      final phone = InputSanitizer.sanitizePhoneNumber(
        _phoneController.text.trim(),
      );

      if (_isPhoneAuth) {
        // Custom Phone Auth Flow
        setState(() => _isLoading = true);
        try {
          final registrationData = <String, dynamic>{
            'name': name,
            'address': address,
            'role': UserRole.user,
            'state': _selectedState,
            'lga': _selectedLga,
            'ward': _selectedWard,
            'phone': phone,
            'ndpaPolicyVersion': _ndpaPolicyVersion,
          };
          final success = await authProvider.sendOtpForPhone(
            phone,
            registrationData: registrationData,
          );
          if (mounted) {
            setState(() => _isLoading = false);
            if (success) {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (dialogContext) => AlertDialog(
                  title: Text(context.l10n.registrationVerifyPhoneTitle),
                  content: Text(context.l10n.registrationPhoneCodeSent(phone)),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(dialogContext).pop(); // Close dialog
                        // The screen's context: the dialog's is gone now.
                        context.push(
                          '/verify-otp?phone=${Uri.encodeComponent(phone)}',
                          extra: registrationData,
                        );
                      },
                      child: Text(context.l10n.accessCodeEnterCode),
                    ),
                  ],
                ),
              );
            }
          }
        } on AuthException catch (e) {
          if (mounted) {
            setState(() => _isLoading = false);
            _showToast(e.userMessage(context.l10n), isError: true);
          }
        } on Exception catch (e) {
          if (mounted) {
            setState(() => _isLoading = false);
            _showToast(
              ErrorHandler.getUserMessage(e, context.l10n),
              isError: true,
            );
          }
        }
        return;
      }

      // Traditional Email Auth Flow
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      developer.log(
        'Registration attempt: email=$email',
        name: 'RegistrationScreen',
      );

      final success = await authProvider.signUpWithEmail(
        email: email,
        password: password,
        name: name,
        address: address, // Physical address description
        role: UserRole.user,
        state: _selectedState, // Pass selected state
        lga: _selectedLga, // Pass selected LGA
        ward: _selectedWard, // Pass selected Ward
        phoneNumber: phone,
        // Recorded in ndpa_consents once the account has a session.
        ndpaPolicyVersion: _ndpaPolicyVersion,
      );

      if (mounted) {
        setState(() => _isLoading = false);

        if (success) {
          // Email confirmation disabled in Supabase → already signed in.
          if (context.read<AuthProvider>().isAuthenticated) {
            _showToast(context.l10n.registrationAccountCreated);
            context.go('/dashboard');
            return; // Stop here
          }

          // Registration flow ends here. User will verify via OTP.
          final registrationData = {
            'name': name,
            'address': address,
            'role': UserRole.user,
            'state': _selectedState,
            'lga': _selectedLga,
            'ward': _selectedWard,
            'email': email.trim().toLowerCase(),
          };

          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (dialogContext) => AlertDialog(
                title: Text(context.l10n.registrationVerifyEmailTitle),
                content: Text(context.l10n.registrationEmailCodeSent(email)),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop(); // Close dialog
                      // The screen's context: the dialog's is gone now.
                      context.push(
                        '/verify-otp?phone=${Uri.encodeComponent(email)}',
                        extra: registrationData,
                      ); // Go to verification screen
                    },
                    child: Text(context.l10n.accessCodeEnterCode),
                  ),
                ],
              ),
            );
          }
        } else {
          _showToast(context.l10n.authErrorRegistrationFailed, isError: true);
        }
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showToast(e.userMessage(context.l10n), isError: true);
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showToast(ErrorHandler.getUserMessage(e, context.l10n), isError: true);
      }
      ErrorHandler.logError(e, context: 'RegistrationScreen._handleRegister');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
                        children: [
                          Semantics(
                            button: true,
                            label: context.l10n.back,
                            child: Tooltip(
                              message: context.l10n.back,
                              child: GestureDetector(
                                onTap: () => context.go('/login'),
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.transparent,
                                  ),
                                  child: const ExcludeSemantics(
                                    child: Icon(
                                      Icons.arrow_back,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              context.l10n.registrationCreateAccount,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.lexend(
                                fontSize: 20, // Increased from 18
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 40),
                        ],
                      ),

                      const SizedBox(height: 32),

                      // Title
                      Text(
                        context.l10n.registrationJoinNetwork,
                        style: GoogleFonts.lexend(
                          fontSize: 34, // Increased from 30
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        context.l10n.registrationSelectLocation,
                        style: GoogleFonts.lexend(
                          fontSize: 18, // Increased from 16
                          color: AppColors.textSecondary,
                          height: 1.5,
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Glassmorphic form container
                      GlassCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10n.registrationMethod,
                              style: GoogleFonts.lexend(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Toggle for Email vs Phone Auth — only shown when phone auth is enabled
                            if (_phoneAuthEnabled)
                              Container(
                                height: 48,
                                decoration: BoxDecoration(
                                  color: Colors.grey.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => setState(
                                          () => _isPhoneAuth = false,
                                        ),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: !_isPhoneAuth
                                                ? AppColors.primaryRed
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            context.l10n.authMethodEmail,
                                            style: GoogleFonts.lexend(
                                              color: !_isPhoneAuth
                                                  ? Colors.white
                                                  : AppColors.textSecondary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () =>
                                            setState(() => _isPhoneAuth = true),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: _isPhoneAuth
                                                ? AppColors.primaryRed
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            context.l10n.authPhoneNumber,
                                            style: GoogleFonts.lexend(
                                              color: _isPhoneAuth
                                                  ? Colors.white
                                                  : AppColors.textSecondary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 24),
                            Text(
                              context.l10n.registrationPersonalInfo,
                              style: GoogleFonts.lexend(
                                fontSize: 18, // Increased from 16
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Full Name
                            CustomTextField(
                              label: context.l10n.fullName,
                              controller: _nameController,
                              hint: context.l10n.registrationNameHint,
                              prefixIcon: const Icon(Icons.person_outline),
                              validator: (v) => Validators.validateRequired(
                                v?.trim(),
                                context.l10n.registrationNameField,
                                context.l10n,
                              ),
                              enabled: !_isLoading,
                            ),
                            const SizedBox(height: 16),

                            // Email (conditional)
                            if (!_isPhoneAuth) ...[
                              CustomTextField(
                                label: context.l10n.emailAddress,
                                controller: _emailController,
                                hint: 'name@example.com',
                                prefixIcon: const Icon(Icons.email_outlined),
                                keyboardType: TextInputType.emailAddress,
                                validator: (v) => Validators.validateEmail(
                                  v?.trim(),
                                  context.l10n,
                                ),
                                enabled: !_isLoading,
                              ),
                              const SizedBox(height: 16),
                            ],

                            // Phone Number
                            CustomTextField(
                              label: context.l10n.authPhoneNumber,
                              controller: _phoneController,
                              hint: '+234...',
                              prefixIcon: const Icon(Icons.phone_outlined),
                              keyboardType: TextInputType.phone,
                              validator: (v) => Validators.validatePhoneNumber(
                                v,
                                context.l10n,
                              ),
                              enabled: !_isLoading,
                            ),
                            const SizedBox(height: 16),

                            // Address
                            CustomTextField(
                              label: context.l10n.registrationAddressLabel,
                              controller: _addressController,
                              hint: context.l10n.registrationAddressHint,
                              prefixIcon: const Icon(
                                Icons.location_on_outlined,
                              ),
                              validator: (v) => Validators.validateRequired(
                                v?.trim(),
                                context.l10n.registrationAddressField,
                                context.l10n,
                              ),
                              enabled: !_isLoading,
                            ),
                            const SizedBox(height: 24),

                            Text(
                              context.l10n.locationLabel,
                              style: GoogleFonts.lexend(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Location Selector
                            LocationSelectorWidget(
                              initialState: _selectedState,
                              initialLGA: _selectedLga,
                              initialWard: _selectedWard,
                              required: true,
                              onLocationChanged: (state, lga, ward) {
                                setState(() {
                                  _selectedState = state;
                                  _selectedLga = lga;
                                  _selectedWard = ward;
                                });
                              },
                            ),

                            const SizedBox(height: 24),

                            if (!_isPhoneAuth) ...[
                              Text(
                                context.l10n.registrationSecurity,
                                style: GoogleFonts.lexend(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Password
                              CustomTextField(
                                label: context.l10n.authPassword,
                                controller: _passwordController,
                                hint: context.l10n.registrationPasswordHint,
                                obscureText: !_isPasswordVisible,
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  tooltip: _isPasswordVisible
                                      ? context.l10n.authHidePassword
                                      : context.l10n.authShowPassword,
                                  icon: Icon(
                                    _isPasswordVisible
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                    color: AppColors.textSecondary,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _isPasswordVisible = !_isPasswordVisible;
                                    });
                                  },
                                ),
                                validator: (value) =>
                                    Validators.validatePassword(
                                      value,
                                      context.l10n,
                                    ),
                                enabled: !_isLoading,
                              ),
                              const SizedBox(height: 16),

                              // Confirm Password
                              CustomTextField(
                                label: context.l10n.registrationConfirmPassword,
                                controller: _confirmPasswordController,
                                hint: context
                                    .l10n
                                    .registrationConfirmPasswordHint,
                                obscureText: !_isConfirmPasswordVisible,
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  tooltip: _isConfirmPasswordVisible
                                      ? context.l10n.authHidePassword
                                      : context.l10n.authShowPassword,
                                  icon: Icon(
                                    _isConfirmPasswordVisible
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                    color: AppColors.textSecondary,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _isConfirmPasswordVisible =
                                          !_isConfirmPasswordVisible;
                                    });
                                  },
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return context
                                        .l10n
                                        .registrationConfirmPasswordRequired;
                                  }
                                  if (value != _passwordController.text) {
                                    return context
                                        .l10n
                                        .registrationPasswordsMismatch;
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 40),
                            ] else ...[
                              const SizedBox(height: 24),
                            ],

                            // Register Button
                            CustomButton(
                              text: _isPhoneAuth
                                  ? context.l10n.registrationSendOtp
                                  : context.l10n.registrationCreateAccount,
                              onPressed: _isLoading ? null : _handleRegister,
                              isLoading: _isLoading,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Login Link (wraps instead of overflowing)
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            context.l10n.registrationHaveAccount,
                            style: GoogleFonts.lexend(
                              color: AppColors.textSecondary,
                              fontSize: 16, // Large size
                            ),
                          ),
                          TextButton(
                            onPressed: () => context.go('/login'),
                            child: Text(
                              context.l10n.authLogin,
                              style: GoogleFonts.lexend(
                                fontSize: 18, // Large bold size
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryRed,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Loading Overlay
          if (_isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.5),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.gradientStart,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        context.l10n.registrationCreating,
                        style: GoogleFonts.lexend(
                          fontSize: 16,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
