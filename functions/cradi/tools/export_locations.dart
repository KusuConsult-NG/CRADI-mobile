// Regenerates `functions/cradi/src/data/locations.json` from the app's own
// location data, which is the only source of truth for it.
//
//   dart run functions/cradi/tools/export_locations.dart
//
// The `write` Function validates state/lga/ward against this file — it is
// what replaces the two dropped foreign-key tables (`nigeria_states`,
// `nigeria_lgas`), whose whole job was that check. A Function cannot read
// Dart, so the data is exported; `test/unit/locations_export_test.dart`
// fails if the export falls behind the source.
import 'dart:convert';
import 'dart:io';

import 'package:climate_app/core/data/mvp_locations_data.dart';

void main() {
  final out = <String, Map<String, List<String>>>{};
  for (final lga in MVPLocationsData.allLGAs) {
    out
        .putIfAbsent(lga.state, () => <String, List<String>>{})
        .putIfAbsent(lga.name, () => <String>[])
        .addAll(lga.wards.map((w) => w.name));
  }
  final file = File('functions/cradi/src/data/locations.json');
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(out)}\n',
  );
  final wards = out.values
      .expand((lgas) => lgas.values)
      .fold<int>(0, (n, w) => n + w.length);
  stdout.writeln(
    'Wrote ${file.path}: ${out.length} states, '
    '${out.values.fold<int>(0, (n, l) => n + l.length)} LGAs, $wards wards',
  );
}
