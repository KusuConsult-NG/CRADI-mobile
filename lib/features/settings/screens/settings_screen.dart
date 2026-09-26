import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/core/providers/language_provider.dart';
import 'package:climate_app/core/widgets/language_selector_sheet.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/core/providers/connectivity_provider.dart';
import 'package:climate_app/features/profile/providers/profile_provider.dart';
import 'package:climate_app/core/providers/settings_provider.dart';
import 'package:climate_app/core/services/biometric_service.dart';
import 'package:climate_app/core/services/notification_service.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:provider/provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _checkingBiometric = true;

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    try {
      final authProvider = context.read<AuthProvider>();
      final available = await authProvider.isBiometricAvailable();
      final enabled = await authProvider.isBiometricEnabled();

      // Also check that the user has actually enrolled credentials
      // (hardware can be present but have no fingerprints/face enrolled).
      bool hasEnrolled = false;
      if (available) {
        final biometrics = await BiometricService().getAvailableBiometrics();
        hasEnrolled = biometrics.isNotEmpty;
      }

      if (mounted) {
        setState(() {
          _biometricAvailable = available && hasEnrolled;
          _biometricEnabled = enabled;
          _checkingBiometric = false;
        });
      }
    } on Exception {
      if (mounted) {
        setState(() {
          _checkingBiometric = false;
        });
      }
    }
  }

  /// Persists the Push Notifications setting and opts this device in to /
  /// out of OneSignal push.
  Future<void> _setPushNotifications(
    SettingsProvider settings,
    bool value,
  ) async {
    await settings.setPushNotifications(value);
    final service = NotificationService();
    if (value) {
      // Explicit user action: may offer to open the system settings when
      // the permission was denied before.
      await service.requestPushPermission(fallbackToSettings: true);
    }
    final ok = await service.setPushSubscribed(value);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Push notifications are unavailable right now. Your choice is '
            'saved and will apply when they are.',
          ),
        ),
      );
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    try {
      final authProvider = context.read<AuthProvider>();
      final profileProvider = context.read<ProfileProvider>();
      await authProvider.setBiometricEnabled(value);
      // Keep the profile screen's biometric switch in sync.
      await profileProvider.refreshBiometricsEnabled();

      if (mounted) {
        setState(() => _biometricEnabled = value);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value ? 'Biometric login enabled' : 'Biometric login disabled',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on AuthException catch (e) {
      // setBiometricEnabled throws when the confirming prompt fails;
      // BiometricService keeps the local_auth error code of that failure.
      if (!mounted) return;
      final bio = BiometricService();
      final code = bio.lastErrorCode;
      final notEnrolled = bio.lastErrorIsNotEnrolled;
      final message = code != null
          ? BiometricService.messageFor(code)
          : e.toString();
      if (message != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: notEnrolled ? Colors.orange : Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      // Enrolment / hardware state may have changed: refresh availability.
      if (notEnrolled) await _checkBiometric();
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorHandler.getUserMessage(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LanguageProvider>(
      builder: (context, provider, _) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: const SizedBox(),
          leadingWidth: 0,
          title: GestureDetector(
            onTap: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/dashboard');
              }
            },
            child: Row(
              children: [
                const Icon(
                  Icons.arrow_back_ios_new,
                  size: 20,
                  color: AppColors.primaryRed,
                ),
                const SizedBox(width: 4),
                Text(
                  provider.back,
                  style: GoogleFonts.lexend(
                    fontSize: 16,
                    color: AppColors.primaryRed,
                  ),
                ),
              ],
            ),
          ),
          backgroundColor: AppColors.background.withValues(alpha: 0.95),
          elevation: 0,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                provider.settingsTitle,
                style: GoogleFonts.lexend(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 24),

              // Profile Header
              GestureDetector(
                onTap: () => context.push('/profile'),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: _cardDecoration(),
                  child: Consumer<ProfileProvider>(
                    builder: (context, profile, _) => Row(
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.primaryRed,
                              width: 2,
                            ),
                            image:
                                profile.profileImagePath != null &&
                                    profile.profileImagePath!.isNotEmpty
                                ? DecorationImage(
                                    image:
                                        profile.profileImagePath!.startsWith(
                                          'http',
                                        )
                                        ? NetworkImage(
                                                profile.profileImagePath!,
                                              )
                                              as ImageProvider
                                        : FileImage(
                                            File(profile.profileImagePath!),
                                          ),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                            color:
                                profile.profileImagePath == null ||
                                    profile.profileImagePath!.isEmpty
                                ? Colors.grey.shade300
                                : null,
                          ),
                          child:
                              profile.profileImagePath == null ||
                                  profile.profileImagePath!.isEmpty
                              ? const Icon(Icons.person, color: Colors.grey)
                              : Align(
                                  alignment: Alignment.bottomRight,
                                  child: Container(
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryRed,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile.name,
                                style: GoogleFonts.lexend(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                '${profile.monitoringZone ?? "Not Set"} • ${profile.monitoringZone != null ? "Active" : "Select Zone"}',
                                style: GoogleFonts.lexend(
                                  fontSize: 14,
                                  color: AppColors.primaryRed,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: AppColors.background,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.edit,
                            size: 20,
                            color: AppColors.primaryRed,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Notifications
              _buildSectionHeader(provider.notifications),
              Container(
                decoration: _cardDecoration(),
                child: Column(
                  children: [
                    Consumer<SettingsProvider>(
                      builder: (context, settings, _) => Column(
                        children: [
                          _buildSwitchTile(
                            icon: Icons.notifications,
                            color: Colors.red,
                            title: provider.pushNotifications,
                            value: settings.pushNotifications,
                            onChanged: (v) =>
                                _setPushNotifications(settings, v),
                          ),
                          // "Critical alerts" (sound while muted) is hidden until
                          // the iOS critical-alert entitlement and an Android
                          // high-importance channel actually back it.
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Security
              _buildSectionHeader('SECURITY \u0026 PRIVACY'),
              Container(
                decoration: _cardDecoration(),
                child: Column(
                  children: [
                    if (_biometricAvailable && !_checkingBiometric)
                      _buildSwitchTile(
                        icon: Icons.fingerprint,
                        color: AppColors.primaryRed,
                        title: 'Biometric Login',
                        subtitle: 'Use fingerprint or Face ID to login',
                        value: _biometricEnabled,
                        onChanged: _toggleBiometric,
                      ),
                    if (!_biometricAvailable && !_checkingBiometric)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.fingerprint,
                                color: Colors.grey.shade400,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Biometric Login',
                                    style: GoogleFonts.lexend(
                                      fontSize: 16,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                  Text(
                                    'Not available on this device',
                                    style: GoogleFonts.lexend(
                                      fontSize: 12,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_checkingBiometric)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // General
              _buildSectionHeader(provider.general),
              Container(
                decoration: _cardDecoration(),
                child: Column(
                  children: [
                    _buildNavTile(
                      icon: Icons.menu_book,
                      color: AppColors.primaryRed,
                      title: provider.navGuides,
                      onTap: () => context.push('/knowledge-base'),
                    ),
                    Divider(height: 1, color: Colors.grey.shade100, indent: 60),
                    _buildNavTile(
                      icon: Icons.language,
                      color: Colors.grey,
                      title: provider.language,
                      trailingText: provider.selectedLanguage,
                      onTap: () => showLanguageSelectorSheet(context, provider),
                    ),
                    Divider(height: 1, color: Colors.grey.shade100, indent: 60),

                    // Offline Mode Toggle
                    SwitchListTile(
                      secondary: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.wifi_off,
                          color: Colors.orange,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        'Offline Mode',
                        style: GoogleFonts.lexend(
                          fontSize: 16,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      value: context
                          .watch<ConnectivityProvider>()
                          .manualOffline,
                      onChanged: (value) {
                        context.read<ConnectivityProvider>().setManualOffline(
                          value,
                        );
                        if (value) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Offline mode enabled'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Restoring connection...'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      },
                    ),
                    Divider(height: 1, color: Colors.grey.shade100, indent: 60),

                    _buildNavTile(
                      icon: Icons.help,
                      color: Colors.grey,
                      title: provider.helpFaq,
                      onTap: () => context.push('/help'),
                    ),
                    Divider(height: 1, color: Colors.grey.shade100, indent: 60),
                    _buildNavTile(
                      icon: Icons.info,
                      color: Colors.grey,
                      title: provider.aboutApp,
                      onTap: () => context.push('/about'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Footer
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(provider.logout),
                        content: const Text(
                          'Are you sure you want to sign out?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(provider.cancel),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(
                              provider.logout,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true && context.mounted) {
                      try {
                        // Perform logout logic
                        await context.read<AuthProvider>().logout();
                        if (context.mounted) {
                          context.read<ProfileProvider>().clearProfile();
                          context.go('/login');
                        }
                      } on Exception catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                ErrorHandler.handleError(e, context: 'Logout'),
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    }
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: AppColors.background,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  child: Text(
                    provider.logout,
                    style: GoogleFonts.lexend(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Climate Early Warning System (CEWS)',
                  style: GoogleFonts.lexend(
                    fontSize: 12,
                    color: Colors.grey.shade400,
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 8),
      child: Text(
        title,
        style: GoogleFonts.lexend(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade500,
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required Color color,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.lexend(
                    fontSize: 16,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: GoogleFonts.lexend(
                      fontSize: 12,
                      color: Colors.grey.shade400,
                    ),
                  ),
              ],
            ),
          ),
          CupertinoSwitch(
            value: value,
            activeTrackColor: AppColors.primaryRed,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildNavTile({
    required IconData icon,
    required Color color,
    required String title,
    String? trailingText,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.lexend(
                  fontSize: 16,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (trailingText != null)
              Text(
                trailingText,
                style: GoogleFonts.lexend(
                  fontSize: 14,
                  color: Colors.grey.shade400,
                ),
              ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade100),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.02),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }
}
