import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/shared/widgets/custom_button.dart';
import 'package:climate_app/core/l10n/l10n.dart';

class SeveritySelectionScreen extends StatefulWidget {
  const SeveritySelectionScreen({super.key, this.returnToReview = false});

  /// Opened from the review screen's "Edit" link: Continue pops back to the
  /// review instead of pushing the rest of the wizard again.
  final bool returnToReview;

  @override
  State<SeveritySelectionScreen> createState() =>
      _SeveritySelectionScreenState();
}

class _SeveritySelectionScreenState extends State<SeveritySelectionScreen> {
  SeverityLevel _currentLevel = SeverityLevel.low;

  @override
  void initState() {
    super.initState();
    // Start from the severity already chosen (e.g. when editing from review).
    final saved = context.read<ReportingProvider>().severity;
    for (final level in SeverityLevel.values) {
      if (level.name == saved) _currentLevel = level;
    }
  }

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

  String _getLabel(SeverityLevel level, AppLocalizations l10n) {
    switch (level) {
      case SeverityLevel.low:
        return l10n.lowMinorImpact;
      case SeverityLevel.medium:
        return l10n.mediumNoticeableImpact;
      case SeverityLevel.high:
        return l10n.highSignificantDamage;
      case SeverityLevel.critical:
        return l10n.criticalLifeThreatening;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.setSeverity)),
      // Scrollable so the screen still fits when the system font is scaled
      // up; the min-height constraint keeps the 1x layout unchanged.
      body: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  Text(
                    l10n.howSevereSituation,
                    style: const TextStyle(fontSize: 18),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _getColor(_currentLevel),
                        width: 4,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      color: _getColor(_currentLevel).withValues(alpha: 0.1),
                    ),
                    // Decorative: the severity is conveyed by the text and the
                    // slider's semantics value below.
                    child: ExcludeSemantics(
                      child: Icon(
                        Icons.warning_amber_rounded,
                        size: 140,
                        color: _getColor(_currentLevel),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Semantics(
                    liveRegion: true,
                    label: l10n.a11ySeverityLabel(
                      _getLabel(_currentLevel, l10n),
                    ),
                    excludeSemantics: true,
                    child: Text(
                      _getLabel(_currentLevel, l10n),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: _getColor(_currentLevel),
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 24,
                    ),
                    decoration: BoxDecoration(
                      color: _getColor(_currentLevel).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(32),
                    ),
                    child: Slider(
                      // Without these the slider is announced as a bare number.
                      label: _getLabel(_currentLevel, l10n),
                      semanticFormatterCallback: (value) =>
                          l10n.a11ySeverityLabel(
                            _getLabel(
                              SeverityLevel.values[value.round().clamp(
                                0,
                                SeverityLevel.values.length - 1,
                              )],
                              l10n,
                            ),
                          ),
                      value: _currentLevel.index.toDouble(),
                      min: 0,
                      max: 3,
                      divisions: 3,
                      activeColor: _getColor(_currentLevel),
                      inactiveColor: _getColor(
                        _currentLevel,
                      ).withValues(alpha: 0.3),
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
                        // Save base name (e.g. 'high', 'critical') for backend consistency
                        context.read<ReportingProvider>().setSeverity(
                          _currentLevel.name,
                        );
                        if (widget.returnToReview) {
                          context.pop();
                        } else {
                          context.push('/report/location');
                        }
                      },
                      text: l10n.nextLocation,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
