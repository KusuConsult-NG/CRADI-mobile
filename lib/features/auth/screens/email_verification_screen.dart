import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/shared/widgets/custom_button.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'dart:developer' as developer;

class EmailVerificationScreen extends StatefulWidget {
  final String userId;
  final String secret;

  const EmailVerificationScreen({
    super.key,
    required this.userId,
    required this.secret,
  });

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  bool _isProcessing = true;
  bool _isVerified = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _verifyEmail();
  }

  Future<void> _verifyEmail() async {
    try {
      if (widget.userId.isEmpty || widget.secret.isEmpty) {
        throw Exception('Invalid verification link.');
      }

      await context.read<AuthProvider>().verifyEmail(
        widget.userId,
        widget.secret,
      );

      if (mounted) {
        setState(() {
          _isProcessing = false;
          _isVerified = true;
        });
      }
    } on Exception catch (e) {
      developer.log('Verification Error: $e', name: 'EmailVerificationScreen');
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _isVerified = false;
          _errorMessage = e
              .toString()
              .replaceAll('Exception: ', '')
              .replaceAll('AuthException: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isProcessing) ...[
                const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.primaryRed,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'Verifying your email...',
                  style: GoogleFonts.lexend(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ] else if (_isVerified) ...[
                const Icon(
                  Icons.check_circle_outline,
                  size: 80,
                  color: AppColors.successGreen,
                ),
                const SizedBox(height: 32),
                Text(
                  'Verification Successful!',
                  style: GoogleFonts.lexend(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Your account has been verified successfully. You can now access all features.',
                  style: GoogleFonts.lexend(
                    fontSize: 16,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                CustomButton(
                  text: 'Continue to Dashboard',
                  onPressed: () {
                    context.go('/dashboard');
                  },
                ),
              ] else ...[
                const Icon(
                  Icons.error_outline,
                  size: 80,
                  color: AppColors.primaryRed,
                ),
                const SizedBox(height: 32),
                Text(
                  'Verification Failed',
                  style: GoogleFonts.lexend(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  _errorMessage,
                  style: GoogleFonts.lexend(
                    fontSize: 16,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                CustomButton(
                  text: 'Back to Login',
                  onPressed: () {
                    context.read<AuthProvider>().logout();
                    context.go('/login');
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
