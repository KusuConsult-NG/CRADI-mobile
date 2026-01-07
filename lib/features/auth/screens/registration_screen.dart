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
import 'dart:developer' as developer;
import 'package:climate_app/core/services/registration_code_service.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _registrationCodeController =
      TextEditingController();

  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRegistrationCode();
  }

  /// Load or generate registration code on app first open
  Future<void> _loadRegistrationCode() async {
    final regCodeService = RegistrationCodeService();
    final code = await regCodeService.getRegistrationCode();
    setState(() {
      _registrationCodeController.text = code;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _registrationCodeController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authProvider = context.read<AuthProvider>();

      final name = _nameController.text.trim();
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
        registrationCode: _registrationCodeController.text.trim(),
      );

      if (mounted) {
        setState(() => _isLoading = false);

        if (success) {
          // Navigate to dashboard directly
          context.go('/dashboard');
        } else {
          setState(
            () => _errorMessage = 'Registration failed. Please try again.',
          );
        }
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.userMessage;
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = ErrorHandler.getUserMessage(e);
        });
      }
      ErrorHandler.logError(e, context: 'RegistrationScreen._handleRegister');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
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

                  // Error Message
                  if (_errorMessage != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 20),
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

                  // Full Name
                  CustomTextField(
                    label: 'Full Name',
                    controller: _nameController,
                    hint: 'John Doe',
                    prefixIcon: const Icon(Icons.person_outline),
                    validator: (v) => Validators.validateRequired(v, 'Name'),
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
                  const SizedBox(height: 16),

                  // Registration Code
                  CustomTextField(
                    label: 'Registration Code',
                    controller: _registrationCodeController,
                    hint: 'Auto-generated',
                    prefixIcon: const Icon(Icons.verified_user),
                    validator: (v) => v == null || v.isEmpty
                        ? 'Registration code is required'
                        : null,
                    enabled: !_isLoading,
                  ),
                  const SizedBox(height: 12),

                  // Important Notice
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.orange.shade700,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Important: Save this registration code! You will need it to login.',
                            style: GoogleFonts.lexend(
                              color: Colors.orange.shade700,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
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
                    validator: (value) => Validators.validatePassword(value),
                    enabled: !_isLoading,
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
    );
  }

  // Removed _buildLabel and _buildTextField as they are replaced by CustomTextField
}
