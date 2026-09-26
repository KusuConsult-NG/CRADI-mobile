import 'package:climate_app/core/l10n/l10n.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The "Biometric Login" switch on the profile screen.
///
/// Settings greys the same setting out when the device has no usable
/// biometrics; this does too. Offering a live switch that can only fail at
/// the system prompt — and explaining it afterwards in a snackbar — is what
/// this replaces: with [available] false the switch is disabled and the
/// subtitle carries the same explanation Settings shows.
class BiometricLoginTile extends StatelessWidget {
  const BiometricLoginTile({
    super.key,
    required this.available,
    required this.checking,
    required this.enabled,
    required this.onChanged,
  });

  /// Hardware present *and* a fingerprint/face enrolled.
  final bool available;

  /// The availability check has not answered yet.
  final bool checking;

  /// Whether biometric unlock is switched on for this account.
  final bool enabled;

  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final usable = available && !checking;
    return SwitchListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade100),
      ),
      tileColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      secondary: Icon(
        Icons.fingerprint,
        color: enabled && usable ? AppColors.primaryRed : Colors.grey.shade400,
      ),
      title: Text(
        context.l10n.biometricLogin,
        style: GoogleFonts.lexend(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: usable ? AppColors.textPrimary : Colors.grey.shade400,
        ),
      ),
      subtitle: Text(
        checking
            ? context.l10n.commonLoading
            : !available
            ? context.l10n.settingsBiometricUnavailable
            : enabled
            ? context.l10n.enabled
            : context.l10n.disabled,
        style: GoogleFonts.lexend(fontSize: 12, color: Colors.grey.shade400),
      ),
      activeThumbColor: AppColors.primaryRed,
      value: enabled && usable,
      onChanged: usable ? onChanged : null,
    );
  }
}
