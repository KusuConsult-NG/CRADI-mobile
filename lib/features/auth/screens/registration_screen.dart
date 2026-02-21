import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/shared/widgets/custom_button.dart';
import 'package:climate_app/shared/widgets/custom_text_field.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:climate_app/core/utils/validators.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:fluttertoast/fluttertoast.dart';
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
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_LONG,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
      textColor: Colors.white,
      fontSize: 16.0,
    );
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) {
      return;
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

      final name = _nameController.text.trim();
      final address = _addressController.text.trim();
      final phone = _phoneController.text.trim();

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
        } on Exception catch (e) {
          if (mounted) {
            setState(() => _isLoading = false);
            _showToast('Failed to send SMS: $e', isError: true);
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
        isVerified: widget.isVerified,
        phoneNumber: phone,
      );

      if (mounted) {
        setState(() => _isLoading = false);

        if (success) {
          // If already verified (pre-signup), go straight to dashboard
          if (widget.isVerified) {
            _showToast('Account created!');
            context.go('/dashboard');
            return; // Stop here
          }

          // Show dialog to inform user about verification link
          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: const Text('Verify Your Account'),
                content: Text(
                  'Account created successfully!\n\nA verification link has been sent to $email.\n\nPlease check your email and click the link to activate your account.',
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      context.pop(); // Close dialog
                      context.go(
                        '/verify-access-code',
                      ); // Go to verification screen
                    },
                    child: const Text('Proceed to Verification'),
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
                        'Select your role and location to get started.',
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
                            // Toggle for Email vs Phone Auth
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
                                      onTap: () =>
                                          setState(() => _isPhoneAuth = false),
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
                              'Role & Location',
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
