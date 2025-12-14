import 'package:climate_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  int _currentStep = 1;
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _coordinatorCodeController =
      TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  // OTP Logic
  final List<TextEditingController> _otpDigitControllers = List.generate(
    4,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _otpFocusNodes = List.generate(4, (_) => FocusNode());

  @override
  void dispose() {
    _phoneController.dispose();
    _coordinatorCodeController.dispose();
    _otpController.dispose();
    for (var c in _otpDigitControllers) {
      c.dispose();
    }
    for (var n in _otpFocusNodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _onOtpChanged(String value, int index) {
    if (value.isNotEmpty && index < 3) {
      _otpFocusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _otpFocusNodes[index - 1].requestFocus();
    }
  }

  void _nextStep() {
    setState(() {
      if (_currentStep < 3) _currentStep++;
    });
  }

  void _prevStep() {
    setState(() {
      if (_currentStep > 1) _currentStep--;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      if (_currentStep > 1) {
                        _prevStep();
                      } else {
                        Navigator.pop(context);
                      }
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.transparent,
                        // hover effect simulated
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'EWM Registration',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.lexend(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 40), // Balance
                ],
              ),
            ),

            // Progress Indicators
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      _buildProgressIndicator(1),
                      const SizedBox(width: 12),
                      _buildProgressIndicator(2),
                      const SizedBox(width: 12),
                      _buildProgressIndicator(3),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Step $_currentStep of 3',
                    style: GoogleFonts.lexend(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // Main Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_currentStep == 1) _buildStep1(),
                    if (_currentStep == 2) _buildStep2(),
                    if (_currentStep == 3) _buildStep3(),

                    const Spacer(),

                    // Action Buttons
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          if (_currentStep < 3) {
                            _nextStep();
                          } else {
                            // Submit Registration
                            context.go('/dashboard');
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryRed,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 4,
                          shadowColor: AppColors.primaryRed.withValues(
                            alpha: 0.25,
                          ),
                        ),
                        child: Text(
                          _currentStep == 3 ? 'Verify & Register' : 'Next Step',
                          style: GoogleFonts.lexend(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: TextButton.icon(
                        onPressed: () {},
                        icon: const Icon(
                          Icons.help_outline,
                          size: 20,
                          color: AppColors.textSecondary,
                        ),
                        label: Text(
                          'Need Help? Call Support',
                          style: GoogleFonts.lexend(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Decorative Bottom Gradient
            IgnorePointer(
              child: Container(
                height: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      AppColors.primaryRed.withValues(alpha: 0.05),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator(int step) {
    bool isActive = step <= _currentStep;
    return Expanded(
      child: Container(
        height: 8,
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primaryRed
              : AppColors.divider.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(999),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: AppColors.primaryRed.withValues(alpha: 0.3),
                    blurRadius: 10,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
      ),
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Welcome, Monitor',
          style: GoogleFonts.lexend(
            fontSize: 30, // text-3xl
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Please enter the mobile phone number you use for alerts.',
          style: GoogleFonts.lexend(
            fontSize: 18, // text-lg
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 32),

        // Phone Input
        Text(
          'Phone Number',
          style: GoogleFonts.lexend(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.divider.withValues(alpha: 0.5),
              width: 2,
            ),
          ),
          child: TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            style: GoogleFonts.lexend(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: '+234 800 000 0000',
              prefixIcon: const Icon(
                Icons.smartphone,
                color: AppColors.textSecondary,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
              hintStyle: GoogleFonts.lexend(
                color: AppColors.textSecondary.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(
              Icons.info_outline,
              size: 16,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              "We'll send a code to verify this number.",
              style: GoogleFonts.lexend(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Registration Code',
          style: GoogleFonts.lexend(
            fontSize: 30,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Enter the 6-digit code given to you by your coordinator.',
          style: GoogleFonts.lexend(
            fontSize: 18,
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 32),

        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.divider.withValues(alpha: 0.5),
              width: 2,
            ),
          ),
          child: TextField(
            controller: _coordinatorCodeController,
            keyboardType: TextInputType.number,
            style: GoogleFonts.lexend(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: '123456',
              prefixIcon: const Icon(
                Icons.vpn_key,
                color: AppColors.textSecondary,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
              hintStyle: GoogleFonts.lexend(
                color: AppColors.textSecondary.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Verify it's you",
          style: GoogleFonts.lexend(
            fontSize: 30,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'We sent a code to your phone. Enter it below.',
          style: GoogleFonts.lexend(
            fontSize: 18,
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 32),

        // OTP Input (Simplified for UI demo, better with Pinput package)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(4, (index) {
            return SizedBox(
              width: 56,
              height: 64,
              child: TextFormField(
                controller: _otpDigitControllers[index],
                focusNode: _otpFocusNodes[index],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 1,
                style: GoogleFonts.lexend(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  counterText: "",
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppColors.divider.withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppColors.divider.withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppColors.primaryRed,
                      width: 2,
                    ),
                  ),
                ),
                onChanged: (value) => _onOtpChanged(value, index),
              ),
            );
          }),
        ),
      ],
    );
  }
}
