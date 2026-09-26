import 'dart:io';

import 'package:climate_app/core/services/remote_config_service.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart'
    as app_auth;
import 'package:climate_app/features/profile/providers/profile_provider.dart';
import 'package:climate_app/features/profile/widgets/sos_sheet.dart';
import 'package:climate_app/core/providers/language_provider.dart';
import 'package:climate_app/core/services/biometric_service.dart';
import 'package:climate_app/features/contacts/providers/emergency_contacts_provider.dart';
import 'package:climate_app/core/widgets/location_selector_widget.dart';
import 'package:climate_app/core/widgets/language_selector_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:climate_app/shared/widgets/dispose_controllers_on_unmount.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/shared/widgets/custom_button.dart';
import 'package:climate_app/shared/widgets/custom_text_field.dart';
import 'package:climate_app/core/l10n/l10n.dart';
import 'package:climate_app/core/utils/screen_security.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen>
    with ScreenSecurityMixin<UserProfileScreen> {
  final ImagePicker _picker = ImagePicker();

  /// Created once so profile rebuilds do not resubscribe the realtime stream.
  late final Stream<List<Map<String, dynamic>>> _reportsStream;

  @override
  void initState() {
    super.initState();
    _reportsStream = context.read<ProfileProvider>().getUserReportsStream();
  }

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
              SnackBar(
                content: Text(context.l10n.profilePhotoUpdated),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } on ProfileSaveException catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(e.message(context.l10n)),
                backgroundColor: Colors.red,
              ),
            );
          }
        } on Exception catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  ErrorHandler.handleError(
                    e,
                    context.l10n,
                    context: 'Profile Upload',
                  ),
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
              e.toString().contains('camera')
                  ? context.l10n.profileCameraUnavailable
                  : context.l10n.profilePickImageFailed,
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
                  context.l10n.profileUpdatePhoto,
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
                  title: Text(context.l10n.profileChooseGallery),
                  subtitle: Text(context.l10n.profileChooseGallerySubtitle),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickImage(ImageSource.gallery);
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.info_outline, color: Colors.grey),
                  title: Text(context.l10n.profileCameraWebUnavailable),
                  subtitle: Text(context.l10n.profileUseGallery),
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
                title: Text(context.l10n.profilePhotoLibrary),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: Text(context.l10n.camera),
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
    // Approved staff are scoped by area; only an admin may move them
    // (the database refuses the change).
    final auth = context.read<app_auth.AuthProvider>();
    final locationLocked =
        auth.isApproved == true &&
        auth.rawUserRole != null &&
        auth.rawUserRole != app_auth.UserRole.user;

    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (context) => DisposeControllersOnUnmount(
        controllers: [nameController, emailController],
        child: StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(
                context.l10n.profileEdit,
                style: GoogleFonts.lexend(fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CustomTextField(
                      controller: nameController,
                      label: context.l10n.fullName,
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      controller: emailController,
                      label: context.l10n.emailAddress,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    if (locationLocked)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.lock_outline),
                        title: Text(
                          [selectedWard, selectedLGA, selectedState]
                              .whereType<String>()
                              .where((v) => v.isNotEmpty)
                              .join(', '),
                          style: GoogleFonts.lexend(fontSize: 14),
                        ),
                        subtitle: Text(
                          context.l10n.profileAskAdminArea,
                          style: GoogleFonts.lexend(fontSize: 12),
                        ),
                      )
                    else
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
                    text: context.l10n.cancel,
                    type: ButtonType.ghost,
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: CustomButton(
                    text: context.l10n.save,
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
      final l10n = context.l10n;
      String? nameMessage;
      if (result['name'] != null) {
        nameMessage = (await profileProvider.updateName(
          result['name']!,
        ))?.call(l10n);
      }
      String? emailMessage;
      if (result['email'] != null) {
        emailMessage = (await profileProvider.updateEmail(
          result['email']!,
        ))?.call(l10n);
      }
      // Update location (approved staff cannot change their own area).
      final locationMessage = locationLocked
          ? null
          : (await profileProvider.updateLocation(
              result['state'],
              result['lga'],
              result['ward'],
            ))?.call(l10n);

      if (mounted) {
        // A set: offline, name and location report the same problem.
        final message = <String>{
          ?nameMessage,
          ?emailMessage,
          ?locationMessage,
        }.join('\n');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message.isEmpty ? l10n.profileUpdated : message),
            backgroundColor: message.isEmpty ? Colors.green : null,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.l10n.back,
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
          context.l10n.myProfile,
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
                      profileProvider.name.isNotEmpty
                          ? profileProvider.name
                          : context.l10n.profileDefaultName,
                      style: GoogleFonts.lexend(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Consumer<app_auth.AuthProvider>(
                    builder: (context, authProvider, _) {
                      final roleText =
                          authProvider.rawUserRole?.label(context.l10n) ??
                          context.l10n.roleEwm;
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
                            final code =
                                profile.registrationCode ??
                                context.l10n.commonNotAvailable;

                            return Text(
                              context.l10n.profileIdLabel(code),
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
                            child: Semantics(
                              label: context.l10n.a11yStatusLabel(
                                isVerified
                                    ? context.l10n.profileVerified
                                    : context.l10n.profileUnverified,
                              ),
                              excludeSemantics: true,
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
                                    isVerified
                                        ? context.l10n.profileVerified
                                        : context.l10n.profileUnverified,
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
                          ),
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
                    stream: _reportsStream,
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
                                onTap: () => context.push('/my-reports'),
                                child: _buildStatCard(
                                  '$totalReports',
                                  context.l10n.profileStatReports,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => context.push('/reports-status'),
                                child: _buildStatCard(
                                  '$verifiedCount',
                                  context.l10n.profileVerified,
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
            _buildSectionHeader(null, context.l10n.profileAccountSettings),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _buildSettingsTile(
                    Icons.person,
                    context.l10n.editProfileDetails,
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
                        context.l10n.biometricLogin,
                        style: GoogleFonts.lexend(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        profile.biometricsEnabled
                            ? context.l10n.enabled
                            : context.l10n.disabled,
                        style: GoogleFonts.lexend(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                        ),
                      ),
                      activeThumbColor: AppColors.primaryRed,
                      value: profile.biometricsEnabled,
                      // The device lock flag is only written through
                      // AuthProvider (it prompts for biometrics first).
                      onChanged: (value) async {
                        final messenger = ScaffoldMessenger.of(context);
                        final l10n = context.l10n;
                        final auth = context.read<app_auth.AuthProvider>();
                        if (value && !await auth.isBiometricAvailable()) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(l10n.biometricsNotAvailable),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        try {
                          await auth.setBiometricEnabled(
                            value,
                            promptReason: l10n.biometricEnablePrompt,
                          );
                          await profile.refreshBiometricsEnabled();
                          if (value) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(l10n.profileBiometricsEnabled),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } on Exception {
                          final message =
                              BiometricService.messageFor(
                                BiometricService().lastErrorCode,
                              )?.call(l10n) ??
                              (BiometricService().lastErrorCode == null
                                  ? l10n.profileBiometricChangeFailed
                                  : null);
                          if (message != null) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(message),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Consumer<LanguageProvider>(
                    builder: (context, languageProvider, _) =>
                        _buildSettingsTile(
                          Icons.language,
                          context.l10n.languagePreference,
                          subtitle:
                              LanguageProvider.nativeNames[languageProvider
                                  .selectedLanguage] ??
                              languageProvider.selectedLanguage,
                          // A sheet, not push('/settings'): Profile is often
                          // opened from Settings already.
                          onTap: () => showLanguageSelectorSheet(
                            context,
                            languageProvider,
                          ),
                        ),
                  ),
                  const SizedBox(height: 8),
                  _buildSettingsTile(
                    Icons.sync,
                    context.l10n.offlineDataSync,
                    subtitle: context.l10n.upToDate,
                    subtitleColor: AppColors.successGreen,
                    onTap: () async {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            context.l10n.profileSyncingOffline,
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
                          SnackBar(
                            content: Text(context.l10n.profileSyncComplete),
                            backgroundColor: AppColors.successGreen,
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  _buildSettingsTile(
                    Icons.assignment_outlined,
                    context.l10n.myReports,
                    onTap: () => context.push('/my-reports'),
                  ),
                  if (RemoteConfigService().featureFlagPeerChat) ...[
                    const SizedBox(height: 8),
                    _buildSettingsTile(
                      Icons.chat_bubble_outline,
                      context.l10n.profileSupportChat,
                      onTap: () => context.push('/chat'),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _buildSettingsTile(
                    Icons.help,
                    context.l10n.helpSupport,
                    onTap: () => context.push('/help'),
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
                    // Offers calls to 112 / the user's emergency contacts;
                    // nothing is sent through the app.
                    onPressed: () => showSosSheet(context),
                    text: context.l10n.profileSosButton,
                    icon: Icons.sos,
                    // Note: Using primary red for SOS to make it prominent
                  ),
                  const SizedBox(height: 16),
                  CustomButton(
                    text: context.l10n.logout,
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

  // Days since registration; '–' while the registration date is unknown.
  Widget _buildDaysActiveCard(ProfileProvider profile) {
    final registered = profile.registrationDate;
    String value = '–';
    if (registered != null) {
      final days = DateTime.now().difference(registered).inDays;
      // Registered today counts as the first day.
      value = '${days <= 0 ? 1 : days}';
    }
    return _buildStatCard(value, context.l10n.profileDaysActive);
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
