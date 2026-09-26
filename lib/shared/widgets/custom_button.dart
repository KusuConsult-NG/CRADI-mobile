import 'package:flutter/material.dart';
import 'package:climate_app/core/l10n/l10n.dart';
import 'package:climate_app/core/theme/app_colors.dart';

enum ButtonType { primary, secondary, ghost }

class CustomButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final ButtonType type;
  final bool isLoading;
  final IconData? icon;
  final double? width;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? borderColor;
  final double fontSize;

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
    this.fontSize = 16.0,
  });

  @override
  State<CustomButton> createState() => _CustomButtonState();
}

class _CustomButtonState extends State<CustomButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _isPressed ? 0.95 : 1.0,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeInOut,
      child: GestureDetector(
        // Press feedback only: the real button below owns the tap action and
        // the label, so this must not add a second, unlabelled tappable node.
        excludeFromSemantics: true,
        onTapDown: (_) {
          if (widget.onPressed != null && !widget.isLoading) {
            setState(() => _isPressed = true);
          }
        },
        onTapUp: (_) {
          if (widget.onPressed != null && !widget.isLoading) {
            setState(() => _isPressed = false);
          }
        },
        onTapCancel: () {
          if (widget.onPressed != null && !widget.isLoading) {
            setState(() => _isPressed = false);
          }
        },
        // We still need the buttons to intercept the tap and trigger onPressed
        // to keep their internal ripple, so we don't handle onTap here
        child: SizedBox(
          width: widget.width ?? double.infinity,
          height: 48,
          child: _buildButton(context),
        ),
      ),
    );
  }

  Widget _buildButton(BuildContext context) {
    if (widget.isLoading) {
      // The label is replaced by a bare spinner, which a screen reader
      // cannot name. Announce what the button is doing instead, as a live
      // region so the change is spoken when the press starts.
      final l10n = AppLocalizations.of(context);
      return Semantics(
        label: l10n?.commonSubmittingPleaseWait ?? 'Submitting, please wait',
        liveRegion: true,
        excludeSemantics: true,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                widget.type == ButtonType.primary
                    ? Colors.white
                    : AppColors.primaryRed,
              ),
            ),
          ),
        ),
      );
    }

    switch (widget.type) {
      case ButtonType.primary:
        return ElevatedButton(
          onPressed: widget.onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.backgroundColor ?? AppColors.primaryRed,
            foregroundColor: widget.foregroundColor ?? Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 0,
          ),
          child: _buildContent(),
        );

      case ButtonType.secondary:
        return OutlinedButton(
          onPressed: widget.onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: widget.foregroundColor ?? AppColors.textPrimary,
            side: BorderSide(
              color: widget.borderColor ?? AppColors.primaryGrey,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: _buildContent(),
        );

      case ButtonType.ghost:
        return TextButton(
          onPressed: widget.onPressed,
          style: TextButton.styleFrom(
            foregroundColor: widget.foregroundColor ?? AppColors.primaryRed,
          ),
          child: _buildContent(),
        );
    }
  }

  Widget _buildContent() {
    if (widget.icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(widget.icon, size: 20),
          const SizedBox(width: 8),
          Text(
            widget.text,
            style: TextStyle(
              fontSize: widget.fontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }
    return Text(
      widget.text,
      style: TextStyle(fontSize: widget.fontSize, fontWeight: FontWeight.w600),
    );
  }
}
