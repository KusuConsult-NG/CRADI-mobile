import 'dart:io';

import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart'
    as app_auth;
import 'package:climate_app/features/profile/providers/profile_provider.dart';
import 'package:climate_app/features/chat/screens/chat_screen.dart';
import 'package:climate_app/core/providers/language_provider.dart';
import 'package:climate_app/core/services/biometric_service.dart';
import 'package:climate_app/features/contacts/providers/emergency_contacts_provider.dart';
import 'package:climate_app/core/widgets/location_selector_widget.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/shared/widgets/custom_button.dart';
import 'package:climate_app/shared/widgets/custom_text_field.dart';
import 'package:climate_app/l10n/app_localizations.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile != null && mounted) {
        final profileProvider = context.read<ProfileProvider>();
        try {
          await profileProvider.uploadProfileImage(pickedFile);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Profile photo updated!'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } on Exception catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  ErrorHandler.handleError(e, context: 'Profile Upload'),
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error: ${e.toString().contains('camera') ? 'Camera not available. Please use the gallery.' : 'Failed to pick image. Please try again.'}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showImagePickerOptions() {
    // On web, camera access is limited, so we handle it differently
    if (kIsWeb) {
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Update Profile Photo',
                  style: GoogleFonts.lexend(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(
                    Icons.photo_library,
                    color: AppColors.primaryRed,
                  ),
                  title: const Text('Choose from Gallery'),
                  subtitle: const Text('Select a photo from your device'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickImage(ImageSource.gallery);
                  },
                ),
                const Divider(),
                const ListTile(
                  leading: Icon(Icons.info_outline, color: Colors.grey),
                  title: Text('Camera not available on web'),
                  subtitle: Text('Please use the gallery option'),
                  enabled: false,
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      // On mobile, show both options
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Photo Library'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(ImageSource.camera);
                },
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _editProfileDetails() async {
    final profileProvider = context.read<ProfileProvider>();
    final nameController = TextEditingController(text: profileProvider.name);
    final emailController = TextEditingController(text: profileProvider.email);
    String? selectedState = profileProvider.state;
    String? selectedLGA = profileProvider.lga;
    String? selectedWard = profileProvider.ward;

    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (context) => _DisposeControllersOnUnmount(
        controllers: [nameController, emailController],
        child: StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(
                'Edit Profile',
                style: GoogleFonts.lexend(fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CustomTextField(
                      controller: nameController,
                      label: 'Full Name',
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      controller: emailController,
                      label: 'Email Address',
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    LocationSelectorWidget(
                      initialState: selectedState,
                      initialLGA: selectedLGA,
                      initialWard: selectedWard,
                      onLocationChanged: (state, lga, ward) {
                        // No need to call setState here as the widget handles its own state
                        // But we need to update our local variables to pass back on save
                        selectedState = state;
                        selectedLGA = lga;
                        selectedWard = ward;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                SizedBox(
                  width: 100,
                  child: CustomButton(
                    text: 'Cancel',
                    type: ButtonType.ghost,
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: CustomButton(
                    text: 'Save',
                    onPressed: () => Navigator.pop(context, {
                      'name': nameController.text,
                      'email': emailController.text,
                      'state': selectedState,
                      'lga': selectedLGA,
                      'ward': selectedWard,
                    }),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );

    if (result != null && mounted) {
      if (result['name'] != null && result['name']!.isNotEmpty) {
        await profileProvider.updateName(result['name']!);
      }
      String? emailMessage;
      if (result['email'] != null) {
        emailMessage = await profileProvider.updateEmail(result['email']!);
      }
      // Update location (may be refused for approved staff accounts)
      final locationMessage = await profileProvider.updateLocation(
        result['state'],
        result['lga'],
        result['ward'],
      );

      if (mounted) {
        final message = [?emailMessage, ?locationMessage].join('\n');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              message.isEmpty ? 'Profile updated successfully!' : message,
            ),
            backgroundColor: message.isEmpty ? Colors.green : null,
          ),
        );
      }
    }
  }

  Future<void> _showVerificationDialog() async {
    final codeController = TextEditingController();
    bool isVerifying = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DisposeControllersOnUnmount(
        controllers: [codeController],
        child: StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                'Verify Account',
                style: GoogleFonts.lexend(fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Enter the Access Code sent to your email to verify your account.',
                    style: GoogleFonts.lexend(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  CustomTextField(
                    controller: codeController,
                    label: 'Access Code',
                    hint: 'e.g., ABC-123',
                    enabled: !isVerifying,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isVerifying ? null : () => Navigator.pop(context),
                  child: Text(AppLocalizations.of(context)!.cancel),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryRed,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: isVerifying
                      ? null
                      : () async {
                          final code = codeController.text.trim();
                          if (code.isEmpty) return;

                          setState(() => isVerifying = true);

                          // Simulate verification logic
                          // In a real app, you'd call a provider method here
                          // For MVP Generator Flow:
                          try {
                            final authProvider = context
                                .read<app_auth.AuthProvider>();
                            if (authProvider.currentUser == null) {
                              throw Exception("User not found");
                            }

                            await authProvider.verifyOtpAndLogin(code);

                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Account verified successfully!',
                                  ),
                                  backgroundColor: Colors.green,
                                ),
                              );
                              // Trigger refresh
                              context
                                  .read<app_auth.AuthProvider>()
                                  .validateSession();
                            }
                          } on Exception catch (e) {
                            if (context.mounted) {
                              setState(() => isVerifying = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    ErrorHandler.handleError(
                                      e,
                                      context: 'Account Verification',
                                    ),
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                  child: isVerifying
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Verify'),
                ),
              ],
              // Added UI Hint / Fallback for Flawless SMS / Email Delivery Assumption
              contentPadding: const EdgeInsets.only(
                left: 24,
                right: 24,
                top: 20,
                bottom: 0,
              ),
              actionsPadding: const EdgeInsets.only(
                left: 24,
                right: 24,
                top: 16,
                bottom: 16,
              ),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            size: 20,
            color: AppColors.textPrimary,
          ),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/dashboard');
            }
          },
        ),
        title: Text(
          'My Profile',
          style: GoogleFonts.lexend(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppColors.background.withValues(alpha: 0.95),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.grey.shade200, height: 1.0),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 40),
        child: Column(
          children: [
            const SizedBox(height: 24),
            // Profile Header
            Center(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _showImagePickerOptions,
                    child: Stack(
                      children: [
                        _buildProfileImage(),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              color: AppColors.primaryRed,
                              size: 24,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Consumer<ProfileProvider>(
                    builder: (context, profileProvider, _) => Text(
                      profileProvider.name,
                      style: GoogleFonts.lexend(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Consumer<app_auth.AuthProvider>(
                    builder: (context, authProvider, _) {
                      String roleText = 'Early Warning Monitor';
                      if (authProvider.rawUserRole != null) {
                        // Simple formatted string from enum
                        switch (authProvider.rawUserRole!) {
                          case app_auth.UserRole.user:
                            roleText = 'User';
                            break;
                          case app_auth.UserRole.ewm:
                            roleText = 'Early Warning Monitor';
                            break;
                          case app_auth.UserRole.ewv:
                            roleText = 'Early Warning Validator';
                            break;
                          case app_auth.UserRole.ewr:
                            roleText = 'Early Warning Responder';
                            break;
                          case app_auth.UserRole.ldpCoordinator:
                            roleText = 'LDP Coordinator';
                            break;
                          case app_auth.UserRole.projectStaff:
                            roleText = 'Project Staff';
                            break;
                          case app_auth.UserRole.admin:
                            roleText = 'Administrator';
                            break;
                          case app_auth.UserRole.techSupport:
                            roleText = 'Tech Support';
                            break;
                        }
                      }
                      return Text(
                        roleText,
                        style: GoogleFonts.lexend(
                          fontSize: 16,
                          color: AppColors.textSecondary,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryRed.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.primaryRed.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.badge,
                          size: 16,
                          color: AppColors.primaryRed,
                        ),
                        const SizedBox(width: 8),
                        Consumer<ProfileProvider>(
                          builder: (context, profile, _) {
                            // Show actual registration code from database
                            final code = profile.registrationCode ?? 'N/A';

                            return Text(
                              'ID: $code',
                              style: GoogleFonts.lexend(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: AppColors.primaryRed,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Account Status Badge
                  Consumer<app_auth.AuthProvider>(
                    builder: (context, authProvider, _) {
                      final isVerified = authProvider.isVerified;

                      return Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isVerified
                                  ? AppColors.successGreen.withValues(
                                      alpha: 0.1,
                                    )
                                  : Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isVerified
                                    ? AppColors.successGreen.withValues(
                                        alpha: 0.3,
                                      )
                                    : Colors.orange.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isVerified ? Icons.verified : Icons.pending,
                                  size: 16,
                                  color: isVerified
                                      ? AppColors.successGreen
                                      : Colors.orange,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  isVerified ? 'Verified' : 'Unverified',
                                  style: GoogleFonts.lexend(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: isVerified
                                        ? AppColors.successGreen
                                        : Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!isVerified) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              width: 140,
                              height: 36,
                              child: ElevatedButton(
                                onPressed: _showVerificationDialog,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryRed,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                child: Text(
                                  'Verify Now',
                                  style: GoogleFonts.lexend(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  Consumer<ProfileProvider>(
                    builder: (context, profile, _) {
                      if (profile.email.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          profile.email,
                          style: GoogleFonts.lexend(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Stats
            Consumer<ProfileProvider>(
              builder: (context, profile, _) =>
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: profile.getUserReportsStream(),
                    builder: (context, snapshot) {
                      int totalReports = 0;
                      int verifiedCount = 0;

                      if (snapshot.hasData) {
                        totalReports = snapshot.data!.length;
                        verifiedCount = snapshot.data!.where((doc) {
                          final status = doc['status'];
                          return status == 'verified' || status == 'approved';
                        }).length;
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => context.push('/reports-status'),
                                child: _buildStatCard(
                                  '$totalReports',
                                  'Reports',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => context.push('/reports-status'),
                                child: _buildStatCard(
                                  '$verifiedCount',
                                  'Verified',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: _buildDaysActiveCard(profile)),
                          ],
                        ),
                      );
                    },
                  ),
            ),

            const SizedBox(height: 24),

            // Account Settings
            _buildSectionHeader(null, 'Account Settings'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _buildSettingsTile(
                    Icons.person,
                    'Edit Profile Details',
                    onTap: _editProfileDetails,
                  ),
                  const SizedBox(height: 8),
                  // Biometrics Toggle
                  Consumer<ProfileProvider>(
                    builder: (context, profile, _) => SwitchListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade100),
                      ),
                      tileColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      secondary: Icon(
                        Icons.fingerprint,
                        color: profile.biometricsEnabled
                            ? AppColors.primaryRed
                            : Colors.grey.shade400,
                      ),
                      title: Text(
                        'Biometric Login',
                        style: GoogleFonts.lexend(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        profile.biometricsEnabled ? 'Enabled' : 'Disabled',
                        style: GoogleFonts.lexend(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                        ),
                      ),
                      activeThumbColor: AppColors.primaryRed,
                      value: profile.biometricsEnabled,
                      onChanged: (value) async {
                        if (value) {
                          final available = await BiometricService()
                              .isBiometricAvailable();
                          if (!available) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Biometrics not available on this device',
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                            return;
                          }

                          final authenticated = await BiometricService()
                              .authenticate(
                                reason: 'Authenticate to enable biometrics',
                                useErrorDialogs: true,
                              );

                          if (authenticated) {
                            await profile.setBiometricsEnabled(true);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Biometrics enabled!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          }
                        } else {
                          await profile.setBiometricsEnabled(false);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Consumer<LanguageProvider>(
                    builder: (context, languageProvider, _) =>
                        _buildSettingsTile(
                          Icons.language,
                          'Language Preference',
                          subtitle: languageProvider.selectedLanguage,
                          onTap: () => context.push('/settings'),
                        ),
                  ),
                  const SizedBox(height: 8),
                  _buildSettingsTile(
                    Icons.sync,
                    'Offline Data Sync',
                    subtitle: 'Up to date',
                    subtitleColor: AppColors.successGreen,
                    onTap: () async {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Syncing offline data...',
                            style: GoogleFonts.lexend(),
                          ),
                        ),
                      );
                      // Refresh all major providers
                      final profileProvider = context.read<ProfileProvider>();
                      await profileProvider.loadProfile();

                      if (context.mounted) {
                        // For streams, the next event will have new data
                        // For future-based ones, we re-call
                        context.read<EmergencyContactsProvider>().getContacts();

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Sync complete!'),
                            backgroundColor: AppColors.successGreen,
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  _buildSettingsTile(
                    Icons.chat_bubble_outline,
                    'Support Chat',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ChatScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  _buildSettingsTile(
                    Icons.help,
                    'Help & Support',
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: Text(
                            'Help & Support',
                            style: GoogleFonts.lexend(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          content: Text(
                            'Email: support@climateapp.org\nPhone: +234 800 1234 567',
                            style: GoogleFonts.lexend(),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c),
                              child: Text(AppLocalizations.of(context)!.close),
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

            // SOS & Logout
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  CustomButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: Text(
                            'SOS Emergency',
                            style: GoogleFonts.lexend(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          content: Text(
                            'Send emergency alert to your supervisor?',
                            style: GoogleFonts.lexend(),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c),
                              child: Text(AppLocalizations.of(context)!.cancel),
                            ),
                            CustomButton(
                              onPressed: () {
                                Navigator.pop(c);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Emergency alert sent!',
                                      style: GoogleFonts.lexend(),
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              },
                              text: 'Send Alert',
                              width: 120, // Optional constraint
                            ),
                          ],
                        ),
                      );
                    },
                    text: 'Contact Supervisor / SOS',
                    icon: Icons.sos,
                    // Note: Using primary red for SOS to make it prominent
                  ),
                  const SizedBox(height: 16),
                  CustomButton(
                    text: 'Log Out',
                    type: ButtonType.ghost,
                    onPressed: () async {
                      // Explicitly clear profile data including offline cache
                      await context.read<ProfileProvider>().clearProfile();

                      // Logout from AuthProvider (clears session and secure storage)
                      if (context.mounted) {
                        await context.read<app_auth.AuthProvider>().logout();
                      }

                      // Navigate to login
                      if (context.mounted) {
                        context.go('/login');
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.lexend(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryRed,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.lexend(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // Calculate days active from user creation
  Widget _buildDaysActiveCard(ProfileProvider profile) {
    int daysActive = 0;

    if (profile.registrationDate != null) {
      daysActive = DateTime.now().difference(profile.registrationDate!).inDays;
      // Ensure at least 1 day is shown if they registered today
      if (daysActive <= 0) daysActive = 1;
    } else {
      daysActive = 1; // Default fallback
    }

    return _buildStatCard('$daysActive', 'Days Active');
  }

  Widget _buildSectionHeader(IconData? icon, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: AppColors.primaryRed, size: 20),
            const SizedBox(width: 8),
          ],
          Text(
            title,
            style: GoogleFonts.lexend(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTile(
    IconData icon,
    String title, {
    String? subtitle,
    Color? subtitleColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(),
        child: Row(
          children: [
            Icon(icon, color: Colors.grey.shade400),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.lexend(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: GoogleFonts.lexend(
                        fontSize: 12,
                        color: subtitleColor ?? Colors.grey.shade400,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileImage() {
    return Consumer<ProfileProvider>(
      builder: (context, profileProvider, _) {
        final imagePath = profileProvider.profileImagePath;

        return Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ClipOval(
            child: imagePath == null || imagePath.isEmpty
                ? Container(
                    color: Colors.grey.shade200,
                    child: Icon(
                      Icons.person,
                      size: 60,
                      color: Colors.grey.shade400,
                    ),
                  )
                : imagePath.startsWith('http')
                ? Image.network(
                    imagePath,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                              : null,
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey.shade200,
                        child: Icon(
                          Icons.error_outline,
                          size: 60,
                          color: Colors.grey.shade400,
                        ),
                      );
                    },
                  )
                : Image.file(
                    File(imagePath),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey.shade200,
                        child: Icon(
                          Icons.error_outline,
                          size: 60,
                          color: Colors.grey.shade400,
                        ),
                      );
                    },
                  ),
          ),
        );
      },
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

/// Disposes [controllers] when the wrapped dialog route is removed from the
/// tree (i.e. after its exit animation), so they are never used after disposal.
class _DisposeControllersOnUnmount extends StatefulWidget {
  const _DisposeControllersOnUnmount({
    required this.controllers,
    required this.child,
  });

  final List<TextEditingController> controllers;
  final Widget child;

  @override
  State<_DisposeControllersOnUnmount> createState() =>
      _DisposeControllersOnUnmountState();
}

class _DisposeControllersOnUnmountState
    extends State<_DisposeControllersOnUnmount> {
  @override
  void dispose() {
    for (final c in widget.controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
