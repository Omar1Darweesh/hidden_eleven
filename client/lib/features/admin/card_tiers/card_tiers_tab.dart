import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hidden_eleven/app/theme.dart';
import 'package:hidden_eleven/features/admin/models/admin_models.dart';
import 'package:hidden_eleven/features/admin/services/admin_api.dart';
import 'package:hidden_eleven/features/admin/widgets/admin_widgets.dart';

/// Rating → card-colour bands. The game colours each player card by the highest
/// band whose minRating the player meets.
class CardTiersTab extends StatefulWidget {
  const CardTiersTab({super.key});

  @override
  State<CardTiersTab> createState() => _CardTiersTabState();
}

class _CardTiersTabState extends State<CardTiersTab> {
  List<AdminCardTier>? _tiers;
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
      final tiers = await AdminApi.getCardTiers();
      if (mounted)
        setState(() {
          _tiers = tiers;
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

  Future<void> _openForm([AdminCardTier? tier]) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _TierFormDialog(tier: tier),
    );
    if (result == true) _load();
  }

  Future<void> _delete(AdminCardTier tier) async {
    final confirmed = await showDeleteConfirm(context, tier.name);
    if (confirmed != true) return;
    try {
      await AdminApi.deleteCardTier(tier.slug);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Card Colours',
                style: TextStyle(
                  color: HEColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: () => _openForm(),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Tier'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Each player card uses the colour of the highest band its rating '
          'reaches. Edit the rating threshold and colour of any band.',
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
    final tiers = _tiers ?? [];
    if (tiers.isEmpty) return const AdminEmptyState(label: 'No card tiers yet');
    // Show highest band first.
    final sorted = [...tiers]
      ..sort((a, b) => b.minRating.compareTo(a.minRating));
    return ListView.separated(
      itemCount: sorted.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _TierRow(
        tier: sorted[i],
        upperBound: i == 0 ? null : sorted[i - 1].minRating - 1,
        onEdit: () => _openForm(sorted[i]),
        onDelete: () => _delete(sorted[i]),
      ),
    );
  }
}

class _TierRow extends StatelessWidget {
  const _TierRow({
    required this.tier,
    required this.upperBound,
    required this.onEdit,
    required this.onDelete,
  });
  final AdminCardTier tier;
  final int? upperBound;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final color = hexToColor(tier.color);
    final range = upperBound == null
        ? '${tier.minRating}+'
        : '${tier.minRating}–$upperBound';
    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(HERadius.md),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: HEColors.surface,
          borderRadius: BorderRadius.circular(HERadius.md),
          border: Border.all(color: HEColors.divider),
        ),
        child: Row(
          children: [
            // Mini card swatch preview
            Container(
              width: 40,
              height: 54,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.lerp(color, Colors.black, 0.62)!,
                    Color.lerp(color, Colors.black, 0.82)!,
                  ],
                ),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: color, width: 1.5),
              ),
              alignment: Alignment.topLeft,
              padding: const EdgeInsets.all(3),
              child: Text(
                '${tier.minRating}',
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tier.name,
                    style: const TextStyle(
                      color: HEColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Rating $range  ·  ${tier.color.toUpperCase()}',
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
        ),
      ),
    );
  }
}

// ── Form ──────────────────────────────────────────────────────────────────────
// Preset palette + hex parsing shared with abilities_tab.dart — see
// admin_widgets.dart's "Shared hex-colour editing" section.

class _TierFormDialog extends StatefulWidget {
  const _TierFormDialog({this.tier});
  final AdminCardTier? tier;

  @override
  State<_TierFormDialog> createState() => _TierFormDialogState();
}

class _TierFormDialogState extends State<_TierFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _minRating;
  late final TextEditingController _color;
  bool _saving = false;
  bool get _isEdit => widget.tier != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.tier?.name ?? '');
    _minRating = TextEditingController(
      text: widget.tier != null ? '${widget.tier!.minRating}' : '',
    );
    _color = TextEditingController(text: widget.tier?.color ?? '#FFD700');
    _color.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _minRating.dispose();
    _color.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final dto = {
        'name': _name.text.trim(),
        'minRating': int.parse(_minRating.text.trim()),
        'color': _color.text.trim(),
      };
      if (_isEdit) {
        await AdminApi.updateCardTier(widget.tier!.slug, dto);
      } else {
        await AdminApi.createCardTier(dto);
      }
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
    final color = hexToColor(_color.text);
    return AdminFormScaffold(
      formKey: _formKey,
      title: _isEdit ? 'Edit Tier' : 'Add Tier',
      saving: _saving,
      isEdit: _isEdit,
      onSave: _save,
      children: [
        AdminTextField(
          controller: _name,
          label: 'Name',
          hint: 'e.g. Gold',
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
        const SizedBox(height: 14),
        AdminTextField(
          controller: _minRating,
          label: 'Minimum rating (applies to this rating and above)',
          hint: '0–99',
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          validator: (v) {
            final n = int.tryParse(v ?? '');
            if (n == null || n < 0 || n > 99) return '0–99';
            return null;
          },
        ),
        const SizedBox(height: 20),
        const AdminSectionHeader('Colour'),
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              width: 56,
              height: 72,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.lerp(color, Colors.black, 0.62)!,
                    Color.lerp(color, Colors.black, 0.82)!,
                  ],
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color, width: 1.5),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: AdminTextField(
                controller: _color,
                label: 'Hex colour',
                hint: '#FFD700',
                validator: adminHexColorValidator,
              ),
            ),
          ],
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
