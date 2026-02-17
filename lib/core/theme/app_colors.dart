import 'package:flutter/material.dart';

class AppColors {
  // Primary Brand Colors - Modern & Vibrant
  static const Color primaryRed = Color(0xFFE63946); // Vibrant red
  static const Color primaryDeep = Color(0xFF9D0208); // Deep red
  static const Color primaryGrey = Color(0xFF8D99AE); // Soft grey-blue

  // Gradient Colors for Modern UI
  static const Color gradientStart = Color(0xFF667EEA); // Purple-blue
  static const Color gradientMid = Color(0xFF764BA2); // Purple
  static const Color gradientEnd = Color(0xFFF093FB); // Pink

  // Secondary Gradients for variety
  static const Color accentGradientStart = Color(0xFF4FACFE); // Sky blue
  static const Color accentGradientEnd = Color(0xFF00F2FE); // Cyan

  // Success/Warning/Error with modern tints
  static const Color successGreen = Color(0xFF06D6A0); // Vibrant teal-green
  static const Color warningOrange = Color(0xFFFF6B35); // Coral orange
  static const Color warningYellow = warningOrange; // Backwards compat alias
  static const Color errorRed = Color(0xFFEF476F); // Bright pink-red

  // Neutral Colors - Softer, More Premium
  static const Color background = Color(0xFFF8F9FA); // Subtle off-white
  static const Color surface = Color(0xFFFFFFFF); // Pure white
  static const Color surfaceGlass = Color(0x40FFFFFF); // Glassmorphism overlay
  static const Color textPrimary = Color(0xFF1A1A2E); // Deep navy-black
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textPlaceholder = Color(
    0xFF9CA3AF,
  ); // Added placeholder color // Modern grey
  static const Color divider = Color(0xFFE5E7EB); // Light grey

  // Glassmorphism colors
  static const Color glassWhite = Color(0x1AFFFFFF); // 10% white
  static const Color glassBorder = Color(0x33FFFFFF); // 20% white border

  // Hazard Specific Colors - More Vibrant
  static const Color hazardFlood = Color(0xFF06B6D4); // Cyan
  static const Color hazardDrought = Color(0xFFF59E0B); // Amber
  static const Color hazardFire = Color(0xFFF97316); // Orange
  static const Color hazardWind = Color(0xFF8B5CF6); // Violet
  static const Color hazardTemp = Color(0xFFEC4899); // Pink
  static const Color hazardPest = Color(0xFF10B981); // Emerald
  static const Color hazardErosion = Color(0xFF78716C); // Stone

  // Premium Gradient Definitions
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gradientStart, gradientMid, gradientEnd],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accentGradientStart, accentGradientEnd],
  );

  static const LinearGradient subtleGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF8F9FA), Color(0xFFE9ECEF)],
  );
}
