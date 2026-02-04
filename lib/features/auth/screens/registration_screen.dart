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
import 'dart:developer' as developer;

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _emailController.dispose();
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

    setState(() => _isLoading = true);

    try {
      final authProvider = context.read<AuthProvider>();

      final name = _nameController.text.trim();
      final address = _addressController.text.trim();
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
        address: address,
      );

      if (mounted) {
        setState(() => _isLoading = false);

        if (success) {
          _showToast('Account created successfully!');
          // Small delay to ensure loading overlay is dismissed before navigation
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            context.go('/dashboard');
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
                                fontSize: 18,
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
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Fill in your details to register as a monitor.',
                        style: GoogleFonts.lexend(
                          fontSize: 16,
                          color: AppColors.textSecondary,
                          height: 1.5,
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Glassmorphic form container
                      GlassCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
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

                            // Address
                            CustomTextField(
                              label: 'Address',
                              controller: _addressController,
                              hint: 'Your full address',
                              prefixIcon: const Icon(
                                Icons.location_on_outlined,
                              ),
                              validator: (v) =>
                                  Validators.validateRequired(v, 'Address'),
                              enabled: !_isLoading,
                            ),
                            const SizedBox(height: 16),

                            // Email
                            CustomTextField(
                              label: 'Email Address',
                              controller: _emailController,
                              hint: 'name@example.com',
                              prefixIcon: const Icon(Icons.email_outlined),
                              keyboardType: TextInputType.emailAddress,
                              validator: Validators.validateEmail,
                              enabled: !_isLoading,
                            ),

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
                              enabled: !_isLoading,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 40),

                      // Register Button
                      CustomButton(
                        text: 'Create Account',
                        onPressed: _isLoading ? null : _handleRegister,
                        isLoading: _isLoading,
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

  // Removed _buildLabel and _buildTextField as they are replaced by CustomTextField
}
