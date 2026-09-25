import 'package:climate_app/core/theme/app_colors.dart';
import 'dart:developer' as developer;
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/profile/providers/profile_provider.dart';
import 'package:climate_app/shared/widgets/custom_button.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:flutter/material.dart';

import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';

class AccessCodeVerificationScreen extends StatefulWidget {
  const AccessCodeVerificationScreen({super.key});

  @override
  State<AccessCodeVerificationScreen> createState() =>
      _AccessCodeVerificationScreenState();
}

class _AccessCodeVerificationScreenState
    extends State<AccessCodeVerificationScreen> {
  bool _isLoading = false;

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _handleVerify() async {
    setState(() => _isLoading = true);

    try {
      await context.read<AuthProvider>().reloadUserData();

      if (!mounted) return;

      final isVerified = context.read<AuthProvider>().isVerified;

      if (isVerified) {
        Fluttertoast.showToast(
          msg: 'Account verified successfully!',
          backgroundColor: Colors.green,
        );
        context.go('/dashboard');
      } else {
        Fluttertoast.showToast(
          msg: 'Not verified yet. Please enter the code sent to your email.',
          backgroundColor: Colors.orange,
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        Fluttertoast.showToast(msg: e.userMessage, backgroundColor: Colors.red);
      }
    } on Exception catch (e) {
      if (mounted) {
        Fluttertoast.showToast(
          msg: ErrorHandler.getUserMessage(e),
          backgroundColor: Colors.red,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool _resending = false;

  Future<void> _handleResend() async {
    if (_resending) return;

    setState(() => _resending = true);
    try {
      await context.read<AuthProvider>().resendVerificationLink();
      if (mounted) {
        Fluttertoast.showToast(
          msg: 'Verification code sent!',
          backgroundColor: Colors.green,
        );
        _openCodeEntry();
      }
    } on AuthException catch (e) {
      if (mounted) {
        Fluttertoast.showToast(msg: e.userMessage, backgroundColor: Colors.red);
      }
    } on Exception catch (e) {
      if (mounted) {
        Fluttertoast.showToast(
          msg: ErrorHandler.getUserMessage(e),
          backgroundColor: Colors.red,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _resending = false);
      }
    }
  }

  /// Open the OTP entry screen for the signed-in user's email. It verifies
  /// the code via AuthProvider.verifyOtpAndLogin and goes to /dashboard.
  void _openCodeEntry() {
    final email = context.read<AuthProvider>().currentUser?.email;
    if (email == null || email.isEmpty) {
      Fluttertoast.showToast(
        msg: 'No email found for this account. Please log in again.',
        backgroundColor: Colors.red,
      );
      return;
    }
    context.push('/verify-otp?phone=${Uri.encodeComponent(email)}');
  }

  Future<void> _handleLogout() async {
    try {
      context.read<ProfileProvider>().clearProfile();
      await context.read<AuthProvider>().logout();
      if (mounted) {
        context.go('/login');
      }
    } on Exception catch (e) {
      ErrorHandler.logError(e, context: 'AccessCodeVerificationScreen.logout');
      if (mounted) {
        context.go('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = context.select<AuthProvider, String?>(
      (p) => p.currentUser?.email,
    );
    developer.log(
      'Building Verification Screen. isLoading: $_isLoading, resending: $_resending',
      name: 'AccessCodeVerificationScreen',
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.mark_email_unread_outlined,
                size: 80,
                color: AppColors.primaryRed,
              ),
              const SizedBox(height: 32),
              Text(
                'Verify Your Email',
                style: GoogleFonts.lexend(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'We have sent a 6-digit verification code to ${email ?? "your email"}.\nEnter the code to activate your account.',
                style: GoogleFonts.lexend(
                  fontSize: 16,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              CustomButton(text: 'Enter Code', onPressed: _openCodeEntry),
              const SizedBox(height: 16),
              CustomButton(
                text: 'I have verified my account',
                onPressed: _handleVerify, // Force enabled for debug
                isLoading: _isLoading,
                type: ButtonType.secondary,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _handleResend, // Force enabled for debug
                child: _resending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        'Resend Code',
                        style: GoogleFonts.lexend(
                          color: AppColors.primaryRed,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
              const SizedBox(height: 8),

              TextButton(
                onPressed: _handleLogout, // Force enabled for debug
                child: Text(
                  'Logout',
                  style: GoogleFonts.lexend(
                    color: AppColors.primaryRed,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
