import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/shared/widgets/custom_button.dart';
import 'package:climate_app/shared/widgets/custom_text_field.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'dart:async';
import 'dart:developer' as developer;
import 'package:climate_app/core/l10n/l10n.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String phoneNumber;
  final Map<String, dynamic>? registrationData;

  const OtpVerificationScreen({
    super.key,
    required this.phoneNumber,
    this.registrationData,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final TextEditingController _otpController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isResending = false;
  int _resendSeconds = 60;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  void _startResendTimer() {
    _resendSeconds = 60;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendSeconds > 0) {
        if (mounted) setState(() => _resendSeconds--);
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _otpController.dispose();
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

  Future<void> _handleVerify() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authProvider = context.read<AuthProvider>();

      final dataParams =
          widget.registrationData ??
          (widget.phoneNumber.contains('@')
              ? {'email': widget.phoneNumber}
              : {'phone': widget.phoneNumber});

      final success = await authProvider.verifyOtpAndLogin(
        _otpController.text.trim(),
        registrationData: dataParams,
      );

      if (mounted) {
        setState(() => _isLoading = false);
        if (success) {
          _showToast(context.l10n.otpSuccess);
          context.go('/dashboard');
        }
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showToast(ErrorHandler.getUserMessage(e, context.l10n), isError: true);
      }
      developer.log(
        'OTP Verification Error: $e',
        name: 'OtpVerificationScreen',
      );
    }
  }

  Future<void> _handleResend() async {
    setState(() => _isResending = true);
    try {
      final authProvider = context.read<AuthProvider>();

      bool success = false;
      if (widget.phoneNumber.contains('@')) {
        success = await authProvider.sendOtpForEmail(widget.phoneNumber);
      } else {
        success = await authProvider.sendOtpForPhone(widget.phoneNumber);
      }

      if (mounted) {
        setState(() => _isResending = false);
        if (success) {
          _showToast(context.l10n.otpNewCodeSent);
          _startResendTimer();
        }
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _isResending = false);
        _showToast(ErrorHandler.getUserMessage(e, context.l10n), isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/login');
            }
          },
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                const Icon(
                  Icons.textsms_outlined,
                  size: 80,
                  color: AppColors.primaryRed,
                ),
                const SizedBox(height: 32),
                Text(
                  widget.phoneNumber.contains('@')
                      ? context.l10n.otpVerifyEmail
                      : context.l10n.verifyPhoneNumber,
                  style: GoogleFonts.lexend(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  context.l10n.otpCodeSentTo(widget.phoneNumber),
                  style: GoogleFonts.lexend(
                    fontSize: 16,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                CustomTextField(
                  label: context.l10n.otpSecureCode,
                  controller: _otpController,
                  hint: context.l10n.otpCodeHint,
                  keyboardType: TextInputType.number,
                  prefixIcon: const Icon(Icons.password),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return context.l10n.otpCodeRequired;
                    }
                    if (value.length < 4) {
                      return context.l10n.otpCodeInvalidFormat;
                    }
                    return null;
                  },
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 32),
                CustomButton(
                  text: context.l10n.otpVerifyAndLogin,
                  onPressed: _isLoading ? null : _handleVerify,
                  isLoading: _isLoading,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      context.l10n.otpNoCode,
                      style: GoogleFonts.lexend(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                    TextButton(
                      onPressed:
                          _isResending || _isLoading || _resendSeconds > 0
                          ? null
                          : _handleResend,
                      child: _isResending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primaryRed,
                              ),
                            )
                          : Text(
                              _resendSeconds > 0
                                  ? context.l10n.otpResendIn(_resendSeconds)
                                  : context.l10n.resendCode,
                              style: GoogleFonts.lexend(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: _resendSeconds > 0
                                    ? AppColors.textSecondary
                                    : AppColors.primaryRed,
                              ),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
