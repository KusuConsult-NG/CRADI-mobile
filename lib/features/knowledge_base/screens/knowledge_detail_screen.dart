import 'package:flutter/material.dart';

class KnowledgeDetailScreen extends StatelessWidget {
  final Map<String, dynamic> guide;

  const KnowledgeDetailScreen({super.key, required this.guide});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(guide['title'])),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.grey.shade200,
              child: const Row(
                children: [
                  Icon(Icons.offline_pin, color: Colors.green),
                  SizedBox(width: 8),
                  Text('Available Offline'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(guide['title'], style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            const Text(
              'This is a placeholder for the full guide content. In the production app, this would contain rich text, images, and step-by-step instructions loaded from a local database or PDF renderer.',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 24),
            const Text('Related Topics', style: TextStyle(fontWeight: FontWeight.bold)),
            const ListTile(title: Text('Safety Protocol A')),
            const ListTile(title: Text('Reporting Protocol B')),
          ],
        ),
      ),
    );
  }
}
