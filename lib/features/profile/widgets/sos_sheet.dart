import 'package:climate_app/core/constants/emergency.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/features/contacts/models/emergency_contact_model.dart';
import 'package:climate_app/features/contacts/providers/emergency_contacts_provider.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:climate_app/core/l10n/l10n.dart';

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
  final provider = context.read<EmergencyContactsProvider>();
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
              context.l10n.sosTitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.lexend(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.sosBody,
              textAlign: TextAlign.center,
              style: GoogleFonts.lexend(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            _CallTile(
              icon: Icons.local_hospital,
              title: context.l10n.sosCallEmergency(kNationalEmergencyNumber),
              subtitle: context.l10n.sosNationalNumber,
              phone: kNationalEmergencyNumber,
              hostContext: context,
            ),
            SosContactsList(load: provider.fetchContacts, hostContext: context),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(sheetContext),
              child: Text(context.l10n.close),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The user's own emergency contacts in the SOS sheet. A failed load
/// (e.g. offline) is shown as such, with a retry, instead of as "no
/// contacts".
class SosContactsList extends StatefulWidget {
  const SosContactsList({
    super.key,
    required this.load,
    required this.hostContext,
  });

  /// Loads the contacts; throws when they could not be loaded.
  final Future<List<EmergencyContact>> Function() load;

  /// The screen's context (see [_CallTile.hostContext]).
  final BuildContext hostContext;

  @override
  State<SosContactsList> createState() => _SosContactsListState();
}

class _SosContactsListState extends State<SosContactsList> {
  late Future<List<EmergencyContact>> _future = widget.load();

  void _retry() {
    final future = widget.load();
    setState(() {
      _future = future;
    });
  }

  Widget _message(String text) => Padding(
    padding: const EdgeInsets.all(12),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: GoogleFonts.lexend(fontSize: 12, color: AppColors.textSecondary),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<EmergencyContact>>(
      future: _future,
      builder: (_, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _message(context.l10n.sosContactsLoadError),
              TextButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh),
                label: Text(context.l10n.retry),
              ),
            ],
          );
        }
        final contacts = (snapshot.data ?? const <EmergencyContact>[])
            .where((c) => c.phone.trim().isNotEmpty)
            .take(5)
            .toList();
        if (contacts.isEmpty) {
          return _message(context.l10n.sosNoContacts);
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in contacts)
              _CallTile(
                icon: Icons.person,
                title: context.l10n.sosCallContact(c.name),
                subtitle: c.role.isNotEmpty
                    ? context.l10n.sosContactSubtitle(c.role, c.phone)
                    : c.phone,
                phone: c.phone,
                hostContext: widget.hostContext,
              ),
          ],
        );
      },
    );
  }
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
              content: Text(hostContext.l10n.sosDialFailed(phone)),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
    );
  }
}
