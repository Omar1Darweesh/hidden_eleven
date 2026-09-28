import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/theme.dart';
import 'package:hidden_eleven/features/admin/models/admin_models.dart';
import 'package:hidden_eleven/features/admin/services/admin_api.dart';
import 'package:hidden_eleven/features/admin/widgets/admin_widgets.dart';

/// Formations the game shuffles between at the start of each match. Each can be
/// toggled active/inactive so it can be excluded from the shuffle without
/// deleting it. At least one formation must stay active (the game falls back to
/// the full built-in set if none are).
class FormationsTab extends StatefulWidget {
  const FormationsTab({super.key});

  @override
  State<FormationsTab> createState() => _FormationsTabState();
}

class _FormationsTabState extends State<FormationsTab> {
  List<AdminFormation>? _formations;
  String? _error;
  bool _loading = true;
  String? _busySlug; // slug currently being toggled/deleted

  int get _activeCount => (_formations ?? []).where((f) => f.active).length;

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
      final formations = await AdminApi.getFormations();
      if (mounted)
        setState(() {
          _formations = formations;
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  Future<void> _toggleActive(AdminFormation f) async {
    // Guard: don't let the user disable the last active formation.
    if (f.active && _activeCount <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('At least one formation must stay active.'),
        ),
      );
      return;
    }
    setState(() => _busySlug = f.slug);
    try {
      final updated = await AdminApi.updateFormation(f.slug, {
        'active': !f.active,
      });
      if (mounted) {
        setState(() {
          final i = _formations!.indexWhere((x) => x.slug == f.slug);
          if (i != -1) _formations![i] = updated;
          _busySlug = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busySlug = null);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _delete(AdminFormation f) async {
    final confirmed = await showDeleteConfirm(context, f.name);
    if (confirmed != true) return;
    setState(() => _busySlug = f.slug);
    try {
      await AdminApi.deleteFormation(f.slug);
      _load();
    } catch (e) {
      if (mounted) {
        setState(() => _busySlug = null);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _openForm() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => const _FormationFormDialog(),
    );
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final all = _formations ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Formations',
                style: TextStyle(
                  color: HEColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (_formations != null)
              Text(
                '$_activeCount of ${all.length} active',
                style: const TextStyle(color: HEColors.textMuted, fontSize: 12),
              ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _openForm,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Formation'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'The game randomly shuffles between the active formations each match. '
          'Disable one to exclude it without deleting.',
          style: TextStyle(color: HEColors.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 16),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return AdminErrorState(error: _error!, onRetry: _load);
    final formations = _formations ?? [];
    if (formations.isEmpty) {
      return const AdminEmptyState(label: 'No formations yet');
    }
    return ListView.separated(
      itemCount: formations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _FormationCard(
        formation: formations[i],
        busy: _busySlug == formations[i].slug,
        onToggle: () => _toggleActive(formations[i]),
        onDelete: () => _delete(formations[i]),
      ),
    );
  }
}

class _FormationCard extends StatelessWidget {
  const _FormationCard({
    required this.formation,
    required this.busy,
    required this.onToggle,
    required this.onDelete,
  });

  final AdminFormation formation;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final active = formation.active;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: HEColors.surface,
        borderRadius: BorderRadius.circular(HERadius.md),
        border: Border.all(
          color: active
              ? HEColors.accent.withValues(alpha: 0.4)
              : HEColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: HEColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(HERadius.sm),
                  border: Border.all(color: HEColors.divider),
                ),
                child: Text(
                  formation.name,
                  style: const TextStyle(
                    color: HEColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${formation.slots.length} slots',
                style: const TextStyle(color: HEColors.textMuted, fontSize: 12),
              ),
              const Spacer(),
              // Active toggle
              if (busy)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else ...[
                Text(
                  active ? 'Active' : 'Disabled',
                  style: TextStyle(
                    color: active ? HEColors.accent : HEColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Switch(
                  value: active,
                  onChanged: (_) => onToggle(),
                  activeColor: HEColors.accent,
                ),
              ],
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                color: HEColors.error,
                tooltip: 'Delete',
                onPressed: busy ? null : onDelete,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Slot labels preview
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: formation.slots
                .map(
                  (s) => PositionChip(
                    s.label,
                    primary:
                        s.basePositionType == 'ST' ||
                        s.basePositionType == 'GK',
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ── Add formation form ────────────────────────────────────────────────────────

// All valid slot labels that map to pitch coordinates.
const _kValidLabels = [
  'GK',
  'LB',
  'LWB',
  'LCB',
  'CCB',
  'RCB',
  'RB',
  'RWB',
  'LCDM',
  'CDM',
  'RCDM',
  'LM',
  'LCM',
  'CM',
  'RCM',
  'RM',
  'LAM',
  'CAM',
  'RAM',
  'LW',
  'RW',
  'CF',
  'SS',
  'LST',
  'ST',
  'RST',
];

class _SlotDraft {
  _SlotDraft(this.label, this.basePos);
  final TextEditingController label;
  String basePos;
}

// Default 4-3-3 template.
List<_SlotDraft> _default433() => [
  ('GK', 'GK'),
  ('LB', 'LB'),
  ('LCB', 'CB'),
  ('RCB', 'CB'),
  ('RB', 'RB'),
  ('LCM', 'CM'),
  ('CM', 'CM'),
  ('RCM', 'CM'),
  ('LW', 'LW'),
  ('RW', 'RW'),
  ('ST', 'ST'),
].map((e) => _SlotDraft(TextEditingController(text: e.$1), e.$2)).toList();

class _FormationFormDialog extends StatefulWidget {
  const _FormationFormDialog();

  @override
  State<_FormationFormDialog> createState() => _FormationFormDialogState();
}

class _FormationFormDialogState extends State<_FormationFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  bool _saving = false;
  late List<_SlotDraft> _slots = _default433();

  @override
  void dispose() {
    _name.dispose();
    for (final s in _slots) s.label.dispose();
    super.dispose();
  }

  void _addSlot() {
    setState(() {
      _slots.add(_SlotDraft(TextEditingController(text: 'ST'), 'ST'));
    });
  }

  void _removeSlot(int i) {
    if (_slots.length <= 1) return;
    final removed = _slots.removeAt(i);
    removed.label.dispose();
    setState(() {});
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Formation name is required')),
      );
      return;
    }
    if (_slots.length != 11) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'A formation must have exactly 11 slots (currently ${_slots.length})',
          ),
        ),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final slots = [
        for (var i = 0; i < _slots.length; i++)
          {
            'index': i,
            'label': _slots[i].label.text.trim().isEmpty
                ? _slots[i].basePos
                : _slots[i].label.text.trim(),
            'basePositionType': _slots[i].basePos,
          },
      ];
      await AdminApi.createFormation({
        'name': _name.text.trim(),
        'active': true,
        'slots': slots,
      });
      if (mounted) Navigator.of(context).pop(true);
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
    final slotCount = _slots.length;
    final countOk = slotCount == 11;
    return AdminFormScaffold(
      formKey: _formKey,
      title: 'Add Formation',
      saving: _saving,
      isEdit: false,
      onSave: _save,
      children: [
        AdminTextField(controller: _name, label: 'Name', hint: 'e.g. 4-2-4'),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: AdminSectionHeader(
                'Slots · $slotCount${countOk ? ' ✓' : ' (need 11)'}',
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.remove_circle_outline_rounded,
                size: 20,
                color: HEColors.error,
              ),
              tooltip: 'Remove last slot',
              onPressed: _slots.length > 1
                  ? () => _removeSlot(_slots.length - 1)
                  : null,
            ),
            IconButton(
              icon: const Icon(
                Icons.add_circle_outline_rounded,
                size: 20,
                color: HEColors.accent,
              ),
              tooltip: 'Add slot',
              onPressed: _addSlot,
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'Label must be a valid position key: GK · LB · LCB · CCB · RCB · RB · LCM · CM · RCM · LM · RM · CDM · CAM · LAM · RAM · LW · RW · LST · ST · RST · CF',
            style: TextStyle(color: HEColors.textMuted, fontSize: 10),
          ),
        ),
        for (var i = 0; i < _slots.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      color: HEColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Autocomplete<String>(
                    optionsBuilder: (v) {
                      final q = v.text.toUpperCase();
                      return _kValidLabels.where((l) => l.contains(q));
                    },
                    initialValue: TextEditingValue(text: _slots[i].label.text),
                    fieldViewBuilder: (ctx, ctrl, focus, onSubmit) {
                      // Keep internal controller in sync with _slots[i].label.
                      ctrl.addListener(() {
                        if (ctrl.text != _slots[i].label.text) {
                          _slots[i].label.text = ctrl.text;
                        }
                      });
                      return TextFormField(
                        controller: ctrl,
                        focusNode: focus,
                        style: const TextStyle(
                          color: HEColors.textPrimary,
                          fontSize: 13,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Label',
                          isDense: true,
                        ),
                      );
                    },
                    onSelected: (v) => setState(() => _slots[i].label.text = v),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    value: _slots[i].basePos,
                    isDense: true,
                    dropdownColor: HEColors.surfaceElevated,
                    style: const TextStyle(
                      color: HEColors.textPrimary,
                      fontSize: 13,
                    ),
                    decoration: const InputDecoration(isDense: true),
                    items: kAllPositions
                        .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _slots[i].basePos = v ?? 'CM'),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: HEColors.textMuted,
                  ),
                  tooltip: 'Remove',
                  onPressed: _slots.length > 1 ? () => _removeSlot(i) : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
