import 'package:climate_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class VerificationRequestScreen extends StatelessWidget {
  const VerificationRequestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: AppColors.textPrimary),
            onPressed: () => context.pop(),
        ),
        title: Text(
          'Verify Request #4092',
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
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Headline & Urgency Badge
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                         children: [
                           Container(
                             padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                             decoration: BoxDecoration(
                               color: AppColors.errorRed.withValues(alpha: 0.1),
                               borderRadius: BorderRadius.circular(16),
                               border: Border.all(color: AppColors.errorRed.withValues(alpha: 0.2)),
                             ),
                             child: Row(
                               children: [
                                 const Icon(Icons.warning, size: 16, color: AppColors.errorRed),
                                 const SizedBox(width: 4),
                                 Text('CRITICAL PRIORITY', style: GoogleFonts.lexend(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.errorRed)),
                               ],
                             ),
                           ),
                           const Spacer(),
                           Text('Pending verification', style: GoogleFonts.lexend(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade500)),
                         ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Flash Flood Alert',
                        style: GoogleFonts.lexend(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.textPrimary, letterSpacing: -0.5),
                      ),
                    ],
                  ),
                ),

                // Reporter Profile
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade100),
                    ),
                    child: Row(
                      children: [
                         Container(
                           width: 40, height: 40,
                           decoration: const BoxDecoration(
                             shape: BoxShape.circle,
                             image: DecorationImage(
                               image: NetworkImage('https://lh3.googleusercontent.com/aida-public/AB6AXuCpeWwMBG849UGgb3aAozjYd4r63nTLWvUv7UR9_OfZITVrH43hZBK2jvbgo8EtokVn8Nl8kt-0cUBxfaWkePhfOe4QZLPVq9Yuo6qC1B9kn0WRVv4x_WgnzeiW7avDjEasaB6ss5-ALm98dtzRm5CHeSpsdG5ibwuarFBbMB4ZzhIhV2SBi-rfU1M7RX1ywNSndfbAGOyItz2DoiQ7HpHM6tS4mK1W2Le7n3OXAUI1iWUhu-_OuFHMXEk5YU1Oo6j3sPTgD4A57lqe'),
                               fit: BoxFit.cover,
                             ),
                           ),
                         ),
                         const SizedBox(width: 12),
                         Expanded(
                           child: Column(
                             crossAxisAlignment: CrossAxisAlignment.start,
                             children: [
                               Text('Musa Ibrahim', style: GoogleFonts.lexend(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                               Text('Field Monitor • Makurdi Zone', style: GoogleFonts.lexend(fontSize: 12, color: Colors.grey.shade500)),
                             ],
                           ),
                         ),
                         Row(
                           children: [
                             _buildCircleBtn(Icons.chat),
                             const SizedBox(width: 8),
                             _buildCircleBtn(Icons.call),
                           ],
                         ),
                      ],
                    ),
                  ),
                ),

                // Attached Evidence
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text('Attached Evidence', style: GoogleFonts.lexend(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
                ),
                SizedBox(
                  height: 150,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _buildMediaCard('https://lh3.googleusercontent.com/aida-public/AB6AXuAW8tzeb71fXHKZg_p8LvRhI24GjtjLu4a3BbcmE0NSC3yvctzvRayOLJTlbOB9JqD2V2Q1O68hElwsJz-4aAUoqcHWFSHSbEdZv7btzqNmA7ALNq2LbRxkaAVjwhb9oJX2THcsIrINMbXdVrNgNTNBleHQPy57J8vtr6MNifmU9ja_ITZgNYSQ_pcSKE-vFnvUuWCg1aJvi1rxlBx9cKbD0V1gmRTExAo0Qwtn995K8Mf-_7jWKpdECKlNlFs29iQwOBLFfkYX6xp3', 'Photo 1/2'),
                      const SizedBox(width: 12),
                      _buildMediaCard('https://lh3.googleusercontent.com/aida-public/AB6AXuCloqPpiiarWlDrRG9olfrEiz06GzRIGbrPeRZ_ubC7MiCYBoTCE-L_OgfONf667JXYNZ0plUsrjoGaNM9BybaEeGWs75KP3ac7-5YwG3RrOTZZFJ91Skyz1EkIG4dLrHkDhxqCCmW5NrfjHHFv5f8K0OlkGHtMvmPtEe4LUxyL_XOGxAe7yM0l5K0C2IOS70QX89Poxkr_7sf9pLphjYgJj5APOnBUEM99_SRMIrGOlnZ2nWt6yCsNDo5ZHaXPx2YGhEZnZWcHvgy_', 'Photo 2/2'),
                      const SizedBox(width: 12),
                      Container(
                        width: 200,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(child: Image.network('https://lh3.googleusercontent.com/aida-public/AB6AXuD_gpUxEvi9-ry23P1Re6pgFbmttW87Dm2-BPyWMdcqyVEdrBXek14OntFESxGQejFNMtWXHz4LRLhvz9omxNX9PIxcrz4TRCdU4BBVgzq4yl1PTMKH5TPFoBV5-yqoHRwA-hqWznyWhCO6Fdcsxs7LuHn8t6noDjDobYr2uyt2Z1-EoBG3oweD6xUnLYyZaBOPQ_OndTHMna8JUh0VhAtKSbHWFzEXx7ll7H40BDn_oB4-ufeSKtANweKqnzqhtZRDUOYaCmqzilFt', fit: BoxFit.cover, opacity: const AlwaysStoppedAnimation(0.8))),
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: AppColors.errorRed.withValues(alpha: 0.2), shape: BoxShape.circle),
                                child: Container(
                                  width: 16, height: 16,
                                  decoration: const BoxDecoration(color: AppColors.errorRed, shape: BoxShape.circle, border: Border.fromBorderSide(BorderSide(color: Colors.white, width: 2))),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Description List
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDetailRow('Description', 'River Benue levels rising rapidly due to heavy rainfall upstream. Water has breached the embankment and entered the Wadata market area. Traders are evacuating.', isFullWidth: true, isLast: false),
                        const Divider(height: 24, color: Colors.grey),
                        Row(
                          children: [
                            Expanded(child: _buildDetailRow('When Occurred', 'Dec 12, 2024 at 9:15 PM')),
                            Expanded(child: _buildDetailRow('Time Reported', '20 mins ago')),
                          ],
                        ),
                        const Divider(height: 24, color: Colors.grey),
                         Row(
                           children: [
                             Expanded(child: _buildDetailRow('Location', 'Makurdi, Benue State')),
                             Expanded(child: _buildDetailRow('Report ID', '#4092')),
                           ],
                         ),
                        const Divider(height: 24, color: Colors.grey),
                        Row(
                          children: [
                            Expanded(child: _buildIconDetail(Icons.water_drop, 'Hazard Type', 'Flood', Colors.grey)),
                            Expanded(child: _buildIconDetail(Icons.error, 'Severity', 'Critical', AppColors.errorRed)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                
                // Comment Input
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Add Context (Optional)', style: GoogleFonts.lexend(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'e.g. Confirmed with local chief, water levels are indeed high...',
                      hintStyle: GoogleFonts.lexend(color: Colors.grey.shade400, fontSize: 14),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                      suffixIcon: const Icon(Icons.edit_note, color: Colors.grey),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Sticky Action Footer
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, -2))],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.close, size: 20),
                      label: const Text('Cannot Confirm'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey.shade700,
                        side: BorderSide(color: Colors.grey.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2, // 1.5 in Tailwind usually means wider
                    child: ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.check, size: 20),
                      label: const Text('Confirm This'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.successGreen,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircleBtn(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.grey.shade600, size: 20),
    );
  }

  Widget _buildMediaCard(String url, String label) {
    return Container(
      width: 250,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        image: DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
      ),
      child: Stack(
        children: [
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(4)),
              child: Text(label, style: GoogleFonts.lexend(fontSize: 10, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconDetail(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, color: color == AppColors.errorRed ? color : Colors.grey.shade400, size: 24),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: GoogleFonts.lexend(fontSize: 12, color: Colors.grey.shade500)),
            Text(value, style: GoogleFonts.lexend(fontSize: 14, fontWeight: FontWeight.bold, color: color == AppColors.errorRed ? color : AppColors.textPrimary)),
          ],
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isFullWidth = false, bool isLast = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.lexend(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.lexend(fontSize: 14, color: AppColors.textPrimary, height: 1.5),
        ),
      ],
    );
  }
}
