import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/features/contacts/models/emergency_contact_model.dart';
import 'package:climate_app/features/contacts/providers/emergency_contacts_provider.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Nigeria's national emergency number.
const String kNationalEmergencyNumber = '112';

/// `tel:` link for [phone], with spaces, dashes and brackets removed.
Uri telUri(String phone) =>
    Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[\s\-()]'), ''));

/// Opens the phone dialer for [phone]. Returns false when no app could
/// handle it. canLaunchUrl is not used as a gate: it can report false for
/// tel: even when dialing works (e.g. missing query declarations).
Future<bool> dialNumber(String phone) async {
  try {
    return await launchUrl(telUri(phone));
  } on Exception catch (e) {
    debugPrint('Could not open dialer: $e');
    return false;
  }
}

/// SOS sheet: lets the user call the national emergency number or one of
/// their own emergency contacts. It never sends anything on its own, so it
/// never claims an alert was sent.
Future<void> showSosSheet(BuildContext context) {
  final contactsFuture = context
      .read<EmergencyContactsProvider>()
      .getContacts();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'SOS Emergency',
              textAlign: TextAlign.center,
              style: GoogleFonts.lexend(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Call for help directly. This does not send an alert '
              'through the app.',
              textAlign: TextAlign.center,
              style: GoogleFonts.lexend(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            _CallTile(
              icon: Icons.local_hospital,
              title: 'Call Emergency ($kNationalEmergencyNumber)',
              subtitle: 'National emergency number',
              phone: kNationalEmergencyNumber,
              hostContext: context,
            ),
            FutureBuilder<List<EmergencyContact>>(
              future: contactsFuture,
              builder: (_, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final contacts = (snapshot.data ?? const <EmergencyContact>[])
                    .where((c) => c.phone.trim().isNotEmpty)
                    .take(5)
                    .toList();
                if (contacts.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'No personal emergency contacts saved yet. '
                      'Add them under Emergency Contacts.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.lexend(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  );
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final c in contacts)
                      _CallTile(
                        icon: Icons.person,
                        title: 'Call ${c.name}',
                        subtitle: c.role.isNotEmpty
                            ? '${c.role} · ${c.phone}'
                            : c.phone,
                        phone: c.phone,
                        hostContext: context,
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(sheetContext),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CallTile extends StatelessWidget {
  const _CallTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.phone,
    required this.hostContext,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String phone;

  /// The screen's context, still mounted after the sheet closes, for the
  /// failure snackbar.
  final BuildContext hostContext;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primaryRed),
      title: Text(title, style: GoogleFonts.lexend(fontSize: 15)),
      subtitle: Text(subtitle, style: GoogleFonts.lexend(fontSize: 12)),
      trailing: const Icon(Icons.call, color: AppColors.primaryRed),
      onTap: () async {
        Navigator.pop(context);
        final ok = await dialNumber(phone);
        if (!ok && hostContext.mounted) {
          ScaffoldMessenger.of(hostContext).showSnackBar(
            SnackBar(
              content: Text('Could not open the phone app. Dial $phone.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
    );
  }
}
