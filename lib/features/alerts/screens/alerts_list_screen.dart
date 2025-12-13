import 'package:climate_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class AlertsListScreen extends StatefulWidget {
  const AlertsListScreen({super.key});

  @override
  State<AlertsListScreen> createState() => _AlertsListScreenState();
}

class _AlertsListScreenState extends State<AlertsListScreen> {
  int _selectedFilterIndex = 0;
  final List<String> _filters = ['All Alerts', 'Floods', 'Conflict', 'Drought', 'Fire'];

  final List<Map<String, dynamic>> _allAlerts = [
    {
      'title': 'Flash Flood Warning',
      'time': '2h ago',
      'location': 'Makurdi LGA, Benue State',
      'icon': Icons.flood,
      'color': AppColors.errorRed,
      'severity': 'High Severity',
      'status': 'Pending',
      'statusColor': Colors.orange,
      'category': 'Floods',
    },
    {
       'title': 'Community Unrest',
       'time': '5h ago',
       'location': 'Jos North, Plateau State',
       'icon': Icons.shield,
       'color': Colors.orange,
       'severity': 'Moderate',
       'status': 'Acknowledged',
       'statusColor': Colors.blue,
       'category': 'Conflict',
    },
    {
       'title': 'Heatwave Advisory',
       'time': 'Yesterday',
       'location': 'Lafia, Nasarawa State',
       'icon': Icons.wb_sunny,
       'color': AppColors.successGreen,
       'severity': null,
       'status': 'Resolved',
       'statusColor': AppColors.successGreen,
       'category': 'Drought', // Maps to Drought/Heat
    },
    {
       'title': 'Bush Fire Alert',
       'time': 'Oct 22',
       'location': 'Otukpo, Benue State',
       'icon': Icons.local_fire_department,
       'color': AppColors.errorRed,
       'severity': 'High Severity',
       'status': 'Resolved',
       'statusColor': AppColors.successGreen,
       'category': 'Fire',
    },
  ];

  List<Map<String, dynamic>> get _filteredAlerts {
    if (_selectedFilterIndex == 0) return _allAlerts;
    final filter = _filters[_selectedFilterIndex];
    return _allAlerts.where((alert) => alert['category'] == filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        // leading: Automatically implied by shell or can be explicit if needed. 
        // Logic for shell navigation usually handles this, but since we are modifying it to resemble Stitch which has a back button in "Alert History" top bar (Wait, Stitch has back button? Yes code.html line 46 has arrow_back_ios_new). 
        // But in my app this is a main tab. Main tabs usually don't have back buttons.
        // However, if I follow design exactly, I should put a back button? 
        // OR is this supposed to be a "History" view accessed from somewhere?
        // Stitch has "Alerts" in bottom nav. So it should probably NOT have a back button if it's the root of the tab.
        // But the design shows one. Maybe it pushes a defined history view?
        // I'll stick to standard tab behavior (no back button) OR add a "Search" or "Filter" action.
        // The design has a "Filter" button on the right.
        title: Text(
          'Alert History',
          style: GoogleFonts.lexend(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list, color: AppColors.textPrimary),
            onPressed: () {},
          ),
        ],
        backgroundColor: AppColors.background.withValues(alpha: 0.95),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.grey.shade200, height: 1.0),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/report'),
        backgroundColor: AppColors.successGreen,
        child: const Icon(Icons.add_alert, color: Colors.black, size: 28),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 80),
        child: Column(
          children: [
            // Search Bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search location, hazard, or ID...',
                    hintStyle: GoogleFonts.lexend(color: Colors.grey.shade400),
                    prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
            ),

            // Meta Text
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   Text('SYNC STATUS', style: GoogleFonts.lexend(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade500, letterSpacing: 1.0)),
                   Row(
                     children: [
                       Container(
                         width: 8, height: 8,
                         decoration: const BoxDecoration(color: AppColors.successGreen, shape: BoxShape.circle),
                       ),
                       const SizedBox(width: 8),
                       Text('Online • Just now', style: GoogleFonts.lexend(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.successGreen)),
                     ],
                   ),
                ],
              ),
            ),

            const SizedBox(height: 12),

             // Filters
             SizedBox(
               height: 36,
               child: ListView.separated(
                 padding: const EdgeInsets.symmetric(horizontal: 16),
                 scrollDirection: Axis.horizontal,
                 itemCount: _filters.length,
                 separatorBuilder: (c, i) => const SizedBox(width: 8),
                 itemBuilder: (context, index) {
                   final isSelected = _selectedFilterIndex == index;
                   return ChoiceChip(
                     label: Text(_filters[index]),
                     selected: isSelected,
                     onSelected: (v) => setState(() => _selectedFilterIndex = index),
                     labelStyle: GoogleFonts.lexend(
                       fontWeight: FontWeight.w600,
                       color: isSelected ? Colors.black : Colors.grey.shade700,
                       fontSize: 12,
                     ),
                     selectedColor: AppColors.successGreen,
                     backgroundColor: Colors.white,
                     padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                     shape: RoundedRectangleBorder(
                       borderRadius: BorderRadius.circular(20),
                       side: BorderSide(color: isSelected ? Colors.transparent : Colors.grey.shade200),
                     ),
                     showCheckmark: false,
                   );
                 },
               ),
             ),

             const SizedBox(height: 16),

             // Alert Feed
             ListView.builder(
               shrinkWrap: true,
               physics: const NeverScrollableScrollPhysics(),
               padding: const EdgeInsets.symmetric(horizontal: 16),
               itemCount: _filteredAlerts.length,
               itemBuilder: (context, index) {
                  final alert = _filteredAlerts[index];
                  return Column(
                    children: [
                      _buildAlertCard(
                        title: alert['title'],
                        time: alert['time'],
                        location: alert['location'],
                        icon: alert['icon'],
                        color: alert['color'],
                        severity: alert['severity'],
                        status: alert['status'],
                        statusColor: alert['statusColor'],
                      ),
                      const SizedBox(height: 12),
                    ],
                  );
               },
             ),

             const SizedBox(height: 24),
             Center(
               child: TextButton(
                 onPressed: () {},
                 child: Text('Load older alerts', style: GoogleFonts.lexend(color: Colors.grey.shade500)),
               ),
             ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertCard({
    required String title,
    required String time,
    required String location,
    required IconData icon,
    required Color color,
    String? severity,
    required String status,
    required Color statusColor,
  }) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(width: 6, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: color, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: GoogleFonts.lexend(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 2,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                time,
                                style: GoogleFonts.lexend(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            location,
                            style: GoogleFonts.lexend(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              if (severity != null)
                                _buildTag(severity, color),
                              _buildTag(status, statusColor),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        text,
        style: GoogleFonts.lexend(fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}
