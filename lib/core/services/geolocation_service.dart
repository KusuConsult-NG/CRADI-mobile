import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:developer' as developer;

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

  /// Get current position
  Future<Position?> getCurrentPosition() async {
    try {
      // Check if location service is enabled
      final serviceEnabled = await isLocationServiceEnabled();
      if (!serviceEnabled) {
        developer.log('Location services are disabled');
        return null;
      }

      // Check permissions
      final hasPermission = await checkAndRequestPermission();
      if (!hasPermission) {
        return null;
      }

      // Get position
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      );

      developer.log(
        'Got position: ${position.latitude}, ${position.longitude}',
      );
      return position;
    } on Exception catch (e) {
      developer.log('Error getting position: $e');
      return null;
    }
  }

  /// Format coordinates for display
  String formatCoordinates(double latitude, double longitude) {
    final latDirection = latitude >= 0 ? 'N' : 'S';
    final lonDirection = longitude >= 0 ? 'E' : 'W';

    return '${latitude.abs().toStringAsFixed(4)}° $latDirection | ${longitude.abs().toStringAsFixed(4)}° $lonDirection';
  }

  /// Get location details using reverse geocoding
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

        // Extract locality (LGA) and sublocality (Ward)
        final lga =
            place.locality ?? place.subAdministrativeArea ?? 'Unknown LGA';
        final ward = place.subLocality ?? place.thoroughfare ?? 'Unknown Ward';

        return {
          'lga': lga,
          'ward': ward,
          'address':
              '${place.street ?? ''}, ${place.locality ?? ''}, ${place.administrativeArea ?? ''}',
        };
      }

      return {
        'lga': 'Could not determine LGA',
        'ward': 'Could not determine Ward',
        'address':
            'Lat: ${latitude.toStringAsFixed(4)}, Lon: ${longitude.toStringAsFixed(4)}',
      };
    } on Exception catch (e) {
      developer.log('Error in reverse geocoding: $e');
      return {
        'lga': 'Unknown LGA',
        'ward': 'Unknown Ward',
        'address':
            'Lat: ${latitude.toStringAsFixed(4)}, Lon: ${longitude.toStringAsFixed(4)}',
      };
    }
  }

  /// Check if location accuracy is sufficient
  Future<bool> isAccuracySufficient(Position position) async {
    // Consider accuracy sufficient if it's within 50 meters
    return position.accuracy <= 50.0;
  }
}
