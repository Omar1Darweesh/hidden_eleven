import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/theme.dart';
import 'package:hidden_eleven/features/admin/models/admin_models.dart';
import 'package:hidden_eleven/features/admin/services/admin_api.dart';
import 'package:hidden_eleven/features/admin/widgets/admin_widgets.dart';

/// Admin CRUD for reusable league packs used by the host room flow.
class LeagueBundlesTab extends StatefulWidget {
  const LeagueBundlesTab({super.key});

  @override
  State<LeagueBundlesTab> createState() => _LeagueBundlesTabState();
}

class _LeagueBundlesTabState extends State<LeagueBundlesTab> {
  List<AdminLeagueBundle>? _bundles;
  List<AdminLeague> _leagues = [];
  String? _error;
  bool _loading = true;
  String _query = '';
  String? _busyId;

  List<AdminLeagueBundle> get _filtered {
    var list = _bundles ?? [];
    final q = _query.toLowerCase().trim();
    if (q.isNotEmpty) {
      list = list
          .where(
            (b) =>
                b.name.toLowerCase().contains(q) ||
                (b.description ?? '').toLowerCase().contains(q),
          )
          .toList();
    }
    return list;
  }

  String _leagueNames(AdminLeagueBundle b) {
    final bySlug = {for (final l in _leagues) l.slug: l.name};
    return b.leagueSlugs.map((s) => bySlug[s] ?? s).join(', ');
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await (
        AdminApi.getLeagueBundles(),
        AdminApi.getLeagues(),
      ).wait;
      if (!mounted) return;
      setState(() {
        _bundles = results.$1;
        _leagues = results.$2;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _openForm([AdminLeagueBundle? bundle]) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _BundleFormDialog(bundle: bundle, leagues: _leagues),
    );
    if (result == true) _load();
  }

  Future<void> _delete(AdminLeagueBundle bundle) async {
    final confirmed = await showDeleteConfirm(context, bundle.name);
    if (confirmed != true) return;
    setState(() => _busyId = bundle.id);
    try {
      await AdminApi.deleteLeagueBundle(bundle.id);
      _load();
    } catch (e) {
      if (mounted) {
        setState(() => _busyId = null);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _duplicate(AdminLeagueBundle bundle) async {
    setState(() => _busyId = bundle.id);
    try {
      await AdminApi.duplicateLeagueBundle(bundle.id);
      _load();
    } catch (e) {
      if (mounted) {
        setState(() => _busyId = null);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _toggleActive(AdminLeagueBundle bundle) async {
    setState(() => _busyId = bundle.id);
    try {
      final updated = await AdminApi.updateLeagueBundle(bundle.id, {
        'active': !bundle.active,
      });
      if (!mounted) return;
      setState(() {
        final i = _bundles!.indexWhere((b) => b.id == bundle.id);
        if (i != -1) _bundles![i] = updated;
        _busyId = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _busyId = null);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final total = (_bundles ?? []).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Two-row toolbar so "New bundle" never clips off the right edge of
        // the admin content pane (single-row search+button overflowed).
        TextField(
          onChanged: (q) => setState(() => _query = q),
          style: const TextStyle(color: HEColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Search bundles…',
            hintStyle: const TextStyle(color: HEColors.textMuted),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: HEColors.textMuted,
              size: 20,
            ),
            filled: true,
            fillColor: HEColors.surfaceElevated,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text(
              '$total bundles',
              style: const TextStyle(
                color: HEColors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => _openForm(),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New bundle'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(child: _body(filtered)),
      ],
    );
  }

  Widget _body(List<AdminLeagueBundle> bundles) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return AdminErrorState(error: _error!, onRetry: _load);
    }
    if (bundles.isEmpty) {
      return AdminEmptyState(
        label: _query.isNotEmpty
            ? 'No bundles match "$_query"'
            : 'No league bundles yet',
      );
    }
    return ListView.separated(
      itemCount: bundles.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final b = bundles[i];
        return _BundleRow(
          bundle: b,
          leagueSummary: _leagueNames(b),
          busy: _busyId == b.id,
          onEdit: () => _openForm(b),
          onDelete: () => _delete(b),
          onDuplicate: () => _duplicate(b),
          onToggleActive: () => _toggleActive(b),
        );
      },
    );
  }
}

class _BundleRow extends StatelessWidget {
  const _BundleRow({
    required this.bundle,
    required this.leagueSummary,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
    required this.onDuplicate,
    required this.onToggleActive,
  });

  final AdminLeagueBundle bundle;
  final String leagueSummary;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    final active = bundle.active;
    return InkWell(
      onTap: busy ? null : onEdit,
      child: Opacity(
        opacity: active ? 1 : 0.5,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              const Icon(
                Icons.inventory_2_outlined,
                color: HEColors.brandCyan,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bundle.name,
                      style: const TextStyle(
                        color: HEColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${bundle.leagueSlugs.length} leagues · $leagueSummary',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: HEColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else ...[
                Text(
                  active ? 'Active' : 'Off',
                  style: TextStyle(
                    color: active ? HEColors.accent : HEColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Switch(
                  value: active,
                  onChanged: (_) => onToggleActive(),
                  activeThumbColor: HEColors.accent,
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  color: HEColors.textSecondary,
                  tooltip: 'Duplicate',
                  onPressed: onDuplicate,
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  color: HEColors.textSecondary,
                  tooltip: 'Edit',
                  onPressed: onEdit,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  color: HEColors.error,
                  tooltip: 'Delete',
                  onPressed: onDelete,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BundleFormDialog extends StatefulWidget {
  const _BundleFormDialog({this.bundle, required this.leagues});

  final AdminLeagueBundle? bundle;
  final List<AdminLeague> leagues;

  @override
  State<_BundleFormDialog> createState() => _BundleFormDialogState();
}

class _BundleFormDialogState extends State<_BundleFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final Set<String> _selectedSlugs;
  late bool _active;
  bool _saving = false;

  bool get _isEdit => widget.bundle != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.bundle?.name ?? '');
    _description = TextEditingController(
      text: widget.bundle?.description ?? '',
    );
    _selectedSlugs = {...?widget.bundle?.leagueSlugs};
    _active = widget.bundle?.active ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedSlugs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one league.')),
      );
      return;
    }
    setState(() => _saving = true);
    final dto = {
      'name': _name.text.trim(),
      'description': _description.text.trim().isEmpty
          ? null
          : _description.text.trim(),
      'leagueSlugs': _selectedSlugs.toList(),
      'active': _active,
      if (!_isEdit) 'sortOrder': 0,
    };
    try {
      if (_isEdit) {
        await AdminApi.updateLeagueBundle(widget.bundle!.id, dto);
      } else {
        await AdminApi.createLeagueBundle(dto);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final leagues = [...widget.leagues]
      ..sort((a, b) => a.name.compareTo(b.name));
    return AlertDialog(
      backgroundColor: HEColors.surfaceElevated,
      title: Text(_isEdit ? 'Edit bundle' : 'New league bundle'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active for hosts'),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
                const SizedBox(height: 8),
                Text(
                  'Leagues (${_selectedSlugs.length})',
                  style: const TextStyle(
                    color: HEColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: leagues.length,
                    itemBuilder: (context, i) {
                      final l = leagues[i];
                      final selected = _selectedSlugs.contains(l.slug);
                      return CheckboxListTile(
                        dense: true,
                        value: selected,
                        title: Text(l.name),
                        subtitle: Text(
                          l.active ? l.slug : '${l.slug} · inactive',
                          style: const TextStyle(fontSize: 11),
                        ),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selectedSlugs.add(l.slug);
                          } else {
                            _selectedSlugs.remove(l.slug);
                          }
                        }),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isEdit ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}
