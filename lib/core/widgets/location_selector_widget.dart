import 'package:climate_app/core/data/nigeria_locations_data.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:climate_app/core/l10n/l10n.dart';

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
    // Blank or unknown initial values (e.g. '' from an empty profile) are
    // treated as "not selected": a dropdown value must be one of its items.
    String? pick(String? value, List<String> options) {
      final v = value?.trim();
      if (v == null || v.isEmpty) return null;
      return options.contains(v) ? v : null;
    }

    _selectedState = pick(
      widget.initialState,
      NigeriaLocationsData.focalStates,
    );
    if (_selectedState != null) {
      _availableLGAs = NigeriaLocationsData.getLGAsForState(_selectedState!);
      _selectedLGA = pick(widget.initialLGA, _availableLGAs);
    }
    if (_selectedLGA != null) {
      _availableWards = NigeriaLocationsData.getWardsForLGA(
        _selectedState!,
        _selectedLGA!,
      );
      _selectedWard = pick(widget.initialWard, _availableWards);
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

  /// Field label, with a required marker when [LocationSelectorWidget.required].
  String _label(String label) =>
      widget.required ? context.l10n.formFieldRequiredLabel(label) : label;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // State Dropdown
        _buildDropdown(
          label: _label(l10n.stateLabel),
          value: _selectedState,
          items: NigeriaLocationsData.focalStates,
          onChanged: _onStateChanged,
          hint: l10n.selectState,
        ),
        const SizedBox(height: 16),

        // LGA Dropdown
        _buildDropdown(
          label: _label(l10n.locationSelectorLgaLabel),
          value: _selectedLGA,
          items: _availableLGAs,
          onChanged: _selectedState != null ? _onLGAChanged : null,
          hint: _selectedState != null ? l10n.selectLga : l10n.selectStateFirst,
        ),
        const SizedBox(height: 16),

        // Ward Dropdown
        _buildDropdown(
          label: _label(l10n.wardLabel),
          value: _selectedWard,
          items: _availableWards,
          onChanged: _selectedLGA != null ? _onWardChanged : null,
          hint: _selectedLGA != null ? l10n.selectWard : l10n.selectLgaFirst,
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
