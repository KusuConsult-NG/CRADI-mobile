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
import 'package:climate_app/core/constants/hazards.dart';
import 'package:climate_app/core/l10n/severity_label.dart';
import 'package:climate_app/shared/widgets/custom_button.dart';
import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/core/l10n/l10n.dart';

/// Query flag marking a wizard step opened from the review screen's "Edit"
/// link. Such a step pops back to the review on Continue, so editing never
/// stacks a second copy of the remaining wizard pages.
const String kReviewEditQuery = 'edit';
const String _kReviewEditValue = 'review';

/// Location of wizard [step] (e.g. 'severity') opened for editing from review.
String reviewEditLocation(String step) =>
    '/report/$step?$kReviewEditQuery=$_kReviewEditValue';

/// Whether [uri] is a wizard step opened from the review screen.
bool isReviewEdit(Uri uri) =>
    uri.queryParameters[kReviewEditQuery] == _kReviewEditValue;

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
              (result['message'] as LocalizedText?)?.call(context.l10n) ??
                  context.l10n.submissionFailed,
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
            ErrorHandler.handleError(
              e,
              context.l10n,
              context: 'Report Submission',
            ),
          ),
        ),
      );
    }
  }

  void _showSuccessDialog(bool isQueued, {String? reportId}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        void returnToDashboard() {
          // Provider is already reset in submitReport
          final router = GoRouter.of(context);
          final reportsProvider = context.read<ReportsStatusProvider>();
          final auth = context.read<AuthProvider>();
          final isUser = auth.userRole == UserRole.user;
          Navigator.of(context).pop(); // Close dialog first!
          reportsProvider.refreshReports(
            userId: isUser ? auth.currentUser?.id : null,
          );
          router.go('/dashboard');
        }

        // The report is already submitted/queued: Android Back must not
        // drop the user back onto the (reset) review page.
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) returnToDashboard();
          },
          child: Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
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
                        ? context.l10n.savedForLater
                        : context.l10n.reportSubmittedTitle,
                    style: GoogleFonts.lexend(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isQueued
                        ? context.l10n.offlineReportMessage
                        : context.l10n.onlineReportMessage,
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
                              ? context.l10n.statusLabel
                              : context.l10n.reportIdLabel,
                          style: GoogleFonts.lexend(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isQueued
                              ? context.l10n.queuedStatus
                              : (reportId != null
                                    ? '#${reportId.substring(0, 8)}...'
                                    : context.l10n.sentStatus),
                          style: GoogleFonts.robotoMono(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isQueued
                                ? Colors.orange
                                : AppColors.primaryRed,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: CustomButton(
                      onPressed: returnToDashboard,
                      text: context.l10n.returnToDashboard,
                      type: ButtonType.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
          context.l10n.reviewReportTitle,
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
                    context.l10n.reviewReportDesc,
                    style: GoogleFonts.lexend(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Hazard Details
                  _buildSectionHeader(
                    context.l10n.hazardDetails,
                    onEdit: () => context.push(reviewEditLocation('severity')),
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
                              label: context.l10n.hazardType,
                              value: provider.hazardType != null
                                  ? Hazard.labelFor(
                                      provider.hazardType,
                                      context.l10n,
                                    )
                                  : context.l10n.notSelected,
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
                              label: context.l10n.severityLevelLabel,
                              value: provider.severity != null
                                  ? severityLabel(
                                      context.l10n,
                                      provider.severity,
                                    )
                                  : context.l10n.notSelected,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // Date & Time
                  _buildSectionHeader(
                    context.l10n.dateTimeLabel,
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
                          label: context.l10n.whenItOccurred,
                          value: isToday
                              ? context.l10n.reviewDateTodayAt(
                                  localizedDateFormat(
                                    context,
                                    'h:mm a',
                                  ).format(reportDate),
                                )
                              : context.l10n.reviewDateOnAt(
                                  localizedDateFormat(
                                    context,
                                    'MMM dd, yyyy',
                                  ).format(reportDate),
                                  localizedDateFormat(
                                    context,
                                    'h:mm a',
                                  ).format(reportDate),
                                ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // Location
                  _buildSectionHeader(
                    context.l10n.locationLabel,
                    onEdit: () => context.push(reviewEditLocation('location')),
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
                                      context.l10n.reviewLocationUnknown,
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
                                  context.l10n.reviewLocationApproximate,
                                  style: GoogleFonts.lexend(
                                    fontSize: 12,
                                    color: Colors.orange.shade800,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 12),
                            Text(
                              provider.locationDetails ??
                                  context.l10n.notProvided,
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
                    context.l10n.monitorNotes,
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
                              context.l10n.noDescriptionProvided,
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
                    context.l10n.evidenceLabel,
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
                                      context.l10n.addPhotoBtn,
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
                text: context.l10n.submitReportBtn,
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
                context.l10n.editBtn,
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
