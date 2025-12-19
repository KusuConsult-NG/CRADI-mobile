import 'package:climate_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart';

class HazardSelectionScreen extends StatefulWidget {
  const HazardSelectionScreen({super.key});

  @override
  State<HazardSelectionScreen> createState() => _HazardSelectionScreenState();
}

class _HazardSelectionScreenState extends State<HazardSelectionScreen> {
  int? _selectedindex;

  final List<Map<String, dynamic>> _hazards = [
    {'name': 'Flooding', 'icon': Icons.flood, 'color': AppColors.hazardFlood},
    {
      'name': 'Extreme Heat',
      'icon': Icons.thermostat,
      'color': AppColors.hazardTemp,
    },
    {
      'name': 'Drought',
      'icon': Icons.wb_sunny_rounded,
      'color': AppColors.hazardDrought,
    },
    {'name': 'Windstorms', 'icon': Icons.air, 'color': AppColors.hazardWind},
    {
      'name': 'Wildfires',
      'icon': Icons.local_fire_department,
      'color': AppColors.hazardFire,
    },
    {
      'name': 'Erosion',
      'icon': Icons.landslide,
      'color': AppColors.hazardErosion,
    },
    {
      'name': 'Pest Outbreak',
      'icon': Icons.pest_control,
      'color': AppColors.hazardPest,
    },
    {
      'name': 'Crop Disease',
      'icon': Icons.coronavirus_rounded,
      'color': Colors.green,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Select Hazard',
          style: GoogleFonts.lexend(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppColors.background,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.grey.shade200, height: 1.0),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Text(
              'What type of incident are you reporting?',
              textAlign: TextAlign.center,
              style: GoogleFonts.lexend(
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.0,
              ),
              itemCount: _hazards.length,
              itemBuilder: (context, index) {
                final hazard = _hazards[index];
                final isSelected = _selectedindex == index;
                return _buildHazardCard(hazard, index, isSelected);
              },
            ),
          ),
        ],
      ),
      bottomSheet: Container(
        color: Colors.white, // White background for better button visibility
        padding: const EdgeInsets.all(16),
        child: SafeArea(
          child: ElevatedButton(
            onPressed: _selectedindex != null
                ? () {
                    final hazardName =
                        _hazards[_selectedindex!]['name'] as String;
                    context.read<ReportingProvider>().setHazardType(hazardName);
                    context.push('/report/severity');
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryRed,
              disabledBackgroundColor: Colors.grey.shade300,
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.grey,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 4,
            ),
            child: Text(
              'Continue',
              style: GoogleFonts.lexend(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHazardCard(
    Map<String, dynamic> hazard,
    int index,
    bool isSelected,
  ) {
    return GestureDetector(
      onTap: () => setState(() => _selectedindex = index),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primaryRed : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Selected Overlay
            if (isSelected)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.primaryRed.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),

            // Content
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (hazard['color'] as Color).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      hazard['icon'] as IconData,
                      size: 32,
                      color: hazard['color'] as Color,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    hazard['name'] as String,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.lexend(
                      fontSize: 14,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),

            // Selection Checkmark
            if (isSelected)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: AppColors.primaryRed,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, size: 12, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
