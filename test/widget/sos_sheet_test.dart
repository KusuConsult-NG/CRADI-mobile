import 'package:climate_app/features/contacts/models/emergency_contact_model.dart';
import 'package:climate_app/features/profile/widgets/sos_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:climate_app/l10n/app_localizations.dart';

void main() {
  testWidgets('a failed contacts load shows an error with retry', (
    tester,
  ) async {
    var calls = 0;
    Future<List<EmergencyContact>> load() async {
      calls++;
      if (calls == 1) throw Exception('offline');
      return const [];
    }

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) =>
                SosContactsList(load: load, hostContext: context),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't load your contacts"), findsOneWidget);
    expect(find.textContaining('No personal emergency contacts'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(
      find.textContaining('No personal emergency contacts'),
      findsOneWidget,
    );
  });
}
