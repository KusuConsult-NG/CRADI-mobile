import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:developer' as developer;
import 'package:climate_app/core/data/mvp_locations_data.dart';

/// Service for handling geolocation operations
class GeolocationService {
  ///Check if location services are enabled
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Check and request location permissions
  Future<bool> checkAndRequestPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        developer.log('Location permissions are denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      developer.log('Location permissions are permanently denied');
      return false;
    }

    return true;
  }

  /// How long to wait for a fresh fix before falling back to the last known
  /// position. Without a limit the request can hang forever indoors.
  static const Duration positionTimeLimit = Duration(seconds: 20);

  /// Human-readable reason of the last [getCurrentPosition] failure (or of a
  /// fallback to a stale position); null when the last call got a fresh fix.
  String? lastErrorMessage;

  /// Get current position.
  ///
  /// Waits at most [positionTimeLimit] for a fix, then falls back to the
  /// device's last known position. Returns null (with [lastErrorMessage]
  /// set) when neither is available.
  Future<Position?> getCurrentPosition() async {
    lastErrorMessage = null;
    try {
      // Check if location service is enabled
      final serviceEnabled = await isLocationServiceEnabled();
      if (!serviceEnabled) {
        developer.log('Location services are disabled');
        lastErrorMessage =
            'Location services are turned off. Please enable GPS.';
        return null;
      }

      // Check permissions
      final hasPermission = await checkAndRequestPermission();
      if (!hasPermission) {
        lastErrorMessage = 'Location permission was denied.';
        return null;
      }
    } on Exception catch (e) {
      developer.log('Error checking location availability: $e');
      lastErrorMessage = 'Could not access location services.';
      return null;
    }

    return fetchPositionWithFallback(
      current: () => Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
          timeLimit: positionTimeLimit,
        ),
      ),
      lastKnown: () => Geolocator.getLastKnownPosition(),
    );
  }

  /// Fetches a fresh position via [current] (which must enforce its own time
  /// limit); on failure/timeout falls back to [lastKnown]. Exposed for tests.
  Future<Position?> fetchPositionWithFallback({
    required Future<Position> Function() current,
    required Future<Position?> Function() lastKnown,
  }) async {
    lastErrorMessage = null;
    Object? failure;
    try {
      final position = await current().timeout(
        positionTimeLimit + const Duration(seconds: 5),
      );
      developer.log(
        'Got position: ${position.latitude}, ${position.longitude}',
      );
      return position;
    } on Exception catch (e) {
      failure = e;
      developer.log('Error getting position: $e');
    }

    try {
      final last = await lastKnown();
      if (last != null) {
        lastErrorMessage =
            'Could not get a fresh GPS fix; using your last known location.';
        return last;
      }
    } on Exception catch (e) {
      developer.log('Error getting last known position: $e');
    }

    lastErrorMessage = failure is TimeoutException
        ? 'Timed out waiting for a GPS signal. Move to an open area and '
              'try again, or choose your location manually.'
        : 'Could not determine your location. Please try again or choose '
              'your location manually.';
    return null;
  }

  /// Format coordinates for display
  String formatCoordinates(double latitude, double longitude) {
    final latDirection = latitude >= 0 ? 'N' : 'S';
    final lonDirection = longitude >= 0 ? 'E' : 'W';

    return '${latitude.abs().toStringAsFixed(4)}° $latDirection | ${longitude.abs().toStringAsFixed(4)}° $lonDirection';
  }

  /// Get location details using reverse geocoding.
  /// Validates LGA against MVP location data to avoid showing
  /// non-LGA locality names (e.g., village names like "Bar Jirgi Summa").
  Future<Map<String, String>> getLocationDetails(
    double latitude,
    double longitude,
  ) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        latitude,
        longitude,
      );

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;

        // Detect state from administrativeArea
        final rawState = place.administrativeArea ?? '';
        // Normalize: "Plateau State" → "Plateau"
        final stateName = rawState.replaceAll(' State', '').trim();

        // Candidate LGA names from geocoding (in priority order)
        final candidates = <String>[
          if (place.subAdministrativeArea != null) place.subAdministrativeArea!,
          if (place.locality != null) place.locality!,
        ];

        // Try to match against known MVP LGAs for this state
        String resolvedLga = 'Select LGA';
        if (stateName.isNotEmpty) {
          final knownLGAs = MVPLocationsData.getLGAsForState(stateName);
          if (knownLGAs.isNotEmpty) {
            for (final candidate in candidates) {
              final lowerCandidate = candidate.toLowerCase().trim();
              // Exact match
              final exactMatch = knownLGAs.cast<String?>().firstWhere(
                (lga) => lga!.toLowerCase() == lowerCandidate,
                orElse: () => null,
              );
              if (exactMatch != null) {
                resolvedLga = exactMatch;
                break;
              }
              // Partial match (candidate contains LGA name or vice versa)
              final partialMatch = knownLGAs.cast<String?>().firstWhere(
                (lga) =>
                    lga!.toLowerCase().contains(lowerCandidate) ||
                    lowerCandidate.contains(lga.toLowerCase()),
                orElse: () => null,
              );
              if (partialMatch != null) {
                resolvedLga = partialMatch;
                break;
              }
            }
          }
        }

        // If no MVP match, fall back to best available geocoded value
        if (resolvedLga == 'Select LGA' && candidates.isNotEmpty) {
          // Use subAdministrativeArea as it's more likely to be an LGA
          resolvedLga = place.subAdministrativeArea ?? 'Select LGA';
        }

        final ward = place.subLocality ?? place.thoroughfare ?? 'Select Ward';

        developer.log(
          'Reverse geocode: state=$stateName, '
          'candidates=$candidates, resolved LGA=$resolvedLga, ward=$ward',
          name: 'GeolocationService',
        );

        return {
          'lga': resolvedLga,
          'ward': ward,
          'state': stateName,
          'address':
              '${place.street ?? ''}, ${place.locality ?? ''}, ${place.administrativeArea ?? ''}',
        };
      }

      return {
        'lga': 'Select LGA',
        'ward': 'Select Ward',
        'state': '',
        'address':
            'Lat: ${latitude.toStringAsFixed(4)}, Lon: ${longitude.toStringAsFixed(4)}',
      };
    } on Exception catch (e) {
      developer.log('Error in reverse geocoding: $e');
      return {
        'lga': 'Select LGA',
        'ward': 'Select Ward',
        'state': '',
        'address':
            'Lat: ${latitude.toStringAsFixed(4)}, Lon: ${longitude.toStringAsFixed(4)}',
      };
    }
  }

  /// Get coordinates from address/location name
  Future<Position?> getCoordinatesFromAddress(String locationName) async {
    try {
      List<Location> locations = await locationFromAddress(locationName);
      if (locations.isNotEmpty) {
        final loc = locations.first;
        return Position(
          latitude: loc.latitude,
          longitude: loc.longitude,
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          heading: 0,
          speed: 0,
          speedAccuracy: 0,
          altitudeAccuracy: 0,
          headingAccuracy: 0,
        );
      }
      return null;
    } on Exception catch (e) {
      developer.log(
        'Error geocoding location: $e',
      ); // Assuming ErrorHandler.logError is not defined in this context, keeping developer.log for consistency.
      return null;
    }
  }

  Future<bool> isAccuracySufficient(Position position) async {
    // Consider accuracy sufficient if it's within 50 meters
    return position.accuracy <= 50.0;
  }
}
