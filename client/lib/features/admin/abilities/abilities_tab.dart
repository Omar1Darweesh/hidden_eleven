import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/theme.dart';
import 'package:hidden_eleven/features/admin/models/admin_models.dart';
import 'package:hidden_eleven/features/admin/services/admin_api.dart';
import 'package:hidden_eleven/features/admin/widgets/admin_widgets.dart';
import 'package:hidden_eleven/features/game/models/ability.dart';

/// Toggle which of the 5 ability cards appear in games. Disabling all of them
/// removes the ability phase entirely.
class AbilitiesTab extends StatefulWidget {
  const AbilitiesTab({super.key});

  @override
  State<AbilitiesTab> createState() => _AbilitiesTabState();
}

class _AbilitiesTabState extends State<AbilitiesTab> {
  List<AdminAbility>? _abilities;
  String? _error;
  bool _loading = true;

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
      final abilities = await AdminApi.getAbilities();
      if (mounted) {
        setState(() {
          _abilities = abilities;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggle(AdminAbility ability) async {
    try {
      final updated = await AdminApi.updateAbility(ability.type, {
        'enabled': !ability.enabled,
      });
      if (mounted) {
        setState(() {
          final i = _abilities!.indexWhere((a) => a.type == ability.type);
          if (i != -1) _abilities![i] = updated;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _openEditor(AdminAbility ability) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _AbilityEditDialog(ability: ability),
    );
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final abilities = _abilities ?? [];
    final enabledCount = abilities.where((a) => a.enabled).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Ability Cards',
                style: TextStyle(
                  color: HEColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (_abilities != null)
              Text(
                '$enabledCount of ${abilities.length} on',
                style: const TextStyle(color: HEColors.textMuted, fontSize: 12),
              ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Choose which ability cards can appear in games. Turn one off and it '
          'will never be dealt in the ability draft.',
          style: TextStyle(color: HEColors.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 16),
        if (_abilities != null && enabledCount == 0)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: HEColors.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: HEColors.error.withValues(alpha: 0.5)),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: HEColors.error,
                  size: 16,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'All abilities are off — games will skip the ability phase '
                    'entirely.',
                    style: TextStyle(color: HEColors.error, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        Expanded(child: _body(abilities)),
      ],
    );
  }

  Widget _body(List<AdminAbility> abilities) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return AdminErrorState(error: _error!, onRetry: _load);
    if (abilities.isEmpty) {
      return const AdminEmptyState(label: 'No abilities configured');
    }
    return ListView.separated(
      itemCount: abilities.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _AbilityRow(
        ability: abilities[i],
        onToggle: () => _toggle(abilities[i]),
        onEdit: () => _openEditor(abilities[i]),
      ),
    );
  }
}

class _AbilityRow extends StatelessWidget {
  const _AbilityRow({
    required this.ability,
    required this.onToggle,
    required this.onEdit,
  });
  final AdminAbility ability;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final type = abilityTypeFromString(ability.type);
    final meta = type != null ? AbilityMeta.of(type) : null;
    // The row's swatch/border always reflects THIS ability's own live
    // record (ability.color, fresh from every _load()) rather than
    // AbilityMeta.of(type).color — that static table is a process-wide,
    // fetch-once cache (see AbilityMeta.ensureLoaded) that could be a
    // request or two behind what this admin screen just saved. An admin
    // editing colors needs to see the actual current value, not a
    // possibly-stale cached one.
    final color = hexToColor(ability.color);
    final enabled = ability.enabled;

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: HEColors.surface,
          borderRadius: BorderRadius.circular(HERadius.md),
          border: Border.all(
            color: enabled ? color.withValues(alpha: 0.45) : HEColors.divider,
          ),
        ),
        child: Row(
          children: [
            InkWell(
              onTap: onEdit,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                child: Icon(
                  meta?.icon ?? Icons.star_rounded,
                  color: color,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ability.name,
                    style: const TextStyle(
                      color: HEColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (ability.description.isNotEmpty)
                    Text(
                      ability.description,
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
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              color: HEColors.textSecondary,
              tooltip: 'Edit name, colour & description',
              onPressed: onEdit,
            ),
            Text(
              enabled ? 'On' : 'Off',
              style: TextStyle(
                color: enabled ? color : HEColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            Switch(
              value: enabled,
              onChanged: (_) => onToggle(),
              activeColor: color,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Edit dialog (name, colour, description) ───────────────────────────────────
// Colour-picker parts (hex parsing + preset grid) shared with
// card_tiers_tab.dart — see admin_widgets.dart's "Shared hex-colour editing"
// section. `enabled` keeps its own dedicated control (the row's Switch) and
// stays out of this dialog — this is scoped to the 3 free-text/colour fields.

class _AbilityEditDialog extends StatefulWidget {
  const _AbilityEditDialog({required this.ability});
  final AdminAbility ability;

  @override
  State<_AbilityEditDialog> createState() => _AbilityEditDialogState();
}

class _AbilityEditDialogState extends State<_AbilityEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _color;
  late final TextEditingController _description;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.ability.name);
    _color = TextEditingController(text: widget.ability.color);
    _color.addListener(() => setState(() {}));
    _description = TextEditingController(text: widget.ability.description);
  }

  @override
  void dispose() {
    _name.dispose();
    _color.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await AdminApi.updateAbility(widget.ability.type, {
        'name': _name.text.trim(),
        'color': _color.text.trim(),
        'description': _description.text.trim(),
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
    final type = abilityTypeFromString(widget.ability.type);
    final icon = type != null ? AbilityMeta.of(type).icon : Icons.star_rounded;
    final color = hexToColor(_color.text);
    return AdminFormScaffold(
      formKey: _formKey,
      title: 'Edit ${widget.ability.name}',
      saving: _saving,
      isEdit: true,
      onSave: _save,
      children: [
        Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 1.5),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: AdminTextField(
                controller: _name,
                label: 'Name',
                hint: 'e.g. Captain Card',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        AdminTextField(
          controller: _description,
          label: 'Description (shown to players)',
          hint: 'e.g. Knock {yellowPenalty} points off a rival’s score.',
          maxLines: 3,
        ),
        const SizedBox(height: 4),
        const Text(
          'You can reference live chemistry values with {challengeReward}, '
          '{tierEasyReward}, {tierMediumReward}, {tierHardReward}, '
          '{lineLeaderBonus}, {yellowPenalty}, or {captainMultiplier} — not '
          'yet shown to players, but kept in sync for when it is.',
          style: TextStyle(color: HEColors.textMuted, fontSize: 10.5),
        ),
        const SizedBox(height: 20),
        const AdminSectionHeader('Colour'),
        const SizedBox(height: 10),
        AdminTextField(
          controller: _color,
          label: 'Hex colour',
          hint: '#FFC83D',
          validator: adminHexColorValidator,
        ),
        const SizedBox(height: 12),
        AdminColorPresetGrid(
          selectedHex: _color.text,
          onSelect: (hex) => setState(() => _color.text = hex),
        ),
      ],
    );
  }
}
