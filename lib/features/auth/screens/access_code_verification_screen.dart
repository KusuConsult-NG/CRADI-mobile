import 'package:climate_app/core/theme/app_colors.dart';
import 'dart:developer' as developer;
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/profile/providers/profile_provider.dart';
import 'package:climate_app/shared/widgets/custom_button.dart';
import 'package:climate_app/shared/widgets/custom_text_field.dart';
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
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleVerify() async {
    final code = _codeController.text.trim();
    developer.log(
      'Verify button pressed. Code: "$code"',
      name: 'AccessCodeVerificationScreen',
    );

    if (code.isEmpty) {
      Fluttertoast.showToast(
        msg: 'Please enter your access code',
        backgroundColor: Colors.red,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Simulate verification call (replace with actual provider call when available)
      // await context.read<AuthProvider>().verifyAccount(code);

      // For now, consistent with UserProfileScreen, we simulate verification
      // In a real implementation, add verifyAccount(code) to AuthProvider

      // Update: AuthProvider DOES have verifyAccount now (Task 1162)
      await context.read<AuthProvider>().verifyAccount(code);

      if (mounted) {
        Fluttertoast.showToast(
          msg: 'Account verified successfully!',
          backgroundColor: Colors.green,
        );
        // Router will handle redirect to dashboard based on isVerified state
      }
    } on Exception catch (e) {
      if (mounted) {
        Fluttertoast.showToast(
          msg: 'Verification failed: ${e.toString()}',
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
      await context.read<AuthProvider>().resendAccessCode();
      if (mounted) {
        Fluttertoast.showToast(
          msg: 'Access code resent successfully!',
          backgroundColor: Colors.green,
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        Fluttertoast.showToast(
          msg: 'Failed to resend code: ${e.toString()}',
          backgroundColor: Colors.red,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _resending = false);
      }
    }
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
                Icons.verified_user_outlined,
                size: 80,
                color: AppColors.primaryRed,
              ),
              const SizedBox(height: 32),
              Text(
                'Verify Your Account',
                style: GoogleFonts.lexend(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'We have sent an access code to ${email ?? "your email"}.\nPlease enter it below to continue.',
                style: GoogleFonts.lexend(
                  fontSize: 16,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              CustomTextField(
                controller: _codeController,
                label: 'Access Code',
                hint: 'e.g., ABC-123',
                prefixIcon: const Icon(Icons.vpn_key_outlined),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 24),
              CustomButton(
                text: 'Verify Account',
                onPressed: _handleVerify, // Force enabled for debug
                isLoading: _isLoading,
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
                onPressed: () async {
                  setState(() => _isLoading = true);
                  await context.read<AuthProvider>().reloadUserData();
                  if (context.mounted) {
                    setState(() => _isLoading = false);
                  }

                  if (context.mounted) {
                    final auth = context.read<AuthProvider>();
                    showDialog(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Debug Status'),
                        content: Text(
                          'Auth Verified: ${auth.currentUser?.emailVerification}\n'
                          'DB Verified: ${auth.isVerified}\n'
                          'Role: ${auth.userRole}\n'
                          'UID: ${auth.currentUser?.$id}',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c),
                            child: const Text('OK'),
                          ),
                          if (auth.isVerified)
                            TextButton(
                              onPressed: () => context.go('/dashboard'),
                              child: const Text('Force Dashboard'),
                            ),
                        ],
                      ),
                    );
                  }
                },
                child: Text(
                  'Refresh Status (Debug)',
                  style: GoogleFonts.lexend(
                    color: Colors.blue,
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
