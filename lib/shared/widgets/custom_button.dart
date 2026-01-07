import 'package:flutter/material.dart';
import 'package:climate_app/core/theme/app_colors.dart';

enum ButtonType { primary, secondary, ghost }

class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final ButtonType type;
  final bool isLoading;
  final IconData? icon;
  final double? width;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? borderColor;

  const CustomButton({
    super.key,
    required this.text,
    this.onPressed,
    this.type = ButtonType.primary,
    this.isLoading = false,
    this.icon,
    this.width,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width ?? double.infinity,
      height: 48,
      child: _buildButton(context),
    );
  }

  Widget _buildButton(BuildContext context) {
    if (isLoading) {
      // Loading state is consistent across button types for now,
      // but could be specialized if needed (e.g. spinner color).
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              type == ButtonType.primary ? Colors.white : AppColors.primaryRed,
            ),
          ),
        ),
      );
    }

    switch (type) {
      case ButtonType.primary:
        return ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: backgroundColor ?? AppColors.primaryRed,
            foregroundColor: foregroundColor ?? Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 0,
          ),
          child: _buildContent(),
        );

      case ButtonType.secondary:
        return OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: foregroundColor ?? AppColors.textPrimary,
            side: BorderSide(color: borderColor ?? AppColors.primaryGrey),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: _buildContent(),
        );

      case ButtonType.ghost:
        return TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: foregroundColor ?? AppColors.primaryRed,
          ),
          child: _buildContent(),
        );
    }
  }

  Widget _buildContent() {
    if (icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [Icon(icon, size: 20), const SizedBox(width: 8), Text(text)],
      );
    }
    return Text(text);
  }
}
