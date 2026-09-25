import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'dart:developer' as developer;

/// Admin Knowledge Base Management screen.
/// Allows admins to add, edit, and delete knowledge base guides.
class AdminKnowledgeScreen extends StatefulWidget {
  const AdminKnowledgeScreen({super.key});

  @override
  State<AdminKnowledgeScreen> createState() => _AdminKnowledgeScreenState();
}

class _AdminKnowledgeScreenState extends State<AdminKnowledgeScreen> {
  String _categoryFilter = 'All';

  static const _categories = [
    'All',
    'Flood',
    'Fire',
    'Erosion',
    'Storm',
    'Earthquake',
    'Disease',
    'Conflict',
    'General',
  ];

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _knowledgeStream;

  @override
  void initState() {
    super.initState();
    _knowledgeStream = FirebaseFirestore.instance
        .collection(AppConfig.knowledgeBaseCollection)
        .orderBy('updatedAt', descending: true)
        .snapshots();
  }

  Future<void> _deleteGuide(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Guide', style: GoogleFonts.lexend()),
        content: Text(
          'Are you sure you want to delete this guide? This cannot be undone.',
          style: GoogleFonts.lexend(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance
            .collection(AppConfig.knowledgeBaseCollection)
            .doc(id)
            .delete();
      } on FirebaseException catch (e) {
        developer.log('Guide delete failed: $e', name: 'AdminKnowledgeScreen');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not delete guide.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      developer.log('Guide deleted: $id', name: 'AdminKnowledgeScreen');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Guide deleted'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _openGuideForm({Map<String, dynamic>? existing, String? docId}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _GuideFormSheet(
        existing: existing,
        docId: docId,
        categories: _categories.where((c) => c != 'All').toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Knowledge Management',
          style: GoogleFonts.lexend(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.primaryRed,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openGuideForm(),
        backgroundColor: AppColors.primaryRed,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(
          'Add Guide',
          style: GoogleFonts.lexend(fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          // ── Category filter ──
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _categories.map((c) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(c, style: GoogleFonts.lexend(fontSize: 12)),
                      selected: _categoryFilter == c,
                      selectedColor: AppColors.primaryRed,
                      labelStyle: TextStyle(
                        color: _categoryFilter == c ? Colors.white : null,
                      ),
                      onSelected: (_) => setState(() => _categoryFilter = c),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // ── Guides list ──
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _knowledgeStream,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      'Error loading guides',
                      style: GoogleFonts.lexend(color: Colors.red),
                    ),
                  );
                }
                final allDocs = snap.data?.docs ?? [];

                // Client-side filtering
                final docs = allDocs.where((d) {
                  final data = d.data();
                  if (_categoryFilter != 'All') {
                    final hazard = data['hazardType'] as String? ?? '';
                    if (hazard != _categoryFilter.toLowerCase()) return false;
                  }
                  return true;
                }).toList();

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.menu_book_outlined,
                          size: 48,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No guides found',
                          style: GoogleFonts.lexend(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => _openGuideForm(),
                          icon: const Icon(Icons.add),
                          label: const Text('Add the first guide'),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final d = docs[i].data();
                    final id = docs[i].id;
                    final hazardType =
                        d['hazardType'] as String? ??
                        d['category'] as String? ??
                        'general';
                    final color = _categoryColor(hazardType);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _categoryIcon(hazardType),
                            color: color,
                            size: 22,
                          ),
                        ),
                        title: Text(
                          d['title'] as String? ?? 'Untitled',
                          style: GoogleFonts.lexend(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d['source'] as String? ?? '',
                              style: GoogleFonts.lexend(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                hazardType.toUpperCase(),
                                style: GoogleFonts.lexend(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: color,
                                ),
                              ),
                            ),
                          ],
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) {
                            if (action == 'edit') {
                              _openGuideForm(existing: d, docId: id);
                            }
                            if (action == 'delete') _deleteGuide(id);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('✏️ Edit'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(
                                '🗑️ Delete',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _categoryColor(String hazardType) {
    switch (hazardType.toLowerCase()) {
      case 'flood':
        return Colors.blue;
      case 'fire':
      case 'wildfires':
        return Colors.red;
      case 'erosion':
        return Colors.brown;
      case 'storm':
        return Colors.indigo;
      case 'earthquake':
        return Colors.deepOrange;
      case 'disease':
      case 'epidemic':
        return Colors.green;
      case 'conflict':
        return Colors.red.shade900;
      default:
        return Colors.teal;
    }
  }

  IconData _categoryIcon(String hazardType) {
    switch (hazardType.toLowerCase()) {
      case 'flood':
        return Icons.water;
      case 'fire':
      case 'wildfires':
        return Icons.local_fire_department;
      case 'erosion':
        return Icons.terrain;
      case 'storm':
        return Icons.thunderstorm;
      case 'earthquake':
        return Icons.vibration;
      case 'disease':
      case 'epidemic':
        return Icons.coronavirus_outlined;
      case 'conflict':
        return Icons.shield_outlined;
      default:
        return Icons.menu_book_outlined;
    }
  }
}

class _GuideFormSheet extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final String? docId;
  final List<String> categories;

  const _GuideFormSheet({this.existing, this.docId, required this.categories});

  @override
  State<_GuideFormSheet> createState() => _GuideFormSheetState();
}

class _GuideFormSheetState extends State<_GuideFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;
  late final TextEditingController _sourceCtrl;
  late String _selectedCategory;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleCtrl = TextEditingController(text: e?['title'] as String? ?? '');
    _contentCtrl = TextEditingController(text: e?['content'] as String? ?? '');
    _sourceCtrl = TextEditingController(text: e?['source'] as String? ?? '');
    final hazardType = e?['hazardType'] as String? ?? '';
    _selectedCategory = widget.categories.firstWhere(
      (c) => c.toLowerCase() == hazardType.toLowerCase(),
      orElse: () => widget.categories.first,
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _sourceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final data = {
      'title': _titleCtrl.text.trim(),
      'content': _contentCtrl.text.trim(),
      'source': _sourceCtrl.text.trim(),
      'category': _selectedCategory,
      'hazardType': _selectedCategory.toLowerCase(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      final col = FirebaseFirestore.instance.collection(
        AppConfig.knowledgeBaseCollection,
      );
      if (widget.docId != null) {
        await col.doc(widget.docId).update(data);
        developer.log(
          'Guide updated: ${widget.docId}',
          name: 'AdminKnowledgeScreen',
        );
      } else {
        data['createdAt'] = FieldValue.serverTimestamp();
        await col.add(data);
        developer.log('Guide created', name: 'AdminKnowledgeScreen');
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.docId != null ? 'Guide updated' : 'Guide created',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ErrorHandler.handleError(e, context: 'Knowledge Base'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Text(
                widget.docId != null ? 'Edit Guide' : 'New Guide',
                style: GoogleFonts.lexend(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 20),

              // Category
              DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                decoration: InputDecoration(
                  labelText: 'Category / Hazard Type',
                  labelStyle: GoogleFonts.lexend(fontSize: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.category_outlined),
                ),
                style: GoogleFonts.lexend(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
                items: widget.categories
                    .map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(c, style: GoogleFonts.lexend(fontSize: 14)),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedCategory = v!),
              ),
              const SizedBox(height: 12),

              // Title
              TextFormField(
                controller: _titleCtrl,
                style: GoogleFonts.lexend(),
                decoration: InputDecoration(
                  labelText: 'Guide Title',
                  labelStyle: GoogleFonts.lexend(fontSize: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.title),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),

              // Source
              TextFormField(
                controller: _sourceCtrl,
                style: GoogleFonts.lexend(),
                decoration: InputDecoration(
                  labelText: 'Source (e.g. NEMA, WHO)',
                  labelStyle: GoogleFonts.lexend(fontSize: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.source_outlined),
                ),
              ),
              const SizedBox(height: 12),

              // Content
              TextFormField(
                controller: _contentCtrl,
                style: GoogleFonts.lexend(fontSize: 13),
                maxLines: 8,
                decoration: InputDecoration(
                  labelText: 'Content (Markdown supported)',
                  labelStyle: GoogleFonts.lexend(fontSize: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignLabelWithHint: true,
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          widget.docId != null
                              ? 'Update Guide'
                              : 'Create Guide',
                          style: GoogleFonts.lexend(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
