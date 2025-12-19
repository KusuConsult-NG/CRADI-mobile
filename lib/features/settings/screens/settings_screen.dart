import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/core/providers/language_provider.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/core/providers/connectivity_provider.dart';
import 'package:climate_app/features/profile/providers/profile_provider.dart';
import 'package:climate_app/core/providers/settings_provider.dart';
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
  bool _pushNotifications = true;
  bool _criticalAlerts = true;
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

      if (mounted) {
        setState(() {
          _biometricAvailable = available;
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

  Future<void> _toggleBiometric(bool value) async {
    try {
      final authProvider = context.read<AuthProvider>();
      await authProvider.setBiometricEnabled(value);

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
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
                            image: profile.profileImagePath != null
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
                            color: profile.profileImagePath == null
                                ? Colors.grey.shade300
                                : null,
                          ),
                          child: profile.profileImagePath == null
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
                                '${profile.monitoringZone ?? "Benue State"} • Active',
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
                    _buildSwitchTile(
                      icon: Icons.notifications,
                      color: Colors.red,
                      title: provider.pushNotifications,
                      value: _pushNotifications,
                      onChanged: (v) => setState(() => _pushNotifications = v),
                    ),
                    Divider(height: 1, color: Colors.grey.shade100, indent: 60),
                    _buildSwitchTile(
                      icon: Icons.warning,
                      color: Colors.orange,
                      title: provider.criticalAlerts,
                      subtitle: 'Play sound even if muted',
                      value: _criticalAlerts,
                      onChanged: (v) => setState(() => _criticalAlerts = v),
                    ),
                    Divider(height: 1, color: Colors.grey.shade100, indent: 60),
                    _buildNavTile(
                      icon: Icons.do_not_disturb_on,
                      color: Colors.purple,
                      title: provider.dnd,
                      trailingText: 'Off',
                      onTap: () {},
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              _buildSectionHeader(provider.dataStorage),
              Container(
                decoration: _cardDecoration(),
                child: Column(
                  children: [
                    Consumer<ConnectivityProvider>(
                      builder: (context, connectivity, _) => _buildSwitchTile(
                        icon: Icons.offline_bolt,
                        color: Colors.orange,
                        title: 'Offline Mode',
                        subtitle: 'Use app without internet connection',
                        value: connectivity.manualOffline,
                        onChanged: (v) => connectivity.setManualOffline(v),
                      ),
                    ),
                    Divider(height: 1, color: Colors.grey.shade100, indent: 60),
                    Consumer<SettingsProvider>(
                      builder: (context, settings, _) => Column(
                        children: [
                          _buildSwitchTile(
                            icon: Icons.wifi,
                            color: Colors.blue,
                            title: provider.wifiOnly,
                            value: settings.wifiOnly,
                            onChanged: (v) => settings.setWifiOnly(v),
                          ),
                          Divider(
                            height: 1,
                            color: Colors.grey.shade100,
                            indent: 60,
                          ),
                          _buildSwitchTile(
                            icon: Icons.data_saver_on,
                            color: Colors.green,
                            title: provider.lowData,
                            subtitle: 'Reduce data usage for maps',
                            value: settings.lowData,
                            onChanged: (v) => settings.setLowData(v),
                          ),
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
                      icon: Icons.language,
                      color: Colors.grey,
                      title: provider.language,
                      trailingText: provider.selectedLanguage,
                      onTap: () => _showLanguageSelector(context, provider),
                    ),
                    Divider(height: 1, color: Colors.grey.shade100, indent: 60),
                    _buildNavTile(
                      icon: Icons.help,
                      color: Colors.grey,
                      title: provider.helpFaq,
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: Text(provider.helpFaq),
                            content: const Text(
                              'Frequently Asked Questions would appear here.\n\n1. How to report?\n2. What is an alert?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c),
                                child: Text(provider.ok),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    Divider(height: 1, color: Colors.grey.shade100, indent: 60),
                    _buildNavTile(
                      icon: Icons.info,
                      color: Colors.grey,
                      title: provider.aboutApp,
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: Text(provider.aboutApp),
                            content: const Text(
                              'Climate Early Warning System (CEWS)\nVersion 2.4.1\n\nDeveloped for CRADI.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c),
                                child: Text(provider.ok),
                              ),
                            ],
                          ),
                        );
                      },
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
                              content: Text('Logout failed: $e'),
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
                child: Column(
                  children: [
                    Text(
                      'Climate Early Warning System (CEWS)',
                      style: GoogleFonts.lexend(
                        fontSize: 12,
                        color: Colors.grey.shade400,
                      ),
                    ),
                    Text(
                      'Version 2.4.1 (Build 204)',
                      style: GoogleFonts.lexend(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
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

  void _showLanguageSelector(BuildContext context, LanguageProvider provider) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final languages = ['English', 'Hausa', 'Yoruba', 'Igbo', 'Pidgin'];
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Select Language',
                style: GoogleFonts.lexend(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ...languages.map(
                (lang) => ListTile(
                  title: Text(lang, style: GoogleFonts.lexend(fontSize: 16)),
                  trailing: provider.selectedLanguage == lang
                      ? const Icon(Icons.check, color: AppColors.primaryRed)
                      : null,
                  onTap: () {
                    provider.setLanguage(lang);
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
