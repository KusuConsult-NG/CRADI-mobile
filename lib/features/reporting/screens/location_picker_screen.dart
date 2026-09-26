import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/features/reporting/widgets/osm_location_picker.dart';
import 'package:climate_app/core/data/mvp_locations_data.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart';
import 'package:climate_app/core/services/geolocation_service.dart';
import 'package:climate_app/core/services/permission_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:climate_app/shared/widgets/custom_button.dart';

import 'package:climate_app/features/profile/providers/profile_provider.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:climate_app/l10n/app_localizations.dart';

enum _PositionSource { gps, manual, geocoded }

class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final MapController _mapController = MapController();
  // Slider position (1-4). Initialised from the severity chosen on the
  // previous screen so the user's choice is not overwritten.
  double _severityValue = 3.0;
  final GeolocationService _geoService = GeolocationService();
  Position? _currentPosition;

  /// Where [_currentPosition] came from. Only [_PositionSource.gps] is a real
  /// fix; a geocoded area centre must never replace a GPS fix or a point the
  /// user tapped.
  _PositionSource? _positionSource;

  /// FlutterMap asserts if the controller is used before the map rendered.
  bool _mapReady = false;
  bool _isLoadingLocation = true;
  String _locationError = '';
  String _lga = 'Loading...';
  String _ward = 'Loading...';

  // Ward & LGA Selection (for MVP)
  String? _selectedState;
  String? _selectedLGA;
  String? _selectedWard;

  // Severity Configuration
  final Map<int, Map<String, dynamic>> _severityLevels = {
    1: {
      'label': 'Low Severity',
      'value': 'low',
      'color': const Color(0xFF13ec5b),
      'desc': 'Minor issue. No immediate threat.',
    },
    2: {
      'label': 'Medium Severity',
      'value': 'medium',
      'color': const Color(0xFFfacc15),
      'desc': 'Moderate issue. Monitor situation.',
    },
    3: {
      'label': 'High Severity',
      'value': 'high',
      'color': const Color(0xFFf97316),
      'desc': 'Significant threat to property or health. Response required.',
    },
    4: {
      'label': 'Critical Severity',
      'value': 'critical',
      'color': const Color(0xFFef4444),
      'desc': 'Life-threatening situation. Immediate action required.',
    },
  };

  @override
  void initState() {
    super.initState();
    // Keep the severity chosen on the SeveritySelectionScreen.
    final chosen = normalizeSeverity(
      context.read<ReportingProvider>().severity,
    );
    if (chosen != null) {
      _severityValue =
          (SeverityLevel.values.indexWhere((l) => l.name == chosen) + 1)
              .toDouble();
    }
    // Delay location fetch to ensure context is ready for Dialogs (PermissionService)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchCurrentLocation();
      _loadProfileLocation();
    });
  }

  /// Pre-selects the dropdowns from the profile. Every pre-selected value
  /// must be one of the dropdown's items (a DropdownButtonFormField asserts
  /// otherwise), so values are validated against the MVP location data;
  /// blank or unknown values are left unselected.
  void _loadProfileLocation() {
    final profile = context.read<ProfileProvider>();
    final reporting = context.read<ReportingProvider>();

    String? clean(String? v) {
      final t = v?.trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    String? match(String? value, List<String> options) {
      final v = clean(value)?.toLowerCase();
      if (v == null) return null;
      for (final o in options) {
        if (o.toLowerCase() == v) return o;
      }
      return null;
    }

    final states = MVPLocationsData.getAllStates();
    // A report already in progress wins over the profile.
    final zone = clean(profile.monitoringZone);
    final state =
        match(reporting.state, states) ??
        match(profile.state, states) ??
        // Monitoring zones look like "Benue State" or "Makurdi, Benue".
        match(zone?.replaceAll(RegExp(r'\s+State$'), ''), states) ??
        match(zone?.split(',').last, states);
    final lga = state == null
        ? null
        : match(
            reporting.lga ?? profile.lga,
            MVPLocationsData.getLGAsForState(state),
          );
    final ward = lga == null
        ? null
        : match(
            reporting.ward ?? profile.ward,
            MVPLocationsData.getWardsForLGA(lga, state: state),
          );

    setState(() {
      _selectedState = state;
      _selectedLGA = lga;
      _selectedWard = ward;
    });
    // The provider is only updated from explicit selections / Confirm.
  }

  Future<void> _fetchCurrentLocation() async {
    if (!mounted) return;
    setState(() {
      _isLoadingLocation = true;
      _locationError = '';
    });

    try {
      // Request permission with rationale first
      final hasPermission = await PermissionService().requestLocation(context);
      if (!mounted) return;

      if (!hasPermission) {
        if (mounted) {
          setState(() {
            _isLoadingLocation = false;
            _locationError = AppLocalizations.of(
              context,
            )!.locationPermissionDenied;
          });
        }
        return;
      }

      final position = await _geoService.getCurrentPosition();
      if (!mounted) return;

      if (position != null) {
        setState(() {
          _currentPosition = position;
          _positionSource = _PositionSource.gps;
          _isLoadingLocation = false;
        });
        _moveCamera(LatLng(position.latitude, position.longitude));
        // e.g. fell back to the last known position after a timeout.
        final notice = _geoService.lastErrorMessage;
        if (notice != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(notice)));
        }

        // Get location details
        final details = await _geoService.getLocationDetails(
          position.latitude,
          position.longitude,
        );
        if (!mounted) return;

        setState(() {
          _lga = details['lga'] ?? 'Unknown LGA';
          _ward = details['ward'] ?? 'Unknown Ward';
        });

        // Update reporting provider with coordinates AND location string
        if (mounted) {
          // Set coordinates immediately to prevent null values
          context.read<ReportingProvider>().setLocation(
            position.latitude,
            position.longitude,
          );

          // Also set location details as string
          context.read<ReportingProvider>().setLocationDetails(
            '${position.latitude},${position.longitude}',
          );
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoadingLocation = false;
            _locationError =
                _geoService.lastErrorMessage ??
                AppLocalizations.of(context)!.enableGpsMessage;
          });
        }
      }
    } on Exception {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
          _locationError = AppLocalizations.of(context)!.locationError;
        });
      }
    }
  }

  String _getGpsStatus(BuildContext context) {
    if (_isLoadingLocation) return AppLocalizations.of(context)!.acquiringGps;
    if (_locationError.isNotEmpty) {
      return AppLocalizations.of(context)!.noSignalGps;
    }
    if (_currentPosition == null) {
      return AppLocalizations.of(context)!.noSignalGps;
    }

    // A geocoded area centre or a tapped point has no accuracy (0): it is
    // not a GPS fix, so never report it as "GPS Strong".
    if (_positionSource != _PositionSource.gps) return 'Approximate';

    final accuracy = _currentPosition!.accuracy;
    if (accuracy <= 20) return AppLocalizations.of(context)!.gpsStrong;
    if (accuracy <= 50) return AppLocalizations.of(context)!.gpsGood;
    return AppLocalizations.of(context)!.gpsWeak;
  }

  Color _getGpsStatusColor(BuildContext context) {
    final status = _getGpsStatus(context);
    if (status == AppLocalizations.of(context)!.gpsStrong) {
      return Colors.green.shade700;
    }
    if (status == AppLocalizations.of(context)!.gpsGood ||
        status == 'Approximate') {
      return Colors.orange.shade700;
    }
    if (status == AppLocalizations.of(context)!.acquiringGps) {
      return Colors.blue.shade700;
    }
    return Colors.red.shade700;
  }

  /// Moves the camera only once the map has rendered (its controller throws
  /// before that).
  void _moveCamera(LatLng target) {
    if (!_mapReady) return;
    try {
      _mapController.move(target, 15.0);
    } on Object catch (_) {
      // Map not attached (e.g. being rebuilt) - the next frame shows the
      // current position anyway.
    }
  }

  /// Centres the map on the chosen State/LGA.
  ///
  /// A GPS fix (or a point the user tapped) is precise and is kept: only the
  /// camera moves. Without one, the geocoded area centre is used as an
  /// *approximate* position.
  Future<void> _updateMapToSelectedLocation(String locationString) async {
    final keepPosition =
        _positionSource == _PositionSource.gps ||
        _positionSource == _PositionSource.manual;
    if (!keepPosition) {
      setState(() {
        _isLoadingLocation = true;
      });
    }

    try {
      final position = await _geoService.getCoordinatesFromAddress(
        locationString,
      );
      if (!mounted) return;
      if (keepPosition) {
        // Precise coordinates stay untouched; just preview the area.
        if (position != null) {
          _moveCamera(LatLng(position.latitude, position.longitude));
        }
        return;
      }
      if (position != null) {
        setState(() {
          _currentPosition = position;
          _positionSource = _PositionSource.geocoded;
          _isLoadingLocation = false;
          _locationError = '';
        });

        _moveCamera(LatLng(position.latitude, position.longitude));

        context.read<ReportingProvider>().setLocation(
          position.latitude,
          position.longitude,
          approximate: true,
        );
      } else {
        setState(() {
          _isLoadingLocation = false;
          _locationError = AppLocalizations.of(context)!.couldNotFindLocation;
        });
      }
    } on Exception {
      if (mounted && !keepPosition) {
        setState(() {
          _isLoadingLocation = false;
          _locationError = AppLocalizations.of(context)!.mapUpdateError;
        });
      }
    }
  }

  Future<void> _onMapPositionChanged(LatLng point) async {
    // Determine new position mock
    final position = Position(
      latitude: point.latitude,
      longitude: point.longitude,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    );

    setState(() {
      _currentPosition = position;
      _positionSource = _PositionSource.manual;
    });

    // Update provider coordinates
    if (mounted) {
      context.read<ReportingProvider>().setLocation(
        point.latitude,
        point.longitude,
        approximate: true,
      );
      context.read<ReportingProvider>().setLocationDetails(
        '${point.latitude},${point.longitude}',
      );
    }

    // Reverse geocode to update UI text (but maybe not dropdowns to avoid loop/conflict)
    try {
      final details = await _geoService.getLocationDetails(
        point.latitude,
        point.longitude,
      );
      if (mounted) {
        // Display only: the report's LGA / ward come from the dropdowns
        // (reverse-geocoded names often do not match the INEC lists).
        setState(() {
          _lga = details['lga'] ?? 'Unknown LGA';
          _ward = details['ward'] ?? 'Unknown Ward';
        });
      }
    } on Exception {
      // ignore
    }
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
          AppLocalizations.of(context)!.reportDetailsTitle,
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
                    AppLocalizations.of(context)!.severityLevelLabel,
                    AppLocalizations.of(context)!.severityDesc,
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
                              context.read<ReportingProvider>().setSeverity(
                                _severityLevels[value.toInt()]!['value']
                                    as String,
                              );
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                AppLocalizations.of(context)!.severityLowShort,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                              Text(
                                AppLocalizations.of(context)!.severityMedShort,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                              Text(
                                AppLocalizations.of(context)!.severityHighShort,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                              Text(
                                AppLocalizations.of(context)!.severityCritShort,
                                style: const TextStyle(
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
                      _buildSectionTitle(
                        AppLocalizations.of(context)!.incidentLocation,
                        '',
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _getGpsStatusColor(
                            context,
                          ).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _isLoadingLocation
                                  ? Icons.gps_not_fixed
                                  : Icons.gps_fixed,
                              size: 14,
                              color: _getGpsStatusColor(context),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _getGpsStatus(context),
                              style: GoogleFonts.lexend(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _getGpsStatusColor(context),
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
                                                AppLocalizations.of(
                                                  context,
                                                )!.locationUnavailable,
                                                style: TextStyle(
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                              if (_locationError.isNotEmpty)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.fromLTRB(
                                                        16,
                                                        6,
                                                        16,
                                                        0,
                                                      ),
                                                  child: Text(
                                                    _locationError,
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color:
                                                          Colors.grey.shade600,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                )
                              : Stack(
                                  children: [
                                    OSMLocationPicker(
                                      mapController: _mapController,
                                      initialPosition: LatLng(
                                        _currentPosition!.latitude,
                                        _currentPosition!.longitude,
                                      ),
                                      isInteractive: true,
                                      onPositionChanged: _onMapPositionChanged,
                                      onMapReady: () => _mapReady = true,
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
                                                AppLocalizations.of(
                                                  context,
                                                )!.refresh,
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
                                        AppLocalizations.of(
                                          context,
                                        )!.coordinatesLabel,
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
                                                  ? AppLocalizations.of(
                                                      context,
                                                    )!.gettingLocation
                                                  : AppLocalizations.of(
                                                      context,
                                                    )!.noGpsData),
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
                                      AppLocalizations.of(
                                        context,
                                      )!.viewDetailsBtn,
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

                  const SizedBox(height: 24),

                  // Ward & LGA Selection Section
                  _buildSectionTitle(
                    AppLocalizations.of(context)!.wardAndLgaSelection,
                    AppLocalizations.of(context)!.selectWardDropdown,
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Info banner
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 20,
                                color: Colors.blue.shade700,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.selectLgaWardIncident,
                                  style: GoogleFonts.lexend(
                                    fontSize: 12,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // State Dropdown
                        Text(
                          AppLocalizations.of(context)!.stateLabel,
                          style: GoogleFonts.lexend(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          key: ValueKey('state_$_selectedState'),
                          initialValue: _selectedState,
                          decoration: InputDecoration(
                            hintText: AppLocalizations.of(context)!.selectState,
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            focusedBorder: const OutlineInputBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(12),
                              ),
                              borderSide: BorderSide(
                                color: AppColors.primaryRed,
                                width: 2,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                          items: MVPLocationsData.getAllStates()
                              .map(
                                (state) => DropdownMenuItem(
                                  value: state,
                                  child: Text(
                                    state,
                                    style: GoogleFonts.lexend(fontSize: 15),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedState = value;
                              _selectedLGA = null; // Reset LGA
                              _selectedWard = null; // Reset ward
                            });
                            if (value != null) {
                              context.read<ReportingProvider>().setReportState(
                                value,
                              );
                            }
                            // Try to move map to State center if possible (or just wait for LGA)
                            if (value != null) {
                              _updateMapToSelectedLocation(
                                '$value State, Nigeria',
                              );
                            }
                          },
                        ),

                        const SizedBox(height: 20),

                        // LGA Dropdown
                        Text(
                          AppLocalizations.of(context)!.lgaLabel,
                          style: GoogleFonts.lexend(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          key: ValueKey('lga_${_selectedState}_$_selectedLGA'),
                          initialValue: _selectedLGA,
                          decoration: InputDecoration(
                            hintText: _selectedState == null
                                ? AppLocalizations.of(context)!.selectStateFirst
                                : AppLocalizations.of(context)!.selectLga,
                            filled: true,
                            fillColor: _selectedState == null
                                ? Colors.grey.shade100
                                : Colors.grey.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            focusedBorder: const OutlineInputBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(12),
                              ),
                              borderSide: BorderSide(
                                color: AppColors.primaryRed,
                                width: 2,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                          items: _selectedState == null
                              ? []
                              : MVPLocationsData.getLGAsForState(
                                      _selectedState!,
                                    )
                                    .map(
                                      (lga) => DropdownMenuItem(
                                        value: lga,
                                        child: Text(
                                          lga,
                                          style: GoogleFonts.lexend(
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                          onChanged: _selectedState == null
                              ? null
                              : (value) {
                                  setState(() {
                                    _selectedLGA = value;
                                    _selectedWard = null; // Reset ward
                                  });

                                  // Update provider
                                  if (value != null) {
                                    context.read<ReportingProvider>().setLGA(
                                      value,
                                    );
                                    // Move map to LGA
                                    if (_selectedState != null) {
                                      _updateMapToSelectedLocation(
                                        '$value, $_selectedState State, Nigeria',
                                      );
                                    }
                                  }
                                },
                        ),

                        const SizedBox(height: 20),

                        // Ward Dropdown
                        Text(
                          AppLocalizations.of(context)!.wardLabel,
                          style: GoogleFonts.lexend(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          key: ValueKey('ward_${_selectedLGA}_$_selectedWard'),
                          initialValue: _selectedWard,
                          decoration: InputDecoration(
                            hintText: _selectedLGA == null
                                ? AppLocalizations.of(context)!.selectLgaFirst
                                : AppLocalizations.of(context)!.selectWard,
                            filled: true,
                            fillColor: _selectedLGA == null
                                ? Colors.grey.shade100
                                : Colors.grey.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            focusedBorder: const OutlineInputBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(12),
                              ),
                              borderSide: BorderSide(
                                color: AppColors.primaryRed,
                                width: 2,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                          items: _selectedLGA == null
                              ? []
                              : MVPLocationsData.getWardsForLGA(
                                      _selectedLGA!,
                                      state: _selectedState,
                                    )
                                    .map(
                                      (ward) => DropdownMenuItem(
                                        value: ward,
                                        child: Text(
                                          ward,
                                          style: GoogleFonts.lexend(
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                          onChanged: _selectedLGA == null
                              ? null
                              : (value) {
                                  setState(() {
                                    _selectedWard = value;
                                  });

                                  // Update provider
                                  if (value != null) {
                                    context.read<ReportingProvider>().setWard(
                                      value,
                                    );

                                    // Update location details with formatted string
                                    final locationString =
                                        MVPLocationsData.getLocationString(
                                          ward: value,
                                          lga: _selectedLGA!,
                                          state: _selectedState,
                                        );
                                    context
                                        .read<ReportingProvider>()
                                        .setLocationDetails(locationString);
                                  }
                                },
                        ),

                        // Show selected location summary
                        if (_selectedWard != null) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: Colors.green.shade700,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    MVPLocationsData.getLocationString(
                                      ward: _selectedWard!,
                                      lga: _selectedLGA!,
                                      state: _selectedState,
                                    ),
                                    style: GoogleFonts.lexend(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.green.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Use GPS Auto-fill
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.my_location, size: 16),
                        label: Text(
                          AppLocalizations.of(context)!.useMyLocationInfo,
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primaryRed,
                          side: const BorderSide(color: AppColors.primaryRed),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () {
                          // Try to match _lga from GPS to the state's LGAs
                          if (_selectedState != null &&
                              _lga != 'Loading...' &&
                              _lga != 'Unknown LGA') {
                            final lgas = MVPLocationsData.getLGAsForState(
                              _selectedState!,
                            );

                            // Check if GPS LGA exists in our MVP list for the selected state
                            String matchedLGA = '';
                            for (var l in lgas) {
                              if (l.toLowerCase() == _lga.toLowerCase() ||
                                  _lga.toLowerCase().contains(
                                    l.toLowerCase(),
                                  )) {
                                matchedLGA = l;
                                break;
                              }
                            }

                            if (matchedLGA.isNotEmpty) {
                              setState(() {
                                _selectedLGA = matchedLGA;
                              });
                              context.read<ReportingProvider>().setLGA(
                                matchedLGA,
                              );

                              // Try to match ward if LGA found
                              final wards = MVPLocationsData.getWardsForLGA(
                                matchedLGA,
                                state: _selectedState,
                              );
                              String matchedWard = '';
                              if (_ward != 'Loading...' &&
                                  _ward != 'Unknown Ward') {
                                for (var w in wards) {
                                  if (w.toLowerCase() == _ward.toLowerCase() ||
                                      _ward.toLowerCase().contains(
                                        w.toLowerCase(),
                                      )) {
                                    matchedWard = w;
                                    break;
                                  }
                                }
                              }

                              if (matchedWard.isNotEmpty) {
                                setState(() {
                                  _selectedWard = matchedWard;
                                });
                                context.read<ReportingProvider>().setWard(
                                  matchedWard,
                                );
                              } else {
                                // Fallback to first ward if GPS ward isn't exact
                                if (wards.isNotEmpty) {
                                  setState(() {
                                    _selectedWard = wards.first;
                                  });
                                  context.read<ReportingProvider>().setWard(
                                    wards.first,
                                  );
                                }
                              }

                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Auto-filled from GPS'),
                                ),
                              );
                            } else {
                              // LGA not found in state
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'GPS Location ($_lga) not found in $_selectedState',
                                  ),
                                ),
                              );
                            }
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'GPS Location unavailable or State not selected',
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  Center(
                    child: GestureDetector(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (context) {
                            final controller = TextEditingController(
                              text: _currentPosition != null
                                  ? '${_currentPosition!.latitude}, ${_currentPosition!.longitude}' // Auto-fill with GPS
                                  : '',
                            );
                            return AlertDialog(
                              title: Text(
                                AppLocalizations.of(
                                  context,
                                )!.enterLocationManually,
                              ),
                              content: TextField(
                                controller: controller,
                                decoration: InputDecoration(
                                  hintText: AppLocalizations.of(
                                    context,
                                  )!.addressOrCoordinates,
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: Text(
                                    AppLocalizations.of(context)!.cancelBtn,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    if (controller.text.isNotEmpty) {
                                      context
                                          .read<ReportingProvider>()
                                          .setLocationDetails(controller.text);
                                      // Also make sure severity is set
                                      context
                                          .read<ReportingProvider>()
                                          .setSeverity(
                                            _severityLevels[_severityValue
                                                    .toInt()]!['value']
                                                as String,
                                          );

                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            AppLocalizations.of(
                                              context,
                                            )!.manualLocationSet,
                                          ),
                                        ),
                                      );
                                    }
                                    Navigator.pop(context);
                                  },
                                  child: Text(
                                    AppLocalizations.of(
                                      context,
                                    )!.setLocationBtn,
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                      child: Text(
                        AppLocalizations.of(context)!.locationIncorrectManual,
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
              child: CustomButton(
                onPressed: () {
                  // Validation
                  if (_selectedState == null ||
                      _selectedLGA == null ||
                      _selectedWard == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          AppLocalizations.of(
                            context,
                          )!.pleaseSelectStateLgaWard,
                        ),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }

                  final reporting = context.read<ReportingProvider>();

                  // Sync Severity
                  reporting.setSeverity(
                    _severityLevels[_severityValue.toInt()]!['value'] as String,
                  );

                  // The dropdown selection is the report's location (never
                  // the reverse-geocoded map position).
                  reporting
                    ..setReportState(_selectedState!)
                    ..setLGA(_selectedLGA!)
                    ..setWard(_selectedWard!);
                  final details = reporting.locationDetails;
                  if (details == null ||
                      details.isEmpty ||
                      RegExp(
                        r'^-?\d+(\.\d+)?,\s*-?\d+(\.\d+)?$',
                      ).hasMatch(details)) {
                    reporting.setLocationDetails(
                      MVPLocationsData.getLocationString(
                        ward: _selectedWard!,
                        lga: _selectedLGA!,
                        state: _selectedState,
                      ),
                    );
                  }

                  // Sync Location (already set via dropdowns)
                  // Also sync GPS coordinates if available
                  if (_currentPosition != null) {
                    context.read<ReportingProvider>().setLocation(
                      _currentPosition!.latitude,
                      _currentPosition!.longitude,
                      approximate: _positionSource != _PositionSource.gps,
                    );
                  }

                  context.push('/report/details');
                },
                text: AppLocalizations.of(context)!.confirmAndContinue,
                icon: Icons.arrow_forward,
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
                  AppLocalizations.of(context)!.locationDetailsTitle,
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
              AppLocalizations.of(context)!.latitudeLabel,
              _currentPosition!.latitude.toStringAsFixed(6),
            ),
            const SizedBox(height: 12),
            _buildDetailRow(
              Icons.my_location,
              AppLocalizations.of(context)!.longitudeLabel,
              _currentPosition!.longitude.toStringAsFixed(6),
            ),
            const SizedBox(height: 12),
            _buildDetailRow(
              Icons.gps_fixed,
              AppLocalizations.of(context)!.accuracyLabel,
              '${_currentPosition!.accuracy.toStringAsFixed(1)} meters',
            ),
            const SizedBox(height: 12),
            _buildDetailRow(
              Icons.height,
              AppLocalizations.of(context)!.altitudeLabel,
              '${_currentPosition!.altitude.toStringAsFixed(1)} m',
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: CustomButton(
                onPressed: () => Navigator.pop(context),
                text: AppLocalizations.of(context)!.closeBtn,
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
