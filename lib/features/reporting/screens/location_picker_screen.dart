import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/features/reporting/widgets/osm_location_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart';
import 'package:climate_app/core/services/geolocation_service.dart';
import 'package:geolocator/geolocator.dart';

class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  double _severityValue = 3.0; // Default High
  final GeolocationService _geoService = GeolocationService();
  Position? _currentPosition;
  bool _isLoadingLocation = true;
  String _locationError = '';
  String _lga = 'Loading...';
  String _ward = 'Loading...';

  // Severity Configuration
  final Map<int, Map<String, dynamic>> _severityLevels = {
    1: {
      'label': 'Low Severity',
      'color': const Color(0xFF13ec5b),
      'desc': 'Minor issue. No immediate threat.',
    },
    2: {
      'label': 'Medium Severity',
      'color': const Color(0xFFfacc15),
      'desc': 'Moderate issue. Monitor situation.',
    },
    3: {
      'label': 'High Severity',
      'color': const Color(0xFFf97316),
      'desc': 'Significant threat to property or health. Response required.',
    },
    4: {
      'label': 'Critical Severity',
      'color': const Color(0xFFef4444),
      'desc': 'Life-threatening situation. Immediate action required.',
    },
  };

  @override
  void initState() {
    super.initState();
    _fetchCurrentLocation();
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() {
      _isLoadingLocation = true;
      _locationError = '';
    });

    try {
      final position = await _geoService.getCurrentPosition();

      if (position != null) {
        setState(() {
          _currentPosition = position;
          _isLoadingLocation = false;
        });

        // Get location details
        final details = await _geoService.getLocationDetails(
          position.latitude,
          position.longitude,
        );

        setState(() {
          _lga = details['lga'] ?? 'Unknown LGA';
          _ward = details['ward'] ?? 'Unknown Ward';
        });

        // Update reporting provider with coordinates
        if (mounted) {
          context.read<ReportingProvider>().setLocationDetails(
            '${position.latitude},${position.longitude}',
          );
        }
      } else {
        setState(() {
          _isLoadingLocation = false;
          _locationError = 'Unable to get location. Please enable GPS.';
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
          _locationError = 'Location error: ${e.toString()}';
        });
      }
    }
  }

  String _getGpsStatus() {
    if (_isLoadingLocation) return 'ACQUIRING...';
    if (_locationError.isNotEmpty) return 'NO SIGNAL';
    if (_currentPosition == null) return 'NO SIGNAL';

    final accuracy = _currentPosition!.accuracy;
    if (accuracy <= 20) return 'GPS STRONG';
    if (accuracy <= 50) return 'GPS GOOD';
    return 'GPS WEAK';
  }

  Color _getGpsStatusColor() {
    final status = _getGpsStatus();
    if (status == 'GPS STRONG') return Colors.green.shade700;
    if (status == 'GPS GOOD') return Colors.orange.shade700;
    if (status == 'ACQUIRING...') return Colors.blue.shade700;
    return Colors.red.shade700;
  }

  @override
  Widget build(BuildContext context) {
    final severity = _severityLevels[_severityValue.toInt()]!;
    final Color severityColor = severity['color'] as Color;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            size: 20,
            color: AppColors.textPrimary,
          ),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Report Details',
          style: GoogleFonts.lexend(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppColors.background.withValues(alpha: 0.95),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.grey.shade200, height: 1.0),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Severity Section
                  _buildSectionTitle(
                    'Severity Level',
                    'Assess the intensity of the hazard.',
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: severityColor.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.warning,
                                color: severityColor,
                                size: 32,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Selected Level',
                                  style: GoogleFonts.lexend(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade400,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                Text(
                                  severity['label'],
                                  style: GoogleFonts.lexend(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: severityColor,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border(
                              left: BorderSide(color: severityColor, width: 4),
                            ),
                          ),
                          child: Text(
                            severity['desc'],
                            style: GoogleFonts.lexend(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Slider
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: severityColor,
                            inactiveTrackColor: Colors.grey.shade200,
                            thumbColor: Colors.white,
                            overlayColor: severityColor.withValues(alpha: 0.2),
                            trackHeight: 12,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 12,
                              elevation: 4,
                            ),
                          ),
                          child: Slider(
                            value: _severityValue,
                            min: 1,
                            max: 4,
                            divisions: 3,
                            onChanged: (value) {
                              setState(() => _severityValue = value);
                              // Update Provider
                              final severityLabel =
                                  _severityLevels[value.toInt()]!['label']
                                      as String;
                              context.read<ReportingProvider>().setSeverity(
                                severityLabel,
                              );
                            },
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Low',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                              Text(
                                'Med',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                              Text(
                                'High',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                              Text(
                                'Crit',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Location Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionTitle('Incident Location', ''),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _getGpsStatusColor().withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _isLoadingLocation
                                  ? Icons.gps_not_fixed
                                  : Icons.gps_fixed,
                              size: 14,
                              color: _getGpsStatusColor(),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _getGpsStatus(),
                              style: GoogleFonts.lexend(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _getGpsStatusColor(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        // Map Preview
                        SizedBox(
                          height: 200,
                          child: _currentPosition == null
                              ? Container(
                                  color: Colors.grey.shade200,
                                  child: _isLoadingLocation
                                      ? const Center(
                                          child: CircularProgressIndicator(),
                                        )
                                      : Center(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.location_off,
                                                size: 48,
                                                color: Colors.grey.shade400,
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                'Location unavailable',
                                                style: TextStyle(
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                )
                              : Stack(
                                  children: [
                                    OSMLocationPicker(
                                      initialPosition: LatLng(
                                        _currentPosition!.latitude,
                                        _currentPosition!.longitude,
                                      ),
                                      isInteractive: false,
                                      onPositionChanged: (point) {
                                        // Optional: Handle map taps if needed in future
                                      },
                                    ),
                                    Positioned(
                                      bottom: 12,
                                      right: 12,
                                      child: GestureDetector(
                                        onTap: _fetchCurrentLocation,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            boxShadow: const [
                                              BoxShadow(
                                                color: Colors.black12,
                                                blurRadius: 4,
                                              ),
                                            ],
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.my_location,
                                                size: 14,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Refresh',
                                                style: GoogleFonts.lexend(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                        // Details
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildLocationInfo('LGA', _lga),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _buildLocationInfo('WARD', _ward),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Divider(height: 1, color: Colors.grey.shade100),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'COORDINATES',
                                        style: GoogleFonts.lexend(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey.shade400,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _currentPosition != null
                                            ? _geoService.formatCoordinates(
                                                _currentPosition!.latitude,
                                                _currentPosition!.longitude,
                                              )
                                            : (_isLoadingLocation
                                                  ? 'Getting location...'
                                                  : 'No GPS data'),
                                        style: GoogleFonts.robotoMono(
                                          fontSize: 12,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      _showLocationDetailsDialog(context);
                                    },
                                    child: Text(
                                      'View Details',
                                      style: GoogleFonts.lexend(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primaryRed,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: GestureDetector(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (context) {
                            final controller = TextEditingController();
                            return AlertDialog(
                              title: const Text('Enter Location Manually'),
                              content: TextField(
                                controller: controller,
                                decoration: const InputDecoration(
                                  hintText: 'Address or Coordinates',
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    if (controller.text.isNotEmpty) {
                                      context
                                          .read<ReportingProvider>()
                                          .setLocationDetails(controller.text);
                                      // Also verify severity if not set
                                      final severityLabel =
                                          _severityLevels[_severityValue
                                                  .toInt()]!['label']
                                              as String;
                                      context
                                          .read<ReportingProvider>()
                                          .setSeverity(severityLabel);
                                    }
                                    Navigator.pop(context);
                                  },
                                  child: const Text('Set'),
                                ),
                              ],
                            );
                          },
                        );
                      },
                      child: Text(
                        'Location incorrect? Enter manually',
                        style: GoogleFonts.lexend(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                          decoration: TextDecoration.underline,
                          decorationStyle: TextDecorationStyle.dotted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Footer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              border: Border(top: BorderSide(color: Colors.grey.shade100)),
            ),
            child: SafeArea(
              child: ElevatedButton(
                onPressed: () {
                  // Sync Severity
                  final severityLabel =
                      _severityLevels[_severityValue.toInt()]!['label']
                          as String;
                  context.read<ReportingProvider>().setSeverity(severityLabel);

                  // Sync Location if not null (it might have been set by GPS or Manual)
                  // If location provider is null, we should block or warn?
                  // For now, assume flow continues, provider check at end will catch it.
                  // But setting it here ensures "default" value is captured.

                  context.push('/report/details');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryRed,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 4,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Confirm & Continue',
                      style: GoogleFonts.lexend(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.lexend(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        if (subtitle.isNotEmpty)
          Text(
            subtitle,
            style: GoogleFonts.lexend(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
      ],
    );
  }

  Widget _buildLocationInfo(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.lexend(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade400,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.lexend(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  void _showLocationDetailsDialog(BuildContext context) {
    if (_currentPosition == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Location Details',
                  style: GoogleFonts.lexend(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildDetailRow(
              Icons.my_location,
              'Latitude',
              _currentPosition!.latitude.toStringAsFixed(6),
            ),
            const SizedBox(height: 12),
            _buildDetailRow(
              Icons.my_location,
              'Longitude',
              _currentPosition!.longitude.toStringAsFixed(6),
            ),
            const SizedBox(height: 12),
            _buildDetailRow(
              Icons.gps_fixed,
              'Accuracy',
              '${_currentPosition!.accuracy.toStringAsFixed(1)} meters',
            ),
            const SizedBox(height: 12),
            _buildDetailRow(
              Icons.height,
              'Altitude',
              '${_currentPosition!.altitude.toStringAsFixed(1)} m',
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Close',
                  style: GoogleFonts.lexend(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: AppColors.primaryRed),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.lexend(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
            ),
            Text(
              value,
              style: GoogleFonts.lexend(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
