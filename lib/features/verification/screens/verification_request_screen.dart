import 'package:climate_app/core/services/appwrite_service.dart';
import 'package:flutter/material.dart';

/// Verification request screen - submit verification request
/// This is a simplified stub implementation using Appwrite
class VerificationRequestScreen extends StatefulWidget {
  const VerificationRequestScreen({super.key});

  @override
  State<VerificationRequestScreen> createState() =>
      _VerificationRequestScreenState();
}

class _VerificationRequestScreenState extends State<VerificationRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  String _selectedHazard = 'Flooding';
  String _selectedSeverity = 'medium';
  bool _isLoading = false;

  final List<String> _hazards = [
    'Flooding',
    'Extreme Heat',
    'Drought',
    'Windstorms',
    'Wildfires',
    'Erosion',
    'Pest Outbreak',
    'Crop Disease',
  ];

  final List<Map<String, String>> _severities = [
    {'value': 'low', 'label': 'Low'},
    {'value': 'medium', 'label': 'Medium'},
    {'value': 'high', 'label': 'High'},
    {'value': 'critical', 'label': 'Critical'},
  ];

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final appwrite = AppwriteService();
      final user = await appwrite.getCurrentUser();

      if (user == null) {
        throw Exception('User not authenticated');
      }

      await appwrite.createDocument(
        collectionId: AppwriteService.reportsCollectionId,
        data: {
          'userId': user.$id,
          'description': _descriptionController.text,
          'hazardType': _selectedHazard,
          'severity': _selectedSeverity,
          'status': 'pending',
          'submittedAt': DateTime.now().toIso8601String(),
          'locationDetails': 'User Requested Verification',
          'latitude': 0.0,
          'longitude': 0.0,
          'isAlert':
              _selectedSeverity == 'critical' || _selectedSeverity == 'high',
          'verificationCount': 0,
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification request submitted')),
        );
        Navigator.of(context).pop();
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request Verification')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedHazard,
              decoration: const InputDecoration(
                labelText: 'Hazard Type',
                border: OutlineInputBorder(),
              ),
              items: _hazards
                  .map((h) => DropdownMenuItem(value: h, child: Text(h)))
                  .toList(),
              onChanged: (val) => setState(() => _selectedHazard = val!),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedSeverity,
              decoration: const InputDecoration(
                labelText: 'Severity',
                border: OutlineInputBorder(),
              ),
              items: _severities
                  .map(
                    (s) => DropdownMenuItem(
                      value: s['value'],
                      child: Text(s['label']!),
                    ),
                  )
                  .toList(),
              onChanged: (val) => setState(() => _selectedSeverity = val!),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Describe what needs verification...',
                border: OutlineInputBorder(),
              ),
              maxLines: 5,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a description';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _submitRequest,
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : const Text('Submit Request'),
            ),
          ],
        ),
      ),
    );
  }
}
