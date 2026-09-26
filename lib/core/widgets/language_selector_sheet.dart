import 'package:climate_app/core/providers/language_provider.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:climate_app/core/l10n/l10n.dart';

/// Bottom sheet for choosing the app language (Settings and Profile).
void showLanguageSelectorSheet(
  BuildContext context,
  LanguageProvider provider,
) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      final languages = LanguageProvider.supportedLanguages.keys;
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.languageSelectTitle,
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
