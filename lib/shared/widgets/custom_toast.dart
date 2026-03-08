import 'package:flutter/material.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';

enum ToastType { success, error, warning, info }

class CustomToast {
  static void show(
    BuildContext context, {
    required String message,
    ToastType type = ToastType.info,
    Duration duration = const Duration(seconds: 4),
  }) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.hideCurrentSnackBar();

    Color backgroundColor;
    IconData icon;
    Color iconColor;

    switch (type) {
      case ToastType.success:
        backgroundColor = const Color(0xFFE8F5E9); // Light Green
        iconColor = AppColors.successGreen;
        icon = Icons.check_circle_outline;
        break;
      case ToastType.error:
        backgroundColor = const Color(0xFFFFEBEE); // Light Red
        iconColor = AppColors.errorRed;
        icon = Icons.error_outline;
        break;
      case ToastType.warning:
        backgroundColor = const Color(0xFFFFF8E1); // Light Amber
        iconColor = AppColors.warningYellow;
        icon = Icons.warning_amber_rounded;
        break;
      case ToastType.info:
        backgroundColor = const Color(0xFFE3F2FD); // Light Blue
        iconColor = Colors.blueAccent;
        icon = Icons.info_outline;
        break;
    }

    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: iconColor.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
            border: Border.all(
              color: iconColor.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.lexend(
                    color: Colors.black87,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        duration: duration,
        animation: CurvedAnimation(
          parent: const AlwaysStoppedAnimation(1),
          curve: Curves.easeOutBack,
        ),
      ),
    );
  }

  static void showSuccess(BuildContext context, String message) {
    show(context, message: message, type: ToastType.success);
  }

  static void showError(BuildContext context, String message) {
    show(context, message: message, type: ToastType.error);
  }

  static void showWarning(BuildContext context, String message) {
    show(context, message: message, type: ToastType.warning);
  }

  static void showInfo(BuildContext context, String message) {
    show(context, message: message, type: ToastType.info);
  }
}
