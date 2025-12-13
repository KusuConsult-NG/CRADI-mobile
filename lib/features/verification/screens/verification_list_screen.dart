import 'package:climate_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

class VerificationListScreen extends StatefulWidget {
  const VerificationListScreen({super.key});

  @override
  State<VerificationListScreen> createState() => _VerificationListScreenState();
}

class _VerificationListScreenState extends State<VerificationListScreen> {
  // Mock Data
  final List<Map<String, dynamic>> _reports = [
    {
      'id': '101',
      'hazard': 'Flooding',
      'severity': 'High',
      'location': 'Daffo Ward, Bokkos',
      'reporter': 'EWM-056',
      'time': '10 mins ago',
      'description': 'Water levels rising rapidly near the bridge.',
      'color': AppColors.hazardFlood,
    },
    {
      'id': '102',
      'hazard': 'Windstorm',
      'severity': 'Medium',
      'location': 'Daffo Ward, Bokkos',
      'reporter': 'EWM-012',
      'time': '25 mins ago',
      'description': 'Roof blew off community hall.',
      'color': AppColors.hazardWind,
    },
  ];

  void _verifyReport(String id, bool isConfirmed) {
    setState(() {
      _reports.removeWhere((r) => r['id'] == id);
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isConfirmed ? 'Report Verified' : 'Report Rejected'),
        backgroundColor: isConfirmed ? AppColors.successGreen : AppColors.errorRed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pending Verification')),
      body: _reports.isEmpty
          ? const Center(child: Text('No pending reports to verify'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _reports.length,
              itemBuilder: (context, index) {
                final report = _reports[index];
                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.warning, color: report['color'] as Color),
                            const SizedBox(width: 8),
                            Text(
                              report['hazard'] as String,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                report['severity'] as String,
                                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text('Location: ${report['location']}'),
                        Text('By: ${report['reporter']} • ${report['time']}'),
                        const SizedBox(height: 12),
                        Text(report['description'] as String, style: const TextStyle(fontStyle: FontStyle.italic)),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _verifyReport(report['id'] as String, false),
                                icon: const Icon(Icons.close, color: Colors.red),
                                label: const Text('Reject', style: TextStyle(color: Colors.red)),
                                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _verifyReport(report['id'] as String, true),
                                icon: const Icon(Icons.check, color: Colors.white),
                                label: const Text('Confirm'),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
