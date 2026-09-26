import 'package:climate_app/features/contacts/models/emergency_contact_model.dart';
import 'package:climate_app/features/contacts/providers/emergency_contacts_provider.dart';
import 'package:climate_app/features/contacts/screens/emergency_contacts_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/l10n/app_localizations.dart';

class _EmptyStreamContactsProvider extends ChangeNotifier
    implements EmergencyContactsProvider {
  @override
  Stream<List<EmergencyContact>> getContactsStream() => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  testWidgets('a stream that ends without rows shows the empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<EmergencyContactsProvider>(
        create: (_) => _EmptyStreamContactsProvider(),
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: EmergencyContactsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No contacts found'), findsOneWidget);
  });
}
