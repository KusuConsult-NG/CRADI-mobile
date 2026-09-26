import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:climate_app/core/theme/app_colors.dart';

class OSMLocationPicker extends StatelessWidget {
  final LatLng initialPosition;
  final Function(LatLng)? onPositionChanged;
  final bool isInteractive;
  final MapController? mapController;

  /// Called once the map has rendered; the [mapController] must not be used
  /// before that.
  final VoidCallback? onMapReady;

  const OSMLocationPicker({
    super.key,
    required this.initialPosition,
    this.onPositionChanged,
    this.isInteractive = true,
    this.mapController,
    this.onMapReady,
  });

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        onMapReady: onMapReady,
        initialCenter: initialPosition,
        initialZoom: 15.0,
        interactionOptions: InteractionOptions(
          flags: isInteractive ? InteractiveFlag.all : InteractiveFlag.none,
        ),
        onTap: isInteractive
            ? (tapPosition, point) {
                if (onPositionChanged != null) {
                  onPositionChanged!(point);
                }
              }
            : null,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.westgatestratagem.climate_app.climate_app',
        ),
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution(
              'OpenStreetMap contributors',
              onTap: () {}, // Can add link launcher here if needed
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: initialPosition,
              width: 40,
              height: 40,
              child: const Icon(
                Icons.location_on,
                color: AppColors.primaryRed,
                size: 40,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
