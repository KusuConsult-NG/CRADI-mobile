import 'dart:io';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:climate_app/features/reporting/widgets/osm_location_picker.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:climate_app/shared/widgets/custom_button.dart';
import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/l10n/app_localizations.dart';

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
      final result = await context.read<ReportingProvider>().submitReport(
        context,
      );

      if (!mounted) return;

      setState(() => _isSubmitting = false);

      // Saved offline as a draft, or queued after a failed online submission:
      // either way the report is stored locally and will sync later.
      final savedForLater =
          result['offline'] == true || result['queued'] == true;
      if (result['success'] == true || savedForLater) {
        _showSuccessDialog(savedForLater, reportId: result['reportId']);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['message'] ??
                  AppLocalizations.of(context)!.submissionFailed,
            ),
          ),
        );
      }
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ErrorHandler.handleError(e, context: 'Report Submission'),
          ),
        ),
      );
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
                isQueued
                    ? AppLocalizations.of(context)!.savedForLater
                    : AppLocalizations.of(context)!.reportSubmittedTitle,
                style: GoogleFonts.lexend(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isQueued
                    ? AppLocalizations.of(context)!.offlineReportMessage
                    : AppLocalizations.of(context)!.onlineReportMessage,
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
                      isQueued
                          ? AppLocalizations.of(context)!.statusLabel
                          : AppLocalizations.of(context)!.reportIdLabel,
                      style: GoogleFonts.lexend(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isQueued
                          ? AppLocalizations.of(context)!.queuedStatus
                          : (reportId != null
                                ? '#${reportId.substring(0, 8)}...'
                                : AppLocalizations.of(context)!.sentStatus),
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
                child: CustomButton(
                  onPressed: () {
                    // Provider is already reset in submitReport
                    final router = GoRouter.of(context);
                    final reportsProvider = context
                        .read<ReportsStatusProvider>();
                    final auth = context.read<AuthProvider>();
                    final isUser = auth.userRole == UserRole.user;
                    Navigator.of(context).pop(); // Close dialog first!
                    reportsProvider.refreshReports(
                      userId: isUser ? auth.currentUser?.id : null,
                    );
                    router.go('/dashboard');
                  },
                  text: AppLocalizations.of(context)!.returnToDashboard,
                  type: ButtonType.secondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Date/time, notes and photos are edited on the details step, which is
  /// the page right below this one in the wizard stack.
  void _backToDetails() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/report/details');
    }
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
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/report'),
        ),
        title: Text(
          AppLocalizations.of(context)!.reviewReportTitle,
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
                    AppLocalizations.of(context)!.reviewReportDesc,
                    style: GoogleFonts.lexend(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Hazard Details
                  _buildSectionHeader(
                    AppLocalizations.of(context)!.hazardDetails,
                    onEdit: () => context.push('/report/severity'),
                    context: context,
                  ),
                  Consumer<ReportingProvider>(
                    builder: (context, provider, _) {
                      return Container(
                        decoration: _cardDecoration(),
                        child: Column(
                          children: [
                            _buildListItem(
                              icon: Icons.warning_amber_rounded,
                              iconColor: Colors.red,
                              iconBg: Colors.red.shade50,
                              label: AppLocalizations.of(context)!.hazardType,
                              value:
                                  provider.hazardType ??
                                  AppLocalizations.of(context)!.notSelected,
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
                              label: AppLocalizations.of(
                                context,
                              )!.severityLevelLabel,
                              value:
                                  provider.severity ??
                                  AppLocalizations.of(context)!.notSelected,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // Date & Time
                  _buildSectionHeader(
                    AppLocalizations.of(context)!.dateTimeLabel,
                    onEdit: _backToDetails,
                    context: context,
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
                          label: AppLocalizations.of(context)!.whenItOccurred,
                          value: isToday
                              ? '${AppLocalizations.of(context)!.todayAt} ${DateFormat('h:mm a').format(reportDate)}'
                              : '${DateFormat('MMM dd, yyyy').format(reportDate)} ${AppLocalizations.of(context)!.atTime} ${DateFormat('h:mm a').format(reportDate)}',
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // Location
                  _buildSectionHeader(
                    AppLocalizations.of(context)!.locationLabel,
                    onEdit: () => context.push('/report/location'),
                    context: context,
                  ),
                  Consumer<ReportingProvider>(
                    builder: (context, provider, _) {
                      return Container(
                        decoration: _cardDecoration(),
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (provider.latitude != null &&
                                provider.longitude != null)
                              SizedBox(
                                height: 120,
                                width: double.infinity,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: OSMLocationPicker(
                                    initialPosition: LatLng(
                                      provider.latitude!,
                                      provider.longitude!,
                                    ),
                                    isInteractive: false,
                                  ),
                                ),
                              )
                            else
                              Container(
                                height: 120,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.location_off,
                                      color: Colors.grey.shade400,
                                      size: 40,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Exact location unknown - the selected '
                                      'area will be used',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.lexend(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (provider.latitude != null &&
                                provider.locationIsApproximate)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  'Location approximate (area centre, no GPS '
                                  'fix)',
                                  style: GoogleFonts.lexend(
                                    fontSize: 12,
                                    color: Colors.orange.shade800,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 12),
                            Text(
                              provider.locationDetails ??
                                  AppLocalizations.of(context)!.notProvided,
                              style: GoogleFonts.lexend(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            if (provider.ward != null && provider.lga != null)
                              Text(
                                '${provider.ward}, ${provider.lga}',
                                style: GoogleFonts.lexend(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // Description
                  _buildSectionHeader(
                    AppLocalizations.of(context)!.monitorNotes,
                    onEdit: _backToDetails,
                    context: context,
                  ),
                  Consumer<ReportingProvider>(
                    builder: (context, provider, _) {
                      return Container(
                        decoration: _cardDecoration(),
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          provider.description ??
                              AppLocalizations.of(
                                context,
                              )!.noDescriptionProvided,
                          style: GoogleFonts.lexend(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                            height: 1.5,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // Evidence
                  _buildSectionHeader(
                    AppLocalizations.of(context)!.evidenceLabel,
                    onEdit: _backToDetails,
                    context: context,
                  ),
                  Consumer<ReportingProvider>(
                    builder: (context, provider, _) {
                      final photos = provider.photos;
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ...photos.map(
                              (photo) => Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade300,
                                    borderRadius: BorderRadius.circular(8),
                                    image: DecorationImage(
                                      image: FileImage(File(photo.path)),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (photos.length < 3)
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
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.add_a_photo,
                                      size: 20,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      AppLocalizations.of(context)!.addPhotoBtn,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
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
                onPressed: _isSubmitting ? null : _submitReport,
                isLoading: _isSubmitting,
                text: AppLocalizations.of(context)!.submitReportBtn,
                icon: Icons.send,
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

  Widget _buildSectionHeader(
    String title, {
    required VoidCallback onEdit,
    required BuildContext context,
  }) {
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
                AppLocalizations.of(context)!.editBtn,
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
}
