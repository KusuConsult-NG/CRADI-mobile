import 'package:climate_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:climate_app/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart';
import 'package:climate_app/shared/widgets/custom_button.dart';

class HazardSelectionScreen extends StatefulWidget {
  const HazardSelectionScreen({super.key});

  @override
  State<HazardSelectionScreen> createState() => _HazardSelectionScreenState();
}

class _HazardSelectionScreenState extends State<HazardSelectionScreen> {
  int? _selectedindex;

  List<Map<String, dynamic>> _getHazards(AppLocalizations l10n) {
    return [
      {'id': 'Flooding', 'name': l10n.flooding, 'icon': Icons.flood, 'color': AppColors.hazardFlood},
      {
        'id': 'Extreme Temperatures',
        'name': l10n.extremeHeat,
        'icon': Icons.thermostat,
        'color': AppColors.hazardTemp,
      },
      {
        'id': 'Drought',
        'name': l10n.drought,
        'icon': Icons.wb_sunny_rounded,
        'color': AppColors.hazardDrought,
      },
      {'id': 'Windstorms', 'name': l10n.windstorms, 'icon': Icons.air, 'color': AppColors.hazardWind},
      {
        'id': 'Wildfires',
        'name': l10n.wildfires,
        'icon': Icons.local_fire_department,
        'color': AppColors.hazardFire,
      },
      {
        'id': 'Erosion',
        'name': l10n.erosion,
        'icon': Icons.landslide,
        'color': AppColors.hazardErosion,
      },
      {
        'id': 'Pest Outbreak',
        'name': l10n.pestOutbreak,
        'icon': Icons.pest_control,
        'color': AppColors.hazardPest,
      },
      {
        'id': 'Crop Disease',
        'name': l10n.cropDisease,
        'icon': Icons.coronavirus_rounded,
        'color': Colors.green,
      },
      {
        'id': 'Conflict',
        'name': l10n.conflict,
        'icon': Icons.warning_amber_rounded,
        'color': AppColors.primaryRed,
      },
    ];
  }

  @override
  void initState() {
    super.initState();
    // Reset any previous reporting state when starting a new report
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ReportingProvider>().reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hazards = _getHazards(l10n);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/dashboard');
            }
          },
        ),
        title: Text(
          l10n.selectHazard,
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
              l10n.whatIncident,
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
              itemCount: hazards.length,
              itemBuilder: (context, index) {
                final hazard = hazards[index];
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
          child: CustomButton(
            onPressed: _selectedindex != null
                ? () {
                    final hazardId = hazards[_selectedindex!]['id'] as String;
                    context.read<ReportingProvider>().setHazardType(hazardId);
                    context.push('/report/severity');
                  }
                : null,
            text: l10n.continueButton,
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
