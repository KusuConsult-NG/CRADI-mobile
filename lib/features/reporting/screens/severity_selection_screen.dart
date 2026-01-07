import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/shared/widgets/custom_button.dart';

class SeveritySelectionScreen extends StatefulWidget {
  const SeveritySelectionScreen({super.key});

  @override
  State<SeveritySelectionScreen> createState() =>
      _SeveritySelectionScreenState();
}

class _SeveritySelectionScreenState extends State<SeveritySelectionScreen> {
  SeverityLevel _currentLevel = SeverityLevel.low;

  Color _getColor(SeverityLevel level) {
    switch (level) {
      case SeverityLevel.low:
        return AppColors.successGreen;
      case SeverityLevel.medium:
        return AppColors.warningYellow;
      case SeverityLevel.high:
        return Colors.orange;
      case SeverityLevel.critical:
        return AppColors.primaryRed;
    }
  }

  String _getLabel(SeverityLevel level) {
    switch (level) {
      case SeverityLevel.low:
        return 'Low - Minor impact';
      case SeverityLevel.medium:
        return 'Medium - Noticeable impact';
      case SeverityLevel.high:
        return 'High - Significant damage';
      case SeverityLevel.critical:
        return 'Critical - Life threatening';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set Severity')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Text(
              'How severe is the situation?',
              style: TextStyle(fontSize: 18),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                border: Border.all(color: _getColor(_currentLevel), width: 4),
                borderRadius: BorderRadius.circular(24),
                color: _getColor(_currentLevel).withValues(alpha: 0.1),
              ),
              child: Icon(
                Icons.warning_amber_rounded,
                size: 140,
                color: _getColor(_currentLevel),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              _getLabel(_currentLevel),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: _getColor(_currentLevel),
              ),
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 24),
              decoration: BoxDecoration(
                color: _getColor(_currentLevel).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(32),
              ),
              child: Slider(
                value: _currentLevel.index.toDouble(),
                min: 0,
                max: 3,
                divisions: 3,
                activeColor: _getColor(_currentLevel),
                inactiveColor: _getColor(_currentLevel).withValues(alpha: 0.3),
                thumbColor: _getColor(_currentLevel),
                onChanged: (value) {
                  setState(() {
                    _currentLevel = SeverityLevel.values[value.toInt()];
                  });
                },
              ),
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: CustomButton(
                onPressed: () {
                  context.read<ReportingProvider>().setSeverity(
                    _currentLevel.name,
                  );
                  // For MVP flow, skipping explicit location screen if auto-detect is assumed,
                  // but sticking to PRD plan, location is next.
                  // For now, let's just create a placeholder valid flow
                  context.push('/report/location');
                },
                text: 'Next: Location',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
