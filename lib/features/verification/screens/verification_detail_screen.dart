import 'package:climate_app/core/services/peer_verification_service.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:climate_app/shared/widgets/custom_button.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:climate_app/features/reporting/widgets/osm_location_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';

class VerificationDetailScreen extends StatefulWidget {
  final Map<String, dynamic> report;

  const VerificationDetailScreen({super.key, required this.report});

  @override
  State<VerificationDetailScreen> createState() =>
      _VerificationDetailScreenState();
}

class _VerificationDetailScreenState extends State<VerificationDetailScreen> {
  bool _isLoading = false;
  final TextEditingController _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitVerification(bool isConfirmed) async {
    setState(() => _isLoading = true);

    try {
      // In a real app, we'd get the current user ID globally
      // For MVP, we'll assume a user ID or fetch it
      final userId =
          context.read<AuthProvider>().currentUser?.uid ?? 'unknown_user';

      final result = await PeerVerificationService().submitVerification(
        reportId: widget.report['\$id'] ?? widget.report['id'] ?? 'unknown',
        userId: userId,
        isConfirmed: isConfirmed,
        comment: _commentController.text,
      );

      if (mounted) {
        setState(() => _isLoading = false);

        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message']),
              backgroundColor: isConfirmed ? Colors.green : Colors.orange,
            ),
          );
          context.pop(); // Go back to list
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Verification failed: ${result['error']}')),
          );
        }
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorHandler.handleError(e, context: 'Verification')),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final date =
        DateTime.tryParse(report['submittedAt'] ?? '') ?? DateTime.now();
    final formattedDate = DateFormat('MMM d, y • h:mm a').format(date);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Verify Report'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.orange),
              ),
              child: Text(
                'PENDING VERIFICATION',
                style: GoogleFonts.lexend(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade800,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header Info
            Text(
              report['hazardType'] ?? 'Unknown Hazard',
              style: GoogleFonts.lexend(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.location_on,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    report['locationDetails'] ?? 'No location details',
                    style: GoogleFonts.lexend(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.access_time,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  formattedDate,
                  style: GoogleFonts.lexend(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            // Description
            Text(
              'Description',
              style: GoogleFonts.lexend(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              report['description'] ?? 'No description provided.',
              style: GoogleFonts.lexend(
                fontSize: 14,
                color: AppColors.textPrimary,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 24),

            // Map Placeholder (In real app, show map)
            // Map View
            if (report['latitude'] != null && report['longitude'] != null)
              SizedBox(
                height: 200,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: OSMLocationPicker(
                    initialPosition: LatLng(
                      double.tryParse(report['latitude'].toString()) ?? 0,
                      double.tryParse(report['longitude'].toString()) ?? 0,
                    ),
                    isInteractive: false,
                  ),
                ),
              )
            else
              Container(
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.location_off,
                        size: 40,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No map location available',
                        style: GoogleFonts.lexend(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 32),

            // Verification Actions
            Text(
              'Can you confirm this report?',
              style: GoogleFonts.lexend(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please verify if you have observed this hazard in the reported location.',
              style: GoogleFonts.lexend(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),

            const SizedBox(height: 16),
            TextField(
              controller: _commentController,
              decoration: const InputDecoration(
                labelText: 'Optional Comment',
                border: OutlineInputBorder(),
                hintText: 'Add details about what you see...',
              ),
              maxLines: 2,
            ),

            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: CustomButton(
                    text: 'I Cannot Confirm',
                    onPressed: _isLoading
                        ? null
                        : () => _submitVerification(false),
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red,
                    type: ButtonType.secondary,
                    isLoading: _isLoading,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: CustomButton(
                    text: 'I Can Confirm',
                    onPressed: _isLoading
                        ? null
                        : () => _submitVerification(true),
                    backgroundColor: Colors.green,
                    isLoading: _isLoading,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
