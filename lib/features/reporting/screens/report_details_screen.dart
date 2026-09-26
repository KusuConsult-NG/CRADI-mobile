import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:climate_app/shared/widgets/custom_button.dart';
import 'package:climate_app/core/utils/input_sanitizer.dart';
import 'package:climate_app/core/l10n/l10n.dart';

class ReportDetailsScreen extends StatefulWidget {
  const ReportDetailsScreen({super.key});

  @override
  State<ReportDetailsScreen> createState() => _ReportDetailsScreenState();
}

class _ReportDetailsScreenState extends State<ReportDetailsScreen> {
  final _descController = TextEditingController();
  late stt.SpeechToText _speech;
  bool _isListening = false;
  bool _speechAvailable = false;
  String _currentLocale = 'en_US';

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    // Returning here through the review screen's "Edit" links pushes a fresh
    // copy of this page; start from what the user already entered instead of
    // an empty field (which would wipe the description on "Review").
    _descController.text = context.read<ReportingProvider>().description ?? '';
    _initSpeech();
    _descController.addListener(_updateCharCount);
  }

  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onError: (error) {
          if (!mounted) return;
          setState(() => _isListening = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.reportDetailsSpeechError),
              backgroundColor: Colors.red,
            ),
          );
        },
        onStatus: (status) {
          // May fire after dispose (stopping the recogniser), so guard.
          if (!mounted) return;
          if (status == 'done' || status == 'notListening') {
            setState(() => _isListening = false);
          }
        },
      );

      // Get available locales
      if (_speechAvailable) {
        final locales = await _speech.locales();
        // Get current app locale
        if (!mounted || locales.isEmpty) return;
        final appLocaleCode = Localizations.localeOf(context).languageCode;

        // Try to find matching locale
        final matchingLocale = locales.firstWhere(
          (locale) => locale.localeId.startsWith(appLocaleCode),
          orElse: () => locales.firstWhere(
            (locale) => locale.localeId.startsWith('en'),
            orElse: () => locales.first,
          ),
        );
        setState(() => _currentLocale = matchingLocale.localeId);
      }
    } on Exception {
      _speechAvailable = false;
      if (mounted) setState(() {});
    }
  }

  void _updateCharCount() {
    setState(() {});
  }

  void _toggleListening() async {
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.speechNotAvailable),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_isListening) {
      await _speech.stop();
      if (!mounted) return;
      setState(() => _isListening = false);
    } else {
      setState(() => _isListening = true);

      await _speech.listen(
        onResult: (result) {
          if (!mounted) return;
          setState(() {
            // Programmatic text bypasses the input formatter: cap it too.
            final words = result.recognizedWords;
            const max = ReportingProvider.maxDescriptionLength;
            _descController.text = words.length > max
                ? words.substring(0, max)
                : words;
            // Move cursor to end
            _descController.selection = TextSelection.fromPosition(
              TextPosition(offset: _descController.text.length),
            );
          });
        },
        localeId: _currentLocale,
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.confirmation, // Continues through pauses
          cancelOnError: false, // Don't stop on errors
          partialResults: true, // Show results as user speaks
        ),
      );
    }
  }

  @override
  void dispose() {
    _descController.removeListener(_updateCharCount);
    _descController.dispose();
    _speech.stop();
    super.dispose();
  }

  // Pick image from camera
  Future<void> _pickImageFromCamera(ReportingProvider provider) async {
    try {
      await provider.pickImage(ImageSource.camera);
    } on ValidationException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.userMessage(context.l10n))));
      }
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.reportDetailsCameraUnavailable)),
        );
      }
    }
  }

  // Pick image from gallery
  Future<void> _pickImageFromGallery(ReportingProvider provider) async {
    try {
      await provider.pickImage(ImageSource.gallery);
    } on ValidationException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.userMessage(context.l10n))));
      }
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.reportDetailsGalleryError)),
        );
      }
    }
  }

  // Remove selected image
  void _removeImage(ReportingProvider provider, int index) {
    provider.removeImage(index);
  }

  Future<void> _selectDateTime(
    BuildContext context,
    ReportingProvider provider,
    DateTime selectedDate,
  ) async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primaryRed,
              onPrimary: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null && mounted) {
      if (!context.mounted) return;

      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(selectedDate),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(
                primary: AppColors.primaryRed,
                onPrimary: Colors.white,
                onSurface: AppColors.textPrimary,
              ),
            ),
            child: child!,
          );
        },
      );

      if (pickedTime != null) {
        final newDateTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );
        // An incident cannot happen in the future (today's date with a later
        // time is still selectable); the provider clamps it to now.
        final inFuture = newDateTime.isAfter(DateTime.now());
        provider.setReportDateTime(newDateTime);
        if (inFuture && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.reportDetailsFutureTime)),
          );
        }
      }
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
          onPressed: () => context.pop(),
        ),
        title: Text(
          context.l10n.reportDetailsTitle,
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
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Description Section
                  Text(
                    context.l10n.descriptionLabel,
                    style: GoogleFonts.lexend(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Stack(
                    children: [
                      TextField(
                        controller: _descController,
                        maxLines: 6,
                        // Stop typing at the limit instead of silently
                        // truncating the text on submit.
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(
                            ReportingProvider.maxDescriptionLength,
                          ),
                        ],
                        style: GoogleFonts.lexend(
                          fontSize: 16,
                          color: AppColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: context.l10n.describeHazardHint,
                          hintStyle: GoogleFonts.lexend(
                            color: Colors.grey.shade400,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.all(16),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: AppColors.primaryRed,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 12,
                        right: 12,
                        child: GestureDetector(
                          onTap: _toggleListening,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: EdgeInsets.all(_isListening ? 12 : 8),
                            decoration: BoxDecoration(
                              color: _isListening
                                  ? AppColors.primaryRed
                                  : AppColors.primaryRed.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                              boxShadow: _isListening
                                  ? [
                                      BoxShadow(
                                        color: AppColors.primaryRed.withValues(
                                          alpha: 0.3,
                                        ),
                                        blurRadius: 8,
                                        spreadRadius: 2,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Icon(
                              _isListening ? Icons.mic : Icons.mic_none,
                              color: _isListening
                                  ? Colors.white
                                  : AppColors.primaryRed,
                              size: _isListening ? 24 : 20,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _isListening ? Icons.mic : Icons.info_outline,
                            size: 16,
                            color: _isListening
                                ? AppColors.primaryRed
                                : Colors.green.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _isListening
                                ? context.l10n.listeningSpeakNow
                                : context.l10n.beSpecificLocationSeverity,
                            style: GoogleFonts.lexend(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: _isListening
                                  ? AppColors.primaryRed
                                  : Colors.green.shade600,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${_descController.text.length}/${ReportingProvider.maxDescriptionLength}',
                        style: GoogleFonts.lexend(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color:
                              _descController.text.length >
                                  ReportingProvider.maxDescriptionLength
                              ? Colors.red
                              : Colors.green.shade600,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                  Divider(color: Colors.grey.shade200),
                  const SizedBox(height: 24),

                  // Date & Time Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        context.l10n.whenDidThisOccur,
                        style: GoogleFonts.lexend(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.successGreen.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          context.l10n.optionalLabel,
                          style: GoogleFonts.lexend(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppColors.successGreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Consumer<ReportingProvider>(
                    builder: (context, provider, _) {
                      final selectedDate = provider.reportDateTime;
                      final isToday =
                          selectedDate.day == DateTime.now().day &&
                          selectedDate.month == DateTime.now().month &&
                          selectedDate.year == DateTime.now().year;

                      return GestureDetector(
                        onTap: () =>
                            _selectDateTime(context, provider, selectedDate),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryRed.withValues(
                                    alpha: 0.1,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.calendar_today,
                                  color: AppColors.primaryRed,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isToday
                                          ? context.l10n.todayLabel
                                          : _formatDate(selectedDate),
                                      style: GoogleFonts.lexend(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _formatTime(selectedDate),
                                      style: GoogleFonts.lexend(
                                        fontSize: 14,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.edit_calendar,
                                color: AppColors.primaryRed,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          context.l10n.tapToSelectDateTime,
                          style: GoogleFonts.lexend(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                  Divider(color: Colors.grey.shade200),
                  const SizedBox(height: 24),

                  // Evidence Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        context.l10n.evidenceLabel,
                        style: GoogleFonts.lexend(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryRed.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          context.l10n.max3Photos,
                          style: GoogleFonts.lexend(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryRed,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Consumer<ReportingProvider>(
                    builder: (context, provider, child) {
                      final images = provider.photos;

                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: images.length + (images.length < 3 ? 2 : 0),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                        itemBuilder: (context, index) {
                          // Show selected images first
                          if (index < images.length) {
                            // Pass provider to helper
                            return _buildImageThumbnail(provider, index);
                          }

                          // Camera button
                          if (index == images.length) {
                            return _buildCameraButton(provider);
                          }

                          // Gallery button
                          return _buildGalleryButton(provider);
                        },
                      );
                    },
                  ),

                  const SizedBox(height: 24),
                  // Offline Helper
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade100),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.offline_pin,
                          size: 20,
                          color: Colors.blue.shade600,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: GoogleFonts.lexend(
                                fontSize: 12,
                                color: AppColors.textPrimary,
                                height: 1.5,
                              ),
                              children: [
                                TextSpan(
                                  text: context.l10n.offlineModeReady,
                                  style: GoogleFonts.lexend(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                                TextSpan(text: context.l10n.offlineModeMessage),
                              ],
                            ),
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
              child: CustomButton(
                onPressed: () {
                  context.read<ReportingProvider>().setDescription(
                    // Stored as typed (no HTML escaping); only control
                    // characters/extra whitespace are removed.
                    InputSanitizer.cleanForStorage(
                      _descController.text,
                      preserveNewlines: true,
                      maxLength: ReportingProvider.maxDescriptionLength,
                    ),
                  );
                  context.push('/report/review');
                },
                text: context.l10n.reviewReportBtn,
                icon: Icons.arrow_forward,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return localizedDateFormat(context, 'MMM dd, yyyy').format(date);
  }

  String _formatTime(DateTime date) {
    return localizedDateFormat(context, 'h:mm a').format(date);
  }

  Widget _buildImageThumbnail(ReportingProvider provider, int index) {
    // Images from provider
    final images = provider.photos;
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            image: DecorationImage(
              image: FileImage(File(images[index].path)),
              fit: BoxFit.cover,
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () => _removeImage(provider, index),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 16, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCameraButton(ReportingProvider provider) {
    return InkWell(
      onTap: () => _pickImageFromCamera(provider),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.primaryRed.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primaryRed),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: AppColors.primaryRed,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add_a_photo,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.cameraBtn,
              style: GoogleFonts.lexend(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryRed,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGalleryButton(ReportingProvider provider) {
    return InkWell(
      onTap: () => _pickImageFromGallery(provider),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library, size: 28, color: Colors.green.shade600),
            const SizedBox(height: 4),
            Text(
              context.l10n.galleryBtn,
              style: GoogleFonts.lexend(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.green.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
