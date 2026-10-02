import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:climate_app/core/data/mvp_locations_data.dart';

/// `functions/cradi/src/data/locations.json` is what the `write` Function
/// validates a report's state, LGA and ward against — the check that
/// replaces the two dropped foreign-key tables. A Function cannot read
/// Dart, so the list is exported; an export that falls behind the app
/// means a ward the user can pick on the form and the server then
/// rejects, which looks like a broken app and is a stale file.
void main() {
  test('the Function\'s location list matches the app\'s', () {
    final file = File('functions/cradi/src/data/locations.json');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'Run: dart run functions/cradi/tools/export_locations.dart',
    );

    final exported = (jsonDecode(file.readAsStringSync()) as Map)
        .map<String, Map<String, List<String>>>(
          (state, lgas) => MapEntry(
            state as String,
            (lgas as Map).map<String, List<String>>(
              (lga, wards) =>
                  MapEntry(lga as String, (wards as List).cast<String>()),
            ),
          ),
        );

    final expected = <String, Map<String, List<String>>>{};
    for (final lga in MVPLocationsData.allLGAs) {
      expected
          .putIfAbsent(lga.state, () => <String, List<String>>{})
          .putIfAbsent(lga.name, () => <String>[])
          .addAll(lga.wards.map((w) => w.name));
    }

    expect(
      exported,
      expected,
      reason:
          'Stale export. Run: '
          'dart run functions/cradi/tools/export_locations.dart',
    );
  });

  test('the export really covers the three states and 584 wards', () {
    // Guards the test above from passing because both sides are empty.
    final exported =
        jsonDecode(
              File(
                'functions/cradi/src/data/locations.json',
              ).readAsStringSync(),
            )
            as Map;
    final lgas = exported.values.fold<int>(0, (n, l) => n + (l as Map).length);
    final wards = exported.values.fold<int>(
      0,
      (n, l) =>
          n + (l as Map).values.fold<int>(0, (m, w) => m + (w as List).length),
    );
    expect(exported.keys, unorderedEquals(['Benue', 'Nasarawa', 'Plateau']));
    expect(lgas, 53);
    expect(wards, 584);
  });
}
