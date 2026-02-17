import 'package:flutter_test/flutter_test.dart';
import 'package:climate_app/core/data/mvp_locations_data.dart';
import 'package:climate_app/core/data/nigeria_locations_data.dart';

void main() {
  group('Location Data Verification', () {
    test(
      'NigeriaLocationsData.focalStates should only contain Benue, Nasarawa, Plateau',
      () {
        final states = NigeriaLocationsData.focalStates;
        expect(states.length, 3);
        expect(states, containsAll(['Benue', 'Nasarawa', 'Plateau']));
      },
    );

    test(
      'MVPLocationsData.getAllStates() should only contain Benue, Nasarawa, Plateau',
      () {
        final states = MVPLocationsData.getAllStates();
        expect(states.length, 3);
        expect(states, containsAll(['Benue', 'Nasarawa', 'Plateau']));
      },
    );

    test('Benue state should have LGAs', () {
      final lgas = MVPLocationsData.getLGAsForState('Benue');
      expect(lgas, isNotEmpty);
      expect(lgas, contains('Gboko')); // Sample check
      expect(lgas, contains('Makurdi')); // Sample check
    });

    test('Nasarawa state should have LGAs', () {
      final lgas = MVPLocationsData.getLGAsForState('Nasarawa');
      expect(lgas, isNotEmpty);
      expect(lgas, contains('Lafia')); // Sample check
      expect(lgas, contains('Keffi')); // Sample check
    });

    test('Plateau state should have LGAs', () {
      final lgas = MVPLocationsData.getLGAsForState('Plateau');
      expect(lgas, isNotEmpty);
      expect(lgas, contains('Jos North')); // Sample check
      expect(lgas, contains('Jos South')); // Sample check
    });

    test(
      'Verify NigeriaLocationsData.getLGAsForState matches for focal states',
      () {
        // This checks if NigeriaLocationsData also has data for these states
        final benueLgas = NigeriaLocationsData.getLGAsForState('Benue');
        expect(benueLgas, isNotEmpty);

        final nasarawaLgas = NigeriaLocationsData.getLGAsForState('Nasarawa');
        expect(nasarawaLgas, isNotEmpty);

        final plateauLgas = NigeriaLocationsData.getLGAsForState('Plateau');
        expect(plateauLgas, isNotEmpty);
      },
    );
  });
}
