import 'package:climate_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:climate_app/core/l10n/l10n.dart';

class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key});

  /// This build's version, read once from the platform.
  static final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: AppColors.primaryRed,
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
          context.l10n.aboutApp,
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
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/ewer_logo.jpg',
                width: 120,
                height: 120,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.shield,
                  size: 100,
                  color: AppColors.primaryRed,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                context.l10n.aboutAppName,
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.aboutTagline,
                style: GoogleFonts.lexend(
                  fontSize: 16,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 32),
              FutureBuilder<PackageInfo>(
                future: _packageInfo,
                builder: (context, snapshot) {
                  final info = snapshot.data;
                  if (info == null) {
                    // Loading, or unavailable on this platform: show no
                    // version rather than a made-up one.
                    return SizedBox(
                      height: 36,
                      child: snapshot.connectionState == ConnectionState.waiting
                          ? const Center(
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : null,
                    );
                  }
                  final build = info.buildNumber.trim();
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      build.isEmpty
                          ? context.l10n.aboutVersionOnly(info.version)
                          : context.l10n.aboutVersion(info.version, build),
                      style: GoogleFonts.lexend(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 48),
              Text(
                context.l10n.aboutCopyright(DateTime.now().year.toString()),
                style: GoogleFonts.lexend(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              ),
              const SizedBox(height: 16),
              // No Terms of Service text exists in the app yet; only the
              // NDPA privacy notice is shown.
              TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: Text(
                      context.l10n.aboutPrivacyPolicy,
                      style: GoogleFonts.lexend(fontWeight: FontWeight.bold),
                    ),
                    content: SingleChildScrollView(
                      child: Text(
                        context.l10n.privacyNoticeText,
                        style: GoogleFonts.lexend(fontSize: 13, height: 1.5),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: Text(context.l10n.close),
                      ),
                    ],
                  ),
                ),
                child: Text(
                  context.l10n.aboutPrivacyPolicy,
                  style: GoogleFonts.lexend(color: AppColors.primaryRed),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
