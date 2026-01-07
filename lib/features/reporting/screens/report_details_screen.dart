import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:climate_app/shared/widgets/custom_button.dart';

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
    _initSpeech();
    _descController.addListener(_updateCharCount);
  }

  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onError: (error) {
          setState(() => _isListening = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error: ${error.errorMsg}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            setState(() => _isListening = false);
          }
        },
      );

      // Get available locales
      if (_speechAvailable) {
        final locales = await _speech.locales();
        // Try to find English locale
        final enLocale = locales.firstWhere(
          (locale) => locale.localeId.startsWith('en'),
          orElse: () => locales.first,
        );
        setState(() => _currentLocale = enLocale.localeId);
      }
    } on Exception {
      setState(() => _speechAvailable = false);
    }
  }

  void _updateCharCount() {
    setState(() {});
  }

  void _toggleListening() async {
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Speech recognition not available'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    } else {
      setState(() => _isListening = true);

      await _speech.listen(
        onResult: (result) {
          setState(() {
            _descController.text = result.recognizedWords;
            // Move cursor to end
            _descController.selection = TextSelection.fromPosition(
              TextPosition(offset: _descController.text.length),
            );
          });
        },
        localeId: _currentLocale,
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          cancelOnError: true,
          partialResults: true,
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
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: ${e.toString()}')),
        );
      }
    }
  }

  // Pick image from gallery
  Future<void> _pickImageFromGallery(ReportingProvider provider) async {
    try {
      await provider.pickImage(ImageSource.gallery);
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gallery error: ${e.toString()}')),
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
        provider.setReportDateTime(newDateTime);
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
          'Report Details',
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
                    'Description',
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
                        style: GoogleFonts.lexend(
                          fontSize: 16,
                          color: AppColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText:
                              'Describe the hazard here (e.g. flood levels rising, bridge collapsed)...',
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
                                ? 'Listening... Speak now'
                                : 'Be specific about location and severity.',
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
                        '${_descController.text.length}/500',
                        style: GoogleFonts.lexend(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: _descController.text.length > 500
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
                        'When Did This Occur?',
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
                          'Optional',
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
                                          ? 'Today'
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
                          'Tap to select date & time. Defaults to now if not changed.',
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
                        'Evidence',
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
                          'Max 3 photos',
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
                                  text: 'Offline Mode Ready: ',
                                  style: GoogleFonts.lexend(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                                const TextSpan(
                                  text:
                                      'Your photos will be compressed automatically. Reports are saved locally until you have internet.',
                                ),
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
                    _descController.text,
                  );
                  context.push('/report/review');
                },
                text: 'Review Report',
                icon: Icons.arrow_forward,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return DateFormat('MMM dd, yyyy').format(date);
  }

  String _formatTime(DateTime date) {
    return DateFormat('h:mm a').format(date);
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
              'Camera',
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
              'Gallery',
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
