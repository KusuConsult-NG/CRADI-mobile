// An alert must never name an LGA without the state it is in.
//
// LGA names repeat across states — Bassa, Ifelodun, Irepodun, Nasarawa, Obi
// and Surulere each belong to two different states — so an LGA on its own does
// not identify a place. Since migration 20260927080000 the database refuses
// that shape (check constraint `alerts_target_lga_needs_state`, plus foreign
// keys into public.nigeria_states / public.nigeria_lgas), so the admin screen
// must never be able to produce it.
import 'package:climate_app/core/data/mvp_locations_data.dart';
import 'package:climate_app/core/data/nigeria_locations_data.dart';
import 'package:climate_app/features/admin/screens/admin_alerts_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('alertTargetFields', () {
    test('a state and an LGA are sent together', () {
      expect(alertTargetFields('Nasarawa', 'Obi'), {
        'targetLga': 'Obi',
        'targetState': 'Nasarawa',
      });
    });

    test("'All' with a state targets every LGA of that state", () {
      expect(alertTargetFields('Benue', 'All'), {
        'targetLga': 'All',
        'targetState': 'Benue',
      });
    });

    test('no state means everyone, everywhere', () {
      expect(alertTargetFields(null, 'All'), {'targetLga': 'All'});
      expect(alertTargetFields('', 'All'), {'targetLga': 'All'});
      expect(alertTargetFields('   ', 'All'), {'targetLga': 'All'});
    });

    test(
      'an LGA left over from a cleared state is dropped, never sent alone',
      () {
        // The picker resets the LGA when the state changes, but even if a stale
        // 'Obi' survived, clearing the state must widen to 'All' explicitly
        // rather than send an LGA the database (and nobody else) can place.
        for (final stale in ['Obi', 'Makurdi', 'Bassa']) {
          final fields = alertTargetFields(null, stale);
          expect(fields['targetState'], isNull, reason: stale);
          expect(fields['targetLga'], 'All', reason: stale);
        }
      },
    );

    test(
      'never emits an LGA without a state, for any pairing the form allows',
      () {
        for (final state in [null, ...MVPLocationsData.getAllStates()]) {
          for (final lga in [
            'All',
            '',
            ...MVPLocationsData.getLGAsForState(state ?? ''),
          ]) {
            final fields = alertTargetFields(state, lga);
            final targetLga = fields['targetLga']!;
            final targetState = fields['targetState'];
            expect(
              targetState != null || targetLga == 'All',
              isTrue,
              reason: 'state=$state lga=$lga produced $fields',
            );
            // Whatever it sends must be a pair the database will accept.
            if (targetState != null && targetLga != 'All') {
              expect(
                NigeriaLocationsData.isValidLGA(targetState, targetLga),
                isTrue,
                reason: '$targetLga is not an LGA of $targetState',
              );
            }
          }
        }
      },
    );
  });

  test('the six ambiguous LGA names are why the state is required', () {
    final states = <String, Set<String>>{};
    for (final loc in NigeriaLocationsData.locations) {
      for (final lga in loc.lgas) {
        states.putIfAbsent(lga, () => <String>{}).add(loc.state);
      }
    }
    final ambiguous =
        states.entries
            .where((e) => e.value.length > 1)
            .map((e) => e.key)
            .toList()
          ..sort();
    expect(ambiguous, [
      'Bassa',
      'Ifelodun',
      'Irepodun',
      'Nasarawa',
      'Obi',
      'Surulere',
    ]);
  });
}
