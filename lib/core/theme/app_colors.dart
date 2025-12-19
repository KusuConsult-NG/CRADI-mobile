import 'package:flutter/material.dart';

class AppColors {
  // Primary Brand Colors
  static const Color primaryRed = Color(0xFFDC2626); // Tailwind Red 600
  static const Color primaryGrey = Color(0xFF999999); // Extracted from image
  
  // Secondary/Accent Colors
  static const Color accentBlue = Color(0xFF005696); 
  static const Color successGreen = Color(0xFF28A745);
  static const Color warningYellow = Color(0xFFFFC107);
  static const Color errorRed = Color(0xFFDC3545);
  
  // Neutral Colors
  static const Color background = Color(0xFFFDFDFD); // Extracted white/off-white
  static const Color surface = Colors.white;
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color divider = Color(0xFFBDBDBD);
  
  // Hazard Specific Colors
  static const Color hazardFlood = Color(0xFF4FC3F7);
  static const Color hazardDrought = Color(0xFFFFB74D);
  static const Color hazardFire = Color(0xFFFF5722);
  static const Color hazardWind = Color(0xFF90A4AE);
  static const Color hazardTemp = Color(0xFFFF8A65);
  static const Color hazardPest = Color(0xFFAED581);
  static const Color hazardErosion = Color(0xFFBCAAA4);
}
