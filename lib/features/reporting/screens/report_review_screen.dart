import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

class ReportReviewScreen extends StatefulWidget {
  const ReportReviewScreen({super.key});

  @override
  State<ReportReviewScreen> createState() => _ReportReviewScreenState();
}

class _ReportReviewScreenState extends State<ReportReviewScreen> {
  bool _isSubmitting = false;

  Future<void> _submitReport() async {
    setState(() => _isSubmitting = true);

    try {
      final result = await context.read<ReportingProvider>().submitReport();

      if (!mounted) return;

      setState(() => _isSubmitting = false);

      if (result['success'] == true) {
        _showSuccessDialog(
          result['queued'] == true,
          reportId: result['reportId'],
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] ?? 'Submission failed')),
        );
      }
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
    }
  }

  void _showSuccessDialog(bool isQueued, {String? reportId}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: (isQueued ? Colors.orange : AppColors.primaryRed)
                      .withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isQueued ? Icons.cloud_off : Icons.check_circle,
                  color: isQueued ? Colors.orange : AppColors.primaryRed,
                  size: 40,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                isQueued ? 'Saved for Later' : 'Report Submitted!',
                style: GoogleFonts.lexend(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isQueued
                    ? 'You are offline. The report will be sent automatically when you are back online.'
                    : 'Your report has been successfully sent to central command.',
                textAlign: TextAlign.center,
                style: GoogleFonts.lexend(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    Text(
                      isQueued ? 'STATUS' : 'REPORT ID',
                      style: GoogleFonts.lexend(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isQueued
                          ? 'QUEUED'
                          : (reportId != null
                                ? '#${reportId.substring(0, 8)}...'
                                : 'SENT'),
                      style: GoogleFonts.robotoMono(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isQueued ? Colors.orange : AppColors.primaryRed,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    // Provider is already reset in submitReport
                    context.go('/dashboard');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade200,
                    foregroundColor: AppColors.textPrimary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Return to Dashboard'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          'Review Report',
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
                  Text(
                    'Please review the details below to ensure accuracy before submitting to the central command.',
                    style: GoogleFonts.lexend(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Hazard Details
                  _buildSectionHeader(
                    'Hazard Details',
                    onEdit: () => context.go('/report'),
                  ), // Go back to start or specific step? go/pop might be better
                  Container(
                    decoration: _cardDecoration(),
                    child: Column(
                      children: [
                        _buildListItem(
                          icon: Icons.flood,
                          iconColor: Colors.red,
                          iconBg: Colors.red.shade50,
                          label: 'Hazard Type',
                          value: 'Flash Flood',
                        ),
                        Divider(
                          height: 1,
                          color: Colors.grey.shade100,
                          indent: 16,
                          endIndent: 16,
                        ),
                        _buildListItem(
                          icon: Icons.warning,
                          iconColor: Colors.orange,
                          iconBg: Colors.orange.shade50,
                          label: 'Severity Level',
                          value: 'High Severity',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Date & Time
                  _buildSectionHeader(
                    'Date & Time',
                    onEdit: () => context.pop(),
                  ),
                  Consumer<ReportingProvider>(
                    builder: (context, provider, _) {
                      final reportDate = provider.reportDateTime;
                      final isToday =
                          reportDate.day == DateTime.now().day &&
                          reportDate.month == DateTime.now().month &&
                          reportDate.year == DateTime.now().year;

                      return Container(
                        decoration: _cardDecoration(),
                        child: _buildListItem(
                          icon: Icons.access_time,
                          iconColor: AppColors.primaryRed,
                          iconBg: AppColors.primaryRed.withValues(alpha: 0.1),
                          label: 'When it occurred',
                          value: isToday
                              ? 'Today at ${DateFormat('h:mm a').format(reportDate)}'
                              : '${DateFormat('MMM dd, yyyy').format(reportDate)} at ${DateFormat('h:mm a').format(reportDate)}',
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // Location
                  _buildSectionHeader(
                    'Location',
                    onEdit: () => context.pop(),
                  ), // Assuming pop goes back to details, need to go back 2 steps? Context.go is safer if we know path
                  Container(
                    decoration: _cardDecoration(),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 120,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.map,
                              color: Colors.grey.shade400,
                              size: 40,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Benue River Bank, Makurdi',
                          style: GoogleFonts.lexend(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Lat: 7.7322° N, Long: 8.5218° E',
                          style: GoogleFonts.robotoMono(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Description
                  _buildSectionHeader(
                    'Monitor Notes',
                    onEdit: () => context.pop(),
                  ),
                  Container(
                    decoration: _cardDecoration(),
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Water levels have risen rapidly over the last 3 hours. Several households in the lower ward are already displaced. Immediate evacuation assistance is required.',
                      style: GoogleFonts.lexend(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Evidence
                  _buildSectionHeader('Evidence', onEdit: () => context.pop()),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildEvidenceThumb(),
                        const SizedBox(width: 12),
                        _buildEvidenceThumb(),
                        const SizedBox(width: 12),
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.grey.shade300,
                              style: BorderStyle.solid,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_a_photo,
                                size: 20,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Add',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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
                onPressed: _isSubmitting ? null : _submitReport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryRed,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 4,
                  disabledBackgroundColor: AppColors.primaryRed.withValues(
                    alpha: 0.6,
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Submit Report',
                            style: GoogleFonts.lexend(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.send),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade200),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.02),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, {required VoidCallback onEdit}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title.toUpperCase(),
            style: GoogleFonts.lexend(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary,
            ),
          ),
          InkWell(
            onTap: onEdit,
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              child: Text(
                'Edit',
                style: GoogleFonts.lexend(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryRed,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListItem({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.lexend(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade500,
                ),
              ),
              Text(
                value,
                style: GoogleFonts.lexend(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEvidenceThumb() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.image, color: Colors.white),
    );
  }
}
