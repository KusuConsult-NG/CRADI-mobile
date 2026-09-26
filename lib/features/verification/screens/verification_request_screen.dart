import 'package:climate_app/core/constants/hazards.dart';
import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:climate_app/core/utils/validators.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/features/verification/models/verification_report_model.dart';
import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:climate_app/core/widgets/location_selector_widget.dart';
import 'package:climate_app/core/l10n/l10n.dart';
import 'package:climate_app/core/l10n/severity_label.dart';

/// Verification request screen - submit verification request
/// Submits a verification request backed by Supabase.
class VerificationRequestScreen extends StatefulWidget {
  const VerificationRequestScreen({super.key});

  @override
  State<VerificationRequestScreen> createState() =>
      _VerificationRequestScreenState();
}

class _VerificationRequestScreenState extends State<VerificationRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  String _selectedHazard = Hazard.flooding.storedName;
  String _selectedSeverity = 'medium';
  String? _selectedState;
  String? _selectedLGA;
  String? _selectedWard;

  /// Stored hazard names (same values as the reporting flow).
  final List<String> _hazards = [for (final h in Hazard.values) h.storedName];

  /// Stored severity values (labels come from [severityLabel]).
  static const List<String> _severities = ['low', 'medium', 'high', 'critical'];

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    // Dismiss keyboard
    FocusScope.of(context).unfocus();

    if (_selectedState == null ||
        _selectedLGA == null ||
        _selectedWard == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.pleaseSelectStateLgaWard)),
        );
      }
      return;
    }

    try {
      final user = SupabaseService().getCurrentUser();

      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.authErrorNotLoggedIn)),
          );
        }
        return;
      }

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final l10n = context.l10n;
      final router = GoRouter.of(context);
      // Deep-linked (nothing below): go to the verification list instead.
      void leave() {
        if (router.canPop()) {
          router.pop();
        } else {
          router.go('/verification');
        }
      }

      try {
        await context.read<ReportsStatusProvider>().submitVerificationRequest(
          userId: user.id,
          hazardType: _selectedHazard,
          severity: _selectedSeverity,
          description: _descriptionController.text,
          state: _selectedState!,
          lga: _selectedLGA!,
          ward: _selectedWard!,
          // Fixed marker (shown localised via displayLocation).
          locationDetails: VerificationReport.verificationRequestLocation,
        );
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.verificationRequestSubmitted)),
        );
        if (mounted) leave();
      } on OfflineQueuedException catch (e) {
        // Saved to the sync queue: it will be uploaded automatically.
        messenger.showSnackBar(SnackBar(content: Text(e.message(l10n))));
        if (mounted) leave();
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ErrorHandler.handleError(
                e,
                context.l10n,
                context: 'Verification',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.verificationRequestTitle),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            size: 20,
            color: Colors.black, // Default text color is usually black/grey
            // Assuming AppTheme uses standard icon themes, but safest to be consistent
          ),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/dashboard');
            }
          },
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedHazard,
              decoration: InputDecoration(
                labelText: context.l10n.hazardType,
                border: const OutlineInputBorder(),
              ),
              items: _hazards
                  .map(
                    (h) => DropdownMenuItem(
                      value: h,
                      child: Text(Hazard.labelFor(h, context.l10n)),
                    ),
                  )
                  .toList(),
              onChanged: (val) => setState(() => _selectedHazard = val!),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedSeverity,
              decoration: InputDecoration(
                labelText: context.l10n.reportViewSeverity,
                border: const OutlineInputBorder(),
              ),
              items: _severities
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Text(severityLabel(context.l10n, s)),
                    ),
                  )
                  .toList(),
              onChanged: (val) => setState(() => _selectedSeverity = val!),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: context.l10n.descriptionLabel,
                hintText: context.l10n.verificationRequestDescriptionHint,
                border: const OutlineInputBorder(),
              ),
              maxLines: 5,
              validator: (value) => Validators.validateDescription(
                value,
                context.l10n,
                maxLength: 500,
              ),
            ),
            const SizedBox(height: 16),
            LocationSelectorWidget(
              initialState: _selectedState,
              initialLGA: _selectedLGA,
              initialWard: _selectedWard,
              onLocationChanged: (state, lga, ward) {
                setState(() {
                  _selectedState = state;
                  _selectedLGA = lga;
                  _selectedWard = ward;
                });
              },
            ),
            const SizedBox(height: 24),
            Consumer<ReportsStatusProvider>(
              builder: (context, provider, child) {
                return ElevatedButton(
                  onPressed: provider.isSubmitting
                      ? null
                      : _submitRequest, // Use isSubmitting
                  child:
                      provider
                          .isSubmitting // Use isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(context.l10n.verificationRequestSubmit),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
