import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/shared/widgets/custom_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/core/utils/validators.dart';
import 'package:climate_app/core/l10n/l10n.dart';
import 'package:climate_app/core/utils/screen_security.dart';

/// Password reset screen, in either of the two shapes a recovery mail allows.
///
/// **Typed code** ([hasRecoverySession] false): Supabase emails a recovery
/// code (see [ForgotPasswordScreen]); the user enters it with a new password
/// and [AuthProvider.confirmPasswordReset] completes the reset. A new code can
/// be requested from here.
///
/// **Opened link** ([hasRecoverySession] true): the same mail's link opens the
/// app and `supabase_flutter` establishes a recovery session from it, so the
/// email and code fields have nothing left to ask — only the new password,
/// which [AuthProvider.completePasswordRecovery] applies. The router parks the
/// app here for as long as that session is unresolved.
class ResetPasswordScreen extends StatefulWidget {
  /// Pre-filled email address (from the forgot-password step).
  final String email;

  /// True when a recovery link already signed the user in, so there is no
  /// code to collect.
  final bool hasRecoverySession;

  const ResetPasswordScreen({
    super.key,
    this.email = '',
    this.hasRecoverySession = false,
  });

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen>
    with ScreenSecurityMixin<ResetPasswordScreen> {
  late final TextEditingController _emailController = TextEditingController(
    text: widget.email,
  );
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isSendingCode = false;
  bool _isSuccess = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return context.l10n.authEmailRequired;
    }
    if (!value.contains('@')) return context.l10n.authEmailInvalid;
    return null;
  }

  Future<void> _sendCode() async {
    final emailError = _validateEmail(_emailController.text);
    if (emailError != null) {
      CustomToast.showError(context, emailError);
      return;
    }
    setState(() => _isSendingCode = true);
    try {
      await context.read<AuthProvider>().sendPasswordResetEmail(
        _emailController.text.trim(),
      );
      if (mounted) {
        CustomToast.showSuccess(context, context.l10n.resetCodeResent);
      }
    } on AuthException catch (e) {
      if (mounted) CustomToast.showError(context, e.userMessage(context.l10n));
    } on Exception catch (e) {
      if (mounted) {
        CustomToast.showError(
          context,
          ErrorHandler.handleError(e, context.l10n, context: 'Password Reset'),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingCode = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      CustomToast.showError(
        context,
        context.l10n.registrationPasswordsMismatch,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final auth = context.read<AuthProvider>();
      if (widget.hasRecoverySession) {
        await auth.completePasswordRecovery(_passwordController.text);
      } else {
        await auth.confirmPasswordReset(
          email: _emailController.text.trim(),
          code: _codeController.text.trim(),
          newPassword: _passwordController.text,
        );
      }
      if (mounted) {
        setState(() {
          _isSuccess = true;
          _isLoading = false;
        });
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        CustomToast.showError(context, e.userMessage(context.l10n));
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        CustomToast.showError(
          context,
          ErrorHandler.handleError(e, context.l10n, context: 'Password Reset'),
        );
      }
    }
  }

  InputDecoration _decoration(String label, IconData icon, {Widget? suffix}) =>
      InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        prefixIcon: Icon(icon),
        suffixIcon: suffix,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: context.l10n.close,
          icon: const Icon(Icons.close, color: Colors.black),
          // Leaving with a recovery session still open would bounce straight
          // back here (the router parks on this screen while it holds), so
          // the session is dropped first.
          onPressed: () async {
            if (widget.hasRecoverySession && !_isSuccess) {
              await context.read<AuthProvider>().cancelPasswordRecovery();
            }
            if (context.mounted) context.go('/login');
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: _isSuccess ? _buildSuccessView() : _buildFormView(),
        ),
      ),
    );
  }

  Widget _buildFormView() {
    return Form(
      key: _formKey,
      child: ListView(
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primaryRed.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_reset,
                size: 40,
                color: AppColors.primaryRed,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            context.l10n.resetTitle,
            style: GoogleFonts.lexend(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            widget.hasRecoverySession
                ? context.l10n.resetRecoveryBody
                : context.l10n.resetBody,
            style: GoogleFonts.lexend(
              fontSize: 16,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          if (!widget.hasRecoverySession) ...[
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: _decoration(
                context.l10n.emailAddress,
                Icons.email_outlined,
              ),
              validator: _validateEmail,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _codeController,
              // Not digits-only. Supabase mails six digits, but Appwrite's
              // server-minted token is six *alphanumeric* characters —
              // `9592e8`. A numeric keypad plus `digitsOnly` meant the
              // code could not be typed at all, and a pasted one was
              // silently stripped to nothing. Digits remain a subset, so
              // this is correct on either backend.
              keyboardType: TextInputType.visiblePassword,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                LengthLimitingTextInputFormatter(10),
              ],
              decoration: _decoration(
                context.l10n.resetCodeLabel,
                Icons.pin_outlined,
                suffix: TextButton(
                  onPressed: _isSendingCode ? null : _sendCode,
                  child: Text(
                    _isSendingCode
                        ? context.l10n.resetSendingCode
                        : context.l10n.resetSendCode,
                  ),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().length < 6) {
                  return context.l10n.resetCodeRequired;
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
          ],
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: _decoration(
              context.l10n.resetNewPassword,
              Icons.lock_outline,
              suffix: IconButton(
                tooltip: _obscurePassword
                    ? context.l10n.authShowPassword
                    : context.l10n.authHidePassword,
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            // Same rules as registration, checked before the single-use
            // recovery code is spent.
            validator: (v) => Validators.validatePassword(v, context.l10n),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: _obscurePassword,
            decoration: _decoration(
              context.l10n.registrationConfirmPassword,
              Icons.lock_outline,
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return context.l10n.registrationConfirmPasswordRequired;
              }
              return null;
            },
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _isLoading ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    context.l10n.resetSubmit,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSuccessView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.successGreen.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_outline,
            size: 60,
            color: AppColors.successGreen,
          ),
        ),
        const SizedBox(height: 32),
        Text(
          context.l10n.resetSuccessTitle,
          style: GoogleFonts.lexend(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          context.l10n.resetSuccessBody,
          style: GoogleFonts.lexend(
            fontSize: 16,
            color: Colors.grey.shade600,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 48),
        ElevatedButton(
          onPressed: () => context.go('/login'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryRed,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            context.l10n.resetContinueToLogin,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
