import 'dart:async';

import 'package:climate_app/core/constants/emergency.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:climate_app/features/contacts/models/emergency_contact_model.dart';
import 'package:climate_app/features/contacts/providers/emergency_contacts_provider.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:climate_app/core/l10n/l10n.dart';
import 'package:climate_app/core/utils/screen_security.dart';

class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  State<EmergencyContactsScreen> createState() =>
      _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen>
    with ScreenSecurityMixin<EmergencyContactsScreen> {
  final TextEditingController _searchController = TextEditingController();

  /// Category filter values (stored contact categories, plus 'all').
  static const List<String> _categoryFilters = [
    'all',
    'coordinator',
    'emergency',
    'agri-extension',
    'other',
  ];

  String _categoryFilterLabel(String value) {
    final l10n = context.l10n;
    switch (value) {
      case 'coordinator':
        return l10n.contactsFilterCoordinators;
      case 'emergency':
        return l10n.contactsCategoryEmergency;
      case 'agri-extension':
        return l10n.contactsCategoryAgriExtension;
      case 'other':
        return l10n.contactsCategoryOther;
      default:
        return l10n.contactsFilterAll;
    }
  }

  String _selectedCategory = 'all';
  String _query = '';

  /// The realtime subscription is created once (and again on
  /// pull-to-refresh), not in build, so typing in the search box or
  /// switching categories does not resubscribe. It is owned by this state
  /// and cancelled on refresh / dispose, which closes the realtime channel.
  /// Category and search filters are applied to its rows.
  StreamSubscription<List<EmergencyContact>>? _contactsSub;
  List<EmergencyContact>? _contacts;
  Object? _contactsError;
  Completer<void>? _nextEvent;

  @override
  void initState() {
    super.initState();
    _subscribe();
    _searchController.addListener(() {
      final q = _searchController.text.trim().toLowerCase();
      if (q != _query) setState(() => _query = q);
    });
  }

  void _subscribe() {
    unawaited(_contactsSub?.cancel());
    final next = _nextEvent = Completer<void>();
    void settle() {
      if (!next.isCompleted) next.complete();
    }

    _contactsSub = context
        .read<EmergencyContactsProvider>()
        .getContactsStream()
        .listen(
          (contacts) {
            settle();
            if (!mounted) return;
            setState(() {
              _contacts = contacts;
              _contactsError = null;
            });
          },
          onError: (Object e) {
            settle();
            if (!mounted) return;
            setState(() => _contactsError = e);
          },
          // A stream that ends without rows (e.g. signed out) must not
          // leave the spinner up forever.
          onDone: () {
            settle();
            if (!mounted || _contacts != null) return;
            setState(() => _contacts = const []);
          },
        );
  }

  Future<void> _refresh() async {
    _subscribe();
    try {
      await _nextEvent!.future.timeout(const Duration(seconds: 10));
    } on TimeoutException catch (_) {
      // The list keeps showing the last rows.
    }
  }

  @override
  void dispose() {
    unawaited(_contactsSub?.cancel());
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _makePhoneCall(String phone) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.contactsLaunchPhoneFailed)),
        );
      }
    }
  }

  Future<void> _sendSMS(String phone) async {
    final Uri launchUri = Uri(scheme: 'sms', path: phone);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.contactsLaunchSmsFailed)),
        );
      }
    }
  }

  Future<void> _showContactDialog({EmergencyContact? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => ContactFormDialog(existing: existing),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existing == null
                ? context.l10n.contactsAdded
                : context.l10n.contactsUpdated,
          ),
        ),
      );
    }
  }

  Future<void> _confirmDelete(EmergencyContact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(context.l10n.contactsDeleteTitle),
        content: Text(context.l10n.contactsDeleteBody(contact.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(context.l10n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(c, true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<EmergencyContactsProvider>().deleteContact(contact.id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.contactsDeleted)));
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ErrorHandler.handleError(
                e,
                context.l10n,
                context: 'Emergency Contact',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<EmergencyContact> _filter(List<EmergencyContact> all) {
    return all.where((c) {
      if (_selectedCategory != 'all') {
        final known = _categoryFilters.contains(c.category);
        final category = known ? c.category : 'other';
        if (category != _selectedCategory) return false;
      }
      if (_query.isEmpty) return true;
      return c.name.toLowerCase().contains(_query) ||
          c.role.toLowerCase().contains(_query) ||
          c.phone.toLowerCase().contains(_query) ||
          (c.organization?.toLowerCase().contains(_query) ?? false) ||
          (c.lga?.toLowerCase().contains(_query) ?? false);
    }).toList();
  }

  Widget _scrollableMessage(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: child),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.l10n.back,
          icon: const Icon(
            Icons.arrow_back_ios_new,
            size: 20,
            color: AppColors.textPrimary,
          ),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/dashboard');
            }
          },
        ),
        title: Text(
          context.l10n.contactsTitle,
          style: GoogleFonts.lexend(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: context.l10n.contactsAddTooltip,
            icon: const Icon(Icons.add, color: AppColors.primaryRed),
            onPressed: () => _showContactDialog(),
          ),
        ],
        backgroundColor: AppColors.background.withValues(alpha: 0.95),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.grey.shade200, height: 1.0),
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: context.l10n.contactsSearchHint,
                hintStyle: GoogleFonts.lexend(color: Colors.grey.shade400),
                prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),

          // Category Filters
          SizedBox(
            height: 40,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: _categoryFilters.length,
              separatorBuilder: (c, i) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final value = _categoryFilters[index];
                final isSelected = _selectedCategory == value;
                return ChoiceChip(
                  label: Text(_categoryFilterLabel(value)),
                  selected: isSelected,
                  onSelected: (v) => setState(() => _selectedCategory = value),
                  labelStyle: GoogleFonts.lexend(
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : AppColors.textPrimary,
                  ),
                  // White label on the selected chip: needs the darker red
                  // to clear the 4.5:1 contrast minimum.
                  selectedColor: AppColors.primaryRed,
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isSelected
                          ? Colors.transparent
                          : Colors.grey.shade200,
                    ),
                  ),
                  showCheckmark: false,
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          // Contacts List
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: Builder(
                builder: (context) {
                  final error = _contactsError;
                  if (error != null) {
                    return _scrollableMessage(
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          ErrorHandler.getUserMessage(error, context.l10n),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  final loaded = _contacts;
                  if (loaded == null) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final contacts = _filter(loaded);

                  if (contacts.isEmpty) {
                    return _scrollableMessage(
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.contacts_outlined,
                            size: 64,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            context.l10n.contactsEmpty,
                            style: GoogleFonts.lexend(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 0,
                      bottom: 120, // Extra padding for floating action button
                    ),
                    itemCount: contacts.length,
                    separatorBuilder: (c, i) => const SizedBox(height: 12),
                    itemBuilder: (context, index) =>
                        _buildContactCard(contacts[index]),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'emergency_contacts_fab',
        onPressed: () => _makePhoneCall(kNationalEmergencyNumber),
        backgroundColor: AppColors.errorRed,
        icon: const Icon(Icons.sos, color: Colors.white),
        label: Text(
          context.l10n.contactsEmergencyButton,
          style: GoogleFonts.lexend(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildContactCard(EmergencyContact contact) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _getCategoryColor(contact.category).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: ExcludeSemantics(
              child: Icon(
                _getCategoryIcon(contact.category),
                color: _getCategoryColor(contact.category),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.name,
                  style: GoogleFonts.lexend(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  contact.lga != null
                      ? context.l10n.contactsRoleAndLga(
                          contact.role,
                          contact.lga!,
                        )
                      : contact.role,
                  style: GoogleFonts.lexend(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          _buildActionButton(
            Icons.sms,
            Colors.grey.shade100,
            Colors.grey.shade600,
            () => _sendSMS(contact.phone),
            context.l10n.contactsSmsTooltip(contact.name),
          ),
          _buildActionButton(
            Icons.call,
            AppColors.successGreen,
            Colors.white,
            () => _makePhoneCall(contact.phone),
            context.l10n.sosCallContact(contact.name),
          ),
          PopupMenuButton<String>(
            tooltip: context.l10n.contactsMoreActions,
            icon: Icon(Icons.more_vert, color: Colors.grey.shade600),
            onSelected: (action) {
              if (action == 'edit') _showContactDialog(existing: contact);
              if (action == 'delete') _confirmDelete(contact);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(context.l10n.edit),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: Text(
                    context.l10n.delete,
                    style: const TextStyle(color: Colors.red),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// An icon-only action on a contact row. [semanticLabel] is what a screen
  /// reader announces and what the tooltip shows; the 40pt circle is centred
  /// in a 48pt hit area so it meets the minimum tap-target size.
  Widget _buildActionButton(
    IconData icon,
    Color bg,
    Color fg,
    VoidCallback onTap,
    String semanticLabel,
  ) {
    return Tooltip(
      message: semanticLabel,
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                child: ExcludeSemantics(child: Icon(icon, color: fg, size: 20)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'coordinator':
        return Colors.blue;
      case 'emergency':
        return AppColors.errorRed;
      case 'agri-extension':
        return AppColors.successGreen;
      default:
        return Colors.grey;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'coordinator':
        return Icons.person;
      case 'emergency':
        return Icons.local_police;
      case 'agri-extension':
        return Icons.agriculture;
      default:
        return Icons.contact_mail;
    }
  }
}

/// Add / edit dialog for an emergency contact. Pops `true` once saved.
class ContactFormDialog extends StatefulWidget {
  const ContactFormDialog({super.key, this.existing});

  /// The contact to edit; null to add a new one.
  final EmergencyContact? existing;

  @override
  State<ContactFormDialog> createState() => _ContactFormDialogState();
}

class _ContactFormDialogState extends State<ContactFormDialog> {
  /// Stored contact categories.
  static const _categories = [
    'coordinator',
    'emergency',
    'agri-extension',
    'other',
  ];

  static String _categoryLabel(AppLocalizations l10n, String value) {
    switch (value) {
      case 'coordinator':
        return l10n.contactsCategoryCoordinator;
      case 'emergency':
        return l10n.contactsCategoryEmergency;
      case 'agri-extension':
        return l10n.contactsCategoryAgriExtension;
      default:
        return l10n.contactsCategoryOther;
    }
  }

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _roleController;
  late final TextEditingController _phoneController;
  late final TextEditingController _orgController;
  late final TextEditingController _lgaController;
  late String _category;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.name ?? '');
    _roleController = TextEditingController(text: e?.role ?? '');
    _phoneController = TextEditingController(text: e?.phone ?? '');
    _orgController = TextEditingController(text: e?.organization ?? '');
    _lgaController = TextEditingController(text: e?.lga ?? '');
    _category = _categories.contains(e?.category)
        ? e!.category
        : (e == null ? 'coordinator' : 'other');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _roleController.dispose();
    _phoneController.dispose();
    _orgController.dispose();
    _lgaController.dispose();
    super.dispose();
  }

  String? _optional(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final provider = context.read<EmergencyContactsProvider>();
    final existing = widget.existing;
    final contact = EmergencyContact(
      id: existing?.id ?? '',
      name: _nameController.text.trim(),
      role: _roleController.text.trim(),
      phone: _phoneController.text.trim(),
      organization: _optional(_orgController),
      lga: _optional(_lgaController),
      category: _category,
      isAvailable: existing?.isAvailable ?? true,
    );
    try {
      if (existing == null) {
        await provider.addContact(contact);
      } else {
        await provider.updateContact(existing.id, contact);
      }
      if (mounted) Navigator.pop(context, true);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ErrorHandler.handleError(
              e,
              context.l10n,
              context: 'Emergency Contact',
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(
        isEdit ? context.l10n.contactsEditTitle : context.l10n.contactsAddTitle,
        style: GoogleFonts.lexend(fontWeight: FontWeight.bold),
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: context.l10n.contactsNameLabel,
                ),
                validator: (v) =>
                    EmergencyContact.validateName(v, context.l10n),
              ),
              TextFormField(
                controller: _roleController,
                decoration: InputDecoration(
                  labelText: context.l10n.contactsRoleLabel,
                ),
              ),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: context.l10n.contactsPhoneLabel,
                ),
                validator: (v) =>
                    EmergencyContact.validatePhone(v, context.l10n),
              ),
              TextFormField(
                controller: _orgController,
                decoration: InputDecoration(
                  labelText: context.l10n.contactsOrganizationLabel,
                ),
              ),
              TextFormField(
                controller: _lgaController,
                decoration: InputDecoration(
                  labelText: context.l10n.contactsLgaLabel,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: InputDecoration(
                  labelText: context.l10n.contactsCategoryLabel,
                ),
                items: [
                  for (final c in _categories)
                    DropdownMenuItem(
                      value: c,
                      child: Text(_categoryLabel(context.l10n, c)),
                    ),
                ],
                onChanged: (v) => setState(() => _category = v ?? 'other'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(context.l10n.cancel),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEdit ? context.l10n.save : context.l10n.contactsAdd),
        ),
      ],
    );
  }
}
