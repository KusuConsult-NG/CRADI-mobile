import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:climate_app/core/theme/app_colors.dart';

class OSMLocationPicker extends StatelessWidget {
  final LatLng initialPosition;
  final Function(LatLng)? onPositionChanged;
  final bool isInteractive;

  const OSMLocationPicker({
    super.key,
    required this.initialPosition,
    this.onPositionChanged,
    this.isInteractive = true,
  });

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: MapOptions(
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
          userAgentPackageName: 'com.kusuconsult.cradimobile',
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
