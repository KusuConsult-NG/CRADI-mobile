import 'package:climate_app/core/utils/error_handler.dart';
import 'package:climate_app/core/services/supabase_service.dart';
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
  final SupabaseService _supabase = SupabaseService();
  List<Map<String, dynamic>> _guides = [];
  bool _loading = false;

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

  @override
  void initState() {
    super.initState();
    _loadGuides();
  }

  Future<void> _loadGuides() async {
    setState(() => _loading = true);
    try {
      final docs = await _supabase.listDocuments(
        collectionId: AppConfig.knowledgeBaseCollection,
        queries: [
          SQuery.orderDesc('updated_at'),
          SQuery.limit(200),
        ],
      );
      if (mounted) setState(() => _guides = docs);
    } on Exception catch (e) {
      developer.log('Error loading guides: $e', name: 'AdminKnowledgeScreen');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
        await _supabase.deleteDocument(
          collectionId: AppConfig.knowledgeBaseCollection,
          documentId: id,
        );
        developer.log('Guide deleted: $id', name: 'AdminKnowledgeScreen');
        _loadGuides();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Guide deleted'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } on Exception catch (e) {
        developer.log('Error deleting guide: $e', name: 'AdminKnowledgeScreen');
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
        onSaved: _loadGuides,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredDocs = _guides.where((d) {
      if (_categoryFilter != 'All') {
        final hazard = (d['hazard_type'] ?? d['hazardType'] ?? '').toString();
        if (hazard.toLowerCase() != _categoryFilter.toLowerCase()) return false;
      }
      return true;
    }).toList();

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
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadGuides,
                    child: filteredDocs.isEmpty
                        ? Center(
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
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                            itemCount: filteredDocs.length,
                            itemBuilder: (_, i) {
                              final d = filteredDocs[i];
                              final id = (d['id'] ?? d['\$id'] ?? '').toString();
                              final hazardType = (d['hazard_type'] ??
                                      d['hazardType'] ??
                                      d['category'] ??
                                      'general')
                                  .toString();
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
                                    (d['title'] ?? 'Untitled').toString(),
                                    style: GoogleFonts.lexend(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (d['source'] ?? '').toString(),
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
                                        child: Text('Edit'),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text(
                                          'Delete',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ),
                                    ],
                                  ),
                                  isThreeLine: true,
                                ),
                              );
                            },
                          ),
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
  final VoidCallback onSaved;

  const _GuideFormSheet({
    this.existing,
    this.docId,
    required this.categories,
    required this.onSaved,
  });

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
    final hazardType = (e?['hazard_type'] ?? e?['hazardType'] ?? '') as String;
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

    final nowIso = DateTime.now().toUtc().toIso8601String();
    final data = <String, dynamic>{
      'title': _titleCtrl.text.trim(),
      'content': _contentCtrl.text.trim(),
      'source': _sourceCtrl.text.trim(),
      'category': _selectedCategory,
      'hazard_type': _selectedCategory.toLowerCase(),
      'updated_at': nowIso,
    };

    try {
      final supabase = SupabaseService();
      if (widget.docId != null) {
        await supabase.updateDocument(
          collectionId: AppConfig.knowledgeBaseCollection,
          documentId: widget.docId!,
          data: data,
        );
        developer.log(
          'Guide updated: ${widget.docId}',
          name: 'AdminKnowledgeScreen',
        );
      } else {
        data['created_at'] = nowIso;
        await supabase.createDocument(
          collectionId: AppConfig.knowledgeBaseCollection,
          data: data,
        );
        developer.log('Guide created', name: 'AdminKnowledgeScreen');
      }

      widget.onSaved();

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
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.docId != null ? 'Edit Guide' : 'New Guide',
                style: GoogleFonts.lexend(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'Category / Hazard Type',
                  border: OutlineInputBorder(),
                ),
                items: widget.categories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedCategory = v);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Title is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _sourceCtrl,
                decoration: const InputDecoration(
                  labelText: 'Source (e.g. NEMA, NIHSA)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _contentCtrl,
                decoration: const InputDecoration(
                  labelText: 'Content',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 6,
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Content is required'
                    : null,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        widget.docId != null ? 'Update Guide' : 'Save Guide',
                        style: GoogleFonts.lexend(fontWeight: FontWeight.w600),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
