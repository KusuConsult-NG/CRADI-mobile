import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/shared/widgets/custom_button.dart';
import 'package:climate_app/shared/widgets/custom_text_field.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:climate_app/core/utils/validators.dart';
import 'package:climate_app/core/utils/input_sanitizer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/shared/widgets/custom_toast.dart';
import 'package:climate_app/core/design/glass_container.dart';
import 'package:climate_app/core/widgets/location_selector_widget.dart';
import 'dart:developer' as developer;

class RegistrationScreen extends StatefulWidget {
  final String? prefilledEmail;
  final bool isVerified;

  const RegistrationScreen({
    super.key,
    this.prefilledEmail,
    this.isVerified = false,
  });

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
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

  static const String _ndpaPolicyVersion = '1.0.0';

  /// Set to false to hide Phone Auth until Termii is configured.
  /// Toggle back to true once TERMII_API_KEY is confirmed in --dart-define.
  static const bool _phoneAuthEnabled = true;
  static const String _ndpaPolicyText = '''
Nigeria Data Protection Act (NDPA) — Data Processing Notice

Your data is processed by EWER Mobile (a CRADI / KusuConsult-NG service) for climate hazard early warning purposes.

• Data collected: name, phone, email, location (state/LGA/ward), hazard reports, and FCM device tokens.
• Purpose: community hazard reporting, peer verification, and emergency alerts.
• Storage: Firebase Cloud Firestore hosted on Google's us-central1 (Iowa, USA) servers.
• US residency: Pursuant to NDPA Article 24, we disclose that your data is transferred to and stored in the United States of America. This transfer is necessary to provide the service. You have the right to withdraw consent at any time by deleting your account.
• Retention: Data is retained for 5 years after your last activity, then anonymised.
• Your rights: access, rectification, erasure, and data portability under the NDPA 2023.

By tapping "I Agree", you consent to these terms and the international transfer of your personal data.''';

  @override
  void initState() {
    super.initState();
    if (widget.prefilledEmail != null) {
      _emailController.text = widget.prefilledEmail!;
    }
  }

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
                  'Data Privacy Notice',
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
                  _ndpaPolicyText,
                  style: GoogleFonts.lexend(fontSize: 13, height: 1.6),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  'Decline',
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
                  'I Agree',
                  style: GoogleFonts.lexend(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// Records the consent in Firestore for NDPA audit trail.
  Future<void> _recordNdpaConsent(String uid) async {
    try {
      await FirebaseFirestore.instance
          .collection('ndpa_consents')
          .doc(uid)
          .set({
            'uid': uid,
            'consentedAt': FieldValue.serverTimestamp(),
            'policyVersion': _ndpaPolicyVersion,
            'dataResidency': 'us-central1',
            'platform': 'mobile',
            'method': 'registration_screen',
          });
      developer.log(
        'NDPA consent recorded for $uid',
        name: 'RegistrationScreen',
      );
    } on Exception catch (e) {
      // Non-fatal: log but don\'t block registration. Retry on next launch.
      developer.log(
        'NDPA consent record failed: $e',
        name: 'RegistrationScreen',
      );
    }
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    // NDPA: Show consent dialog before any data is submitted
    if (!_ndpaConsented) {
      final agreed = await _showNdpaConsentDialog();
      if (!mounted) return;
      if (!agreed) {
        _showToast(
          'You must accept the Data Privacy Notice to register.',
          isError: true,
        );
        return;
      }
      setState(() => _ndpaConsented = true);
    }

    // Additional validation for Dropdowns

    if (_selectedState == null) {
      _showToast('Please select a state', isError: true);
      return;
    }
    if (_selectedLga == null) {
      _showToast('Please select an LGA', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authProvider = context.read<AuthProvider>();

      final name = InputSanitizer.sanitize(_nameController.text.trim());
      final address = InputSanitizer.sanitize(_addressController.text.trim());
      final phone = InputSanitizer.sanitizePhoneNumber(
        _phoneController.text.trim(),
      );

      if (_isPhoneAuth) {
        // Custom Phone Auth Flow
        setState(() => _isLoading = true);
        try {
          final success = await authProvider.sendOtpForPhone(phone);
          if (mounted) {
            setState(() => _isLoading = false);
            if (success) {
              final registrationData = {
                'name': name,
                'address': address,
                'role': UserRole.user,
                'state': _selectedState,
                'lga': _selectedLga,
                'ward': _selectedWard,
                'phone': phone,
              };

              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => AlertDialog(
                  title: const Text('Verify Your Phone Number'),
                  content: Text(
                    'A 6-digit verification code has been sent to $phone.\n\nPlease enter the code to activate your account.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        context.pop(); // Close dialog
                        context.go(
                          '/verify-otp?phone=${Uri.encodeComponent(phone)}',
                          extra: registrationData,
                        );
                      },
                      child: const Text('Enter Code'),
                    ),
                  ],
                ),
              );
            }
          }
        } on AuthException catch (e) {
          if (mounted) {
            setState(() => _isLoading = false);
            _showToast(e.userMessage, isError: true);
          }
        } on Exception catch (e) {
          if (mounted) {
            setState(() => _isLoading = false);
            _showToast(ErrorHandler.getUserMessage(e), isError: true);
          }
        }
        return;
      }

      // Traditional Email Auth Flow
      final email = InputSanitizer.sanitize(_emailController.text.trim());
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
        isVerified: widget.isVerified,
        phoneNumber: phone,
      );

