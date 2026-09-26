import 'package:climate_app/core/services/remote_config_service.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/shared/widgets/custom_button.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:climate_app/core/l10n/l10n.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  /// Builds the support mailto link. The query is encoded with
  /// [Uri.encodeComponent] (spaces as %20): `Uri(queryParameters:)` encodes
  /// spaces as '+', which mail apps show literally.
  static Uri supportMailUri({
    required String address,
    required String subject,
    required String body,
  }) {
    final query =
        'subject=${Uri.encodeComponent(subject)}'
        '&body=${Uri.encodeComponent(body)}';
    return Uri.parse('mailto:$address?$query');
  }

  Future<void> _contactSupport(BuildContext context) async {
    final l10n = context.l10n;
    // Admin-managed (app_settings.support_email).
    final supportEmail = RemoteConfigService().supportEmail;
    final uri = supportMailUri(
      address: supportEmail,
      subject: l10n.helpSupportEmailSubject,
      body: l10n.helpSupportEmailBody,
    );
    var launched = false;
    try {
      launched = await launchUrl(uri);
    } on Exception catch (e) {
      debugPrint('Could not open email app: $e');
    }
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.helpNoEmailApp(supportEmail))),
      );
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
          context.l10n.helpSupport,
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.helpFaqTitle,
              style: GoogleFonts.lexend(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            _buildExpansionTile(
              context.l10n.helpFaqReportQ,
              context.l10n.helpFaqReportA,
            ),
            _buildExpansionTile(
              context.l10n.helpFaqColorsQ,
              context.l10n.helpFaqColorsA,
            ),
            _buildExpansionTile(
              context.l10n.helpFaqOfflineQ,
              context.l10n.helpFaqOfflineA,
            ),
            _buildExpansionTile(
              context.l10n.helpFaqVerifyQ,
              context.l10n.helpFaqVerifyA,
            ),
            const SizedBox(height: 32),
            Text(
              context.l10n.helpStillNeedHelp,
              style: GoogleFonts.lexend(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            CustomButton(
              text: context.l10n.pendingContactSupport,
              icon: Icons.email_outlined,
              onPressed: () => _contactSupport(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpansionTile(String title, String content) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ExpansionTile(
        title: Text(
          title,
          style: GoogleFonts.lexend(
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              content,
              style: GoogleFonts.lexend(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
