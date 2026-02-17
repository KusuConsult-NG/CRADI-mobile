import 'package:climate_app/core/data/nigeria_locations_data.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Reusable cascading dropdown for Nigeria States and LGAs
class LocationSelectorWidget extends StatefulWidget {
  final String? initialState;
  final String? initialLGA;
  final String? initialWard;
  final Function(String? state, String? lga, String? ward) onLocationChanged;
  final bool required;

  const LocationSelectorWidget({
    super.key,
    this.initialState,
    this.initialLGA,
    this.initialWard,
    required this.onLocationChanged,
    this.required = false,
  });

  @override
  State<LocationSelectorWidget> createState() => _LocationSelectorWidgetState();
}

class _LocationSelectorWidgetState extends State<LocationSelectorWidget> {
  String? _selectedState;
  String? _selectedLGA;
  String? _selectedWard;
  List<String> _availableLGAs = [];
  List<String> _availableWards = [];

  @override
  void initState() {
    super.initState();
    _selectedState = widget.initialState;
    _selectedLGA = widget.initialLGA;
    _selectedWard = widget.initialWard;
    if (_selectedState != null) {
      _availableLGAs = NigeriaLocationsData.getLGAsForState(_selectedState!);
    }
    if (_selectedLGA != null) {
      _availableWards = NigeriaLocationsData.getWardsForLGA(
        _selectedState!,
        _selectedLGA!,
      );
    }
  }

  void _onStateChanged(String? state) {
    setState(() {
      _selectedState = state;
      _selectedLGA = null; // Reset LGA when state changes
      _selectedWard = null; // Reset Ward when state changes
      _availableLGAs = state != null
          ? NigeriaLocationsData.getLGAsForState(state)
          : [];
      _availableWards = [];
    });
    widget.onLocationChanged(_selectedState, _selectedLGA, _selectedWard);
  }

  void _onLGAChanged(String? lga) {
    setState(() {
      _selectedLGA = lga;
      _selectedWard = null; // Reset Ward when LGA changes
      if (_selectedState != null && lga != null) {
        _availableWards = NigeriaLocationsData.getWardsForLGA(
          _selectedState!,
          lga,
        );
      } else {
        _availableWards = [];
      }
    });
    widget.onLocationChanged(_selectedState, _selectedLGA, _selectedWard);
  }

  void _onWardChanged(String? ward) {
    setState(() {
      _selectedWard = ward;
    });
    widget.onLocationChanged(_selectedState, _selectedLGA, _selectedWard);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // State Dropdown
        _buildDropdown(
          label: 'State${widget.required ? ' *' : ''}',
          value: _selectedState,
          items: NigeriaLocationsData.focalStates,
          onChanged: _onStateChanged,
          hint: 'Select State',
        ),
        const SizedBox(height: 16),

        // LGA Dropdown
        _buildDropdown(
          label: 'Local Government Area${widget.required ? ' *' : ''}',
          value: _selectedLGA,
          items: _availableLGAs,
          onChanged: _selectedState != null ? _onLGAChanged : null,
          hint: _selectedState != null ? 'Select LGA' : 'Select state first',
        ),
        const SizedBox(height: 16),

        // Ward Dropdown
        _buildDropdown(
          label: 'Ward${widget.required ? ' *' : ''}',
          value: _selectedWard,
          items: _availableWards,
          onChanged: _selectedLGA != null ? _onWardChanged : null,
          hint: _selectedLGA != null ? 'Select Ward' : 'Select LGA first',
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required Function(String?)? onChanged,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.lexend(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: DropdownButtonFormField<String>(
            key: ValueKey(value),
            initialValue: value,
            items: items.map((item) {
              return DropdownMenuItem(
                value: item,
                child: Text(
                  item,
                  style: GoogleFonts.lexend(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
              );
            }).toList(),
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.lexend(
                color: Colors.grey.shade400,
                fontSize: 14,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
            icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade600),
            dropdownColor: Colors.white,
            isExpanded: true,
          ),
        ),
      ],
    );
  }
}