      if (mounted) {
        setState(() => _isLoading = false);

        if (success) {
          // Record NDPA consent in Firestore (uid captured synchronously — safe)
          final uid = context.read<AuthProvider>().currentUser?.uid;
          if (uid != null) await _recordNdpaConsent(uid);
          if (!mounted) return;

          // If already verified (pre-signup), go straight to dashboard
          if (widget.isVerified) {
            _showToast('Account created!');
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
            'email': email
                .trim()
                .toLowerCase(), // normalised to match Firestore doc ID
          };

          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: const Text('Verify Your Email Address'),
                content: Text(
                  'Account created successfully!\n\nA 6-digit verification code has been sent to $email.\n\nPlease enter the code to activate your account.',
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      context.pop(); // Close dialog
                      context.go(
                        '/verify-otp?phone=${Uri.encodeComponent(email)}',
                        extra: registrationData,
                      ); // Go to verification screen
                    },
                    child: const Text('Enter Code'),
                  ),
                ],
              ),
            );
          }
        } else {
          _showToast('Registration failed. Please try again.', isError: true);
        }
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showToast(e.userMessage, isError: true);
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showToast(ErrorHandler.getUserMessage(e), isError: true);
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
                          GestureDetector(
                            onTap: () => context.go('/login'),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.transparent,
                              ),
                              child: const Icon(
                                Icons.arrow_back,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              'Create Account',
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
                        'Join the Network',
                        style: GoogleFonts.lexend(
                          fontSize: 34, // Increased from 30
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Select your location to get started.',
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
                              'Registration Method',
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
                                            'Email',
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
                                            'Phone Number',
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
                              'Personal Information',
                              style: GoogleFonts.lexend(
                                fontSize: 18, // Increased from 16
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Full Name
                            CustomTextField(
                              label: 'Full Name',
                              controller: _nameController,
                              hint: 'John Doe',
                              prefixIcon: const Icon(Icons.person_outline),
                              validator: (v) =>
                                  Validators.validateRequired(v, 'Name'),
                              enabled: !_isLoading,
                            ),
                            const SizedBox(height: 16),

                            // Email (conditional)
                            if (!_isPhoneAuth) ...[
                              CustomTextField(
                                label: 'Email Address',
                                controller: _emailController,
                                hint: 'name@example.com',
                                prefixIcon: const Icon(Icons.email_outlined),
                                keyboardType: TextInputType.emailAddress,
                                validator: Validators.validateEmail,
                                enabled:
                                    !_isLoading &&
                                    widget.prefilledEmail == null,
                              ),
                              const SizedBox(height: 16),
                            ],

                            // Phone Number
                            CustomTextField(
                              label: 'Phone Number',
                              controller: _phoneController,
                              hint: '+234...',
                              prefixIcon: const Icon(Icons.phone_outlined),
                              keyboardType: TextInputType.phone,
                              validator: (v) =>
                                  Validators.validatePhoneNumber(v),
                              enabled: !_isLoading,
                            ),
                            const SizedBox(height: 16),

                            // Address
                            CustomTextField(
                              label: 'Address Description',
                              controller: _addressController,
                              hint: 'e.g., No 5, Main Street',
                              prefixIcon: const Icon(
                                Icons.location_on_outlined,
                              ),
                              validator: (v) =>
                                  Validators.validateRequired(v, 'Address'),
                              enabled: !_isLoading,
                            ),
                            const SizedBox(height: 24),

                            Text(
                              'Location',
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
                                'Security',
                                style: GoogleFonts.lexend(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Password
                              CustomTextField(
                                label: 'Password',
                                controller: _passwordController,
                                hint: 'Create a password',
                                obscureText: !_isPasswordVisible,
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
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
                                    Validators.validatePassword(value),
                                enabled: !_isLoading,
                              ),
                              const SizedBox(height: 16),

                              // Confirm Password
                              CustomTextField(
                                label: 'Confirm Password',
                                controller: _confirmPasswordController,
                                hint: 'Re-enter your password',
                                obscureText: !_isConfirmPasswordVisible,
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
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
                                    return 'Please confirm your password';
                                  }
                                  if (value != _passwordController.text) {
                                    return 'Passwords do not match';
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
                                  ? 'Send OTP & Register'
                                  : 'Create Account',
                              onPressed: _isLoading ? null : _handleRegister,
                              isLoading: _isLoading,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Login Link
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Already have an account? ",
                            style: GoogleFonts.lexend(
                              color: AppColors.textSecondary,
                              fontSize: 16, // Large size
                            ),
                          ),
                          TextButton(
                            onPressed: () => context.go('/login'),
                            child: Text(
                              'Login',
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
                        'Creating account...',
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
