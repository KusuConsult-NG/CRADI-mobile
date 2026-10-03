import 'package:climate_app/core/widgets/admin_menu_entry.dart';
import 'package:climate_app/core/services/backend.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:climate_app/features/knowledge_base/knowledge_categories.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'dart:developer' as developer;
import 'package:climate_app/core/l10n/l10n.dart';

/// Admin Knowledge Base Management screen.
/// Allows admins to add, edit, and delete knowledge base guides.
class AdminKnowledgeScreen extends StatefulWidget {
  const AdminKnowledgeScreen({super.key});

  @override
  State<AdminKnowledgeScreen> createState() => _AdminKnowledgeScreenState();
}

class _AdminKnowledgeScreenState extends State<AdminKnowledgeScreen> {
  String _categoryFilter = 'All';

  /// Shared with the reader screens so what is written is what they filter.
  static final List<String> _categories = knowledgeCategoryFilters;

  late final Stream<List<Map<String, dynamic>>> _knowledgeStream;

  @override
  void initState() {
    super.initState();
    _knowledgeStream = backend.subscribeToCollection(
      collectionId: AppConfig.knowledgeBaseCollection,
      queries: [FQuery.orderDesc('updatedAt')],
    );
  }

  Future<void> _deleteGuide(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          context.l10n.adminGuideDeleteTitle,
          style: GoogleFonts.lexend(),
        ),
        content: Text(
          context.l10n.adminGuideDeleteBody,
          style: GoogleFonts.lexend(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await backend.deleteDocument(
          collectionId: AppConfig.knowledgeBaseCollection,
          documentId: id,
        );
      } on Exception catch (e) {
        developer.log('Guide delete failed: $e', name: 'AdminKnowledgeScreen');
        if (mounted) {
          final denied = isRefusal(e) || e is DocumentNotFoundException;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                denied
                    ? context.l10n.adminGuideDeleteDenied
                    : context.l10n.adminGuideDeleteFailed,
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      developer.log('Guide deleted: $id', name: 'AdminKnowledgeScreen');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.adminGuideDeleted),
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
          context.l10n.knowledgeManagement,
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
          context.l10n.adminGuideAdd,
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
                      label: Text(
                        knowledgeCategoryDisplay(context.l10n, c),
                        style: GoogleFonts.lexend(fontSize: 12),
                      ),
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
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _knowledgeStream,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      context.l10n.adminGuidesLoadError,
                      style: GoogleFonts.lexend(color: Colors.red),
                    ),
                  );
                }
                final allDocs = snap.data ?? const <Map<String, dynamic>>[];

                // Client-side filtering
                final docs = allDocs
                    .where(
                      (data) => guideMatchesCategory(data, _categoryFilter),
                    )
                    .toList();

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
                          context.l10n.adminGuidesEmpty,
                          style: GoogleFonts.lexend(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => _openGuideForm(),
                          icon: const Icon(Icons.add),
                          label: Text(context.l10n.adminGuideAddFirst),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final d = docs[i];
                    final id = d['\$id'] as String;
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
                          d['title'] as String? ??
                              context.l10n.knowledgeNoTitle,
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
                                knowledgeCategoryDisplay(
                                  context.l10n,
                                  hazardType,
                                ).toUpperCase(),
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
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'edit',
                              child: AdminMenuEntry(
                                icon: Icons.edit_outlined,
                                label: context.l10n.adminGuideEditMenu,
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: AdminMenuEntry(
                                icon: Icons.delete_outline,
                                label: context.l10n.adminGuideDeleteMenu,
                                color: Colors.red,
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

  Color _categoryColor(String hazardType) =>
      knowledgeCategoryFor(hazardType)?.color ?? Colors.teal;

  IconData _categoryIcon(String hazardType) =>
      knowledgeCategoryFor(hazardType)?.icon ?? Icons.menu_book_outlined;
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
    final existingCategory =
        knowledgeCategoryFor(e?['hazardType']) ??
        knowledgeCategoryFor(e?['category']);
    _selectedCategory = existingCategory?.label ?? widget.categories.first;
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
      'hazardType':
          knowledgeCategoryFor(_selectedCategory)?.hazardType ??
          _selectedCategory.toLowerCase(),
    };

    try {
      final db = backend;
      if (widget.docId != null) {
        await db.updateDocument(
          collectionId: AppConfig.knowledgeBaseCollection,
          documentId: widget.docId!,
          data: data,
        );
        developer.log(
          'Guide updated: ${widget.docId}',
          name: 'AdminKnowledgeScreen',
        );
      } else {
        await db.createDocument(
          collectionId: AppConfig.knowledgeBaseCollection,
          data: data,
        );
        developer.log('Guide created', name: 'AdminKnowledgeScreen');
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.docId != null
                  ? context.l10n.adminGuideUpdated
                  : context.l10n.adminGuideCreated,
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
              ErrorHandler.handleError(
                e,
                context.l10n,
                context: 'Knowledge Base',
              ),
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
                widget.docId != null
                    ? context.l10n.adminGuideEditTitle
                    : context.l10n.adminGuideNewTitle,
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
                  labelText: context.l10n.adminGuideCategoryLabel,
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
                        child: Text(
                          knowledgeCategoryDisplay(context.l10n, c),
                          style: GoogleFonts.lexend(fontSize: 14),
                        ),
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
                  labelText: context.l10n.adminGuideTitleLabel,
                  labelStyle: GoogleFonts.lexend(fontSize: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.title),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? context.l10n.adminAlertRequired
                    : null,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),

              // Source
              TextFormField(
                controller: _sourceCtrl,
                style: GoogleFonts.lexend(),
                decoration: InputDecoration(
                  labelText: context.l10n.adminGuideSourceLabel,
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
                  labelText: context.l10n.adminGuideContentLabel,
                  labelStyle: GoogleFonts.lexend(fontSize: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignLabelWithHint: true,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? context.l10n.adminAlertRequired
                    : null,
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
                              ? context.l10n.adminGuideUpdate
                              : context.l10n.adminGuideCreate,
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
