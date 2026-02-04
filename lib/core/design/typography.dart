import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Premium typography system for 2026 design
/// Uses Google Fonts: Outfit for headings, Inter for body
class PremiumTypography {
  // Headings - Outfit Bold
  static TextStyle heading1(BuildContext context, {Color? color}) {
    return GoogleFonts.outfit(
      fontSize: 32,
      fontWeight: FontWeight.bold,
      height: 1.2,
      letterSpacing: -0.5,
      color: color ?? Theme.of(context).textTheme.headlineLarge?.color,
    );
  }

  static TextStyle heading2(BuildContext context, {Color? color}) {
    return GoogleFonts.outfit(
      fontSize: 28,
      fontWeight: FontWeight.bold,
      height: 1.3,
      letterSpacing: -0.3,
      color: color ?? Theme.of(context).textTheme.headlineMedium?.color,
    );
  }

  static TextStyle heading3(BuildContext context, {Color? color}) {
    return GoogleFonts.outfit(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      height: 1.3,
      letterSpacing: -0.2,
      color: color ?? Theme.of(context).textTheme.headlineSmall?.color,
    );
  }

  static TextStyle heading4(BuildContext context, {Color? color}) {
    return GoogleFonts.outfit(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      height: 1.4,
      color: color ?? Theme.of(context).textTheme.titleLarge?.color,
    );
  }

  // Body - Inter
  static TextStyle bodyLarge(BuildContext context, {Color? color}) {
    return GoogleFonts.inter(
      fontSize: 16,
      fontWeight: FontWeight.normal,
      height: 1.6,
      color: color ?? Theme.of(context).textTheme.bodyLarge?.color,
    );
  }

  static TextStyle bodyMedium(BuildContext context, {Color? color}) {
    return GoogleFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.normal,
      height: 1.6,
      color: color ?? Theme.of(context).textTheme.bodyMedium?.color,
    );
  }

  static TextStyle bodySmall(BuildContext context, {Color? color}) {
    return GoogleFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.normal,
      height: 1.5,
      color: color ?? Theme.of(context).textTheme.bodySmall?.color,
    );
  }

  // Labels & Buttons - Inter SemiBold
  static TextStyle button(BuildContext context, {Color? color}) {
    return GoogleFonts.inter(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
      color: color ?? Colors.white,
    );
  }

  static TextStyle label(BuildContext context, {Color? color}) {
    return GoogleFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.3,
      color: color ?? Theme.of(context).textTheme.labelLarge?.color,
    );
  }

  static TextStyle caption(BuildContext context, {Color? color}) {
    return GoogleFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.2,
      color:
          color ??
          Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
    );
  }

  // Subtitle with medium weight
  static TextStyle subtitle(BuildContext context, {Color? color}) {
    return GoogleFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      height: 1.5,
      color:
          color ??
          Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
    );
  }
}

/// Extension for quick access to premium typography
extension PremiumTextStyles on BuildContext {
  TextStyle get h1 => PremiumTypography.heading1(this);
  TextStyle get h2 => PremiumTypography.heading2(this);
  TextStyle get h3 => PremiumTypography.heading3(this);
  TextStyle get h4 => PremiumTypography.heading4(this);

  TextStyle get bodyL => PremiumTypography.bodyLarge(this);
  TextStyle get bodyM => PremiumTypography.bodyMedium(this);
  TextStyle get bodyS => PremiumTypography.bodySmall(this);

  TextStyle get buttonText => PremiumTypography.button(this);
  TextStyle get labelText => PremiumTypography.label(this);
  TextStyle get captionText => PremiumTypography.caption(this);
  TextStyle get subtitle => PremiumTypography.subtitle(this);
}
