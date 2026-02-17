import 'dart:math';
import 'package:climate_app/core/services/email_service.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/core/utils/validators.dart';
import 'package:climate_app/shared/widgets/custom_button.dart';
import 'package:climate_app/shared/widgets/custom_text_field.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class PreSignupVerificationScreen extends StatefulWidget {
  const PreSignupVerificationScreen({super.key});

  @override
  State<PreSignupVerificationScreen> createState() =>
      _PreSignupVerificationScreenState();
}

class _PreSignupVerificationScreenState
    extends State<PreSignupVerificationScreen> {
  final TextEditingController _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleInitialVerification() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final email = _emailController.text.trim();

    // 1. Generate 6-digit code
    final code = (Random().nextInt(900000) + 100000).toString();

    // 2. Send Email
    try {
      final success = await EmailService().sendVerificationCode(email, code);

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (success) {
        // 3. Navigate to OTP Screen
        context.push(
          '/signup-otp',
          extra: {
            'email': email,
            'code':
                code, // In prod, do not pass code in routes, verify on server
          },
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Failed to send verification email. Please try again.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Verify Account'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(onPressed: () => context.go('/landing')),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Let\'s get you started',
                  style: GoogleFonts.lexend(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Enter your email address to receive a verification code.',
                  style: GoogleFonts.lexend(
                    fontSize: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 32),
                CustomTextField(
                  controller: _emailController,
                  label: 'Email Address',
                  hint: 'name@example.com',
                  prefixIcon: const Icon(Icons.email_outlined),
                  keyboardType: TextInputType.emailAddress,
                  validator: Validators.validateEmail,
                ),
                const SizedBox(height: 24),
                CustomButton(
                  text: 'Send Code',
                  onPressed: _isLoading ? null : _handleInitialVerification,
                  isLoading: _isLoading,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
