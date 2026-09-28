import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/theme.dart';
import 'package:hidden_eleven/features/admin/models/admin_models.dart';
import 'package:hidden_eleven/features/admin/services/admin_api.dart';
import 'package:hidden_eleven/features/admin/widgets/admin_widgets.dart';
import 'package:hidden_eleven/shared/data/asset_fallbacks.dart';
import 'package:hidden_eleven/shared/widgets/jersey_back.dart';

// Common kit colors, offered as one-tap swatches so setting a club's colors
// doesn't require knowing or looking up a hex code. The hex field underneath
// still takes any custom value — this is a shortcut, not the only way in.
const List<(String, String)> _kitColorPresets = [
  ('Red', '#D3222A'),
  ('Claret', '#6C1D45'),
  ('Maroon', '#7A263A'),
  ('Orange', '#D2691E'),
  ('Gold', '#FDB913'),
  ('Yellow', '#FDE100'),
  ('Green', '#00843D'),
  ('Teal', '#046A38'),
  ('Sky Blue', '#6CABDD'),
  ('Blue', '#0057B8'),
  ('Navy', '#1C2C5B'),
  ('Purple', '#5F259F'),
  ('Pink', '#EB6FBD'),
  ('Black', '#15181C'),
  ('White', '#FFFFFF'),
];

class ClubsTab extends StatefulWidget {
  const ClubsTab({super.key});

  @override
  State<ClubsTab> createState() => _ClubsTabState();
}

class _ClubsTabState extends State<ClubsTab> {
  List<AdminClub>? _clubs;
  String? _error;
  bool _loading = true;
  String _query = '';
  String? _leagueFilter;

  List<String> get _leagueOptions {
    final set = <String>{};
    for (final c in _clubs ?? []) {
      if (c.league.isNotEmpty) set.add(c.league);
    }
    return set.toList()..sort();
  }

  List<AdminClub> get _filtered {
    var list = _clubs ?? [];
    final q = _query.toLowerCase().trim();
    if (q.isNotEmpty) {
      list = list
          .where(
            (c) =>
                c.name.toLowerCase().contains(q) ||
                c.league.toLowerCase().contains(q),
          )
          .toList();
    }
    if (_leagueFilter != null) {
      list = list.where((c) => c.league == _leagueFilter).toList();
    }
    return list;
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
      final clubs = await AdminApi.getClubs();
      if (mounted)
        setState(() {
          _clubs = clubs;
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

  Future<void> _openForm([AdminClub? club]) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _ClubFormDialog(club: club),
    );
    if (result == true) _load();
  }

  Future<void> _delete(AdminClub club) async {
    final confirmed = await showDeleteConfirm(context, club.name);
    if (confirmed != true) return;
    try {
      await AdminApi.deleteClub(club.slug);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _toggleActive(AdminClub club) async {
    try {
      final updated = await AdminApi.updateClub(club.slug, {
        'active': !club.active,
      });
      if (mounted) {
        setState(() {
          final i = _clubs!.indexWhere((c) => c.slug == club.slug);
          if (i != -1) _clubs![i] = updated;
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

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final total = (_clubs ?? []).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Toolbar ───────────────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: TextField(
                onChanged: (q) => setState(() => _query = q),
                style: const TextStyle(
                  color: HEColors.textPrimary,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'Search clubs…',
                  hintStyle: const TextStyle(
                    color: HEColors.textMuted,
                    fontSize: 14,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: HEColors.textSecondary,
                    size: 18,
                  ),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: HEColors.textSecondary,
                            size: 16,
                          ),
                          onPressed: () => setState(() => _query = ''),
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: () => _openForm(),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Club'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // ── League filter ─────────────────────────────────────────────────────
        if (_clubs != null)
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _TabFilterDropdown<String?>(
                label: 'League',
                value: _leagueFilter,
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All leagues'),
                  ),
                  ..._leagueOptions.map(
                    (l) => DropdownMenuItem(value: l, child: Text(l)),
                  ),
                ],
                onChanged: (v) => setState(() => _leagueFilter = v),
              ),
              if (_leagueFilter != null)
                TextButton.icon(
                  onPressed: () => setState(() => _leagueFilter = null),
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
                  label: const Text('Clear'),
                  style: TextButton.styleFrom(foregroundColor: HEColors.error),
                ),
              Text(
                '${filtered.length} of $total',
                style: const TextStyle(color: HEColors.textMuted, fontSize: 12),
              ),
            ],
          ),
        const SizedBox(height: 12),
        Expanded(child: _body(filtered)),
      ],
    );
  }

  Widget _body(List<AdminClub> clubs) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return AdminErrorState(error: _error!, onRetry: _load);
    if (clubs.isEmpty) {
      return AdminEmptyState(
        label: _query.isNotEmpty ? 'No clubs match "$_query"' : 'No clubs yet',
      );
    }
    return ListView.separated(
      itemCount: clubs.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, i) => _ClubRow(
        club: clubs[i],
        onEdit: () => _openForm(clubs[i]),
        onDelete: () => _delete(clubs[i]),
        onToggleActive: () => _toggleActive(clubs[i]),
      ),
    );
  }
}

// ── Shared inline filter dropdown ─────────────────────────────────────────────

class _TabFilterDropdown<T> extends StatelessWidget {
  const _TabFilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: HEColors.surfaceElevated,
        borderRadius: BorderRadius.circular(HERadius.sm),
        border: Border.all(color: HEColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              color: HEColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              items: items,
              onChanged: onChanged,
              isDense: true,
              dropdownColor: HEColors.surfaceElevated,
              style: const TextStyle(color: HEColors.textPrimary, fontSize: 13),
              icon: const Icon(
                Icons.arrow_drop_down,
                color: HEColors.textSecondary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClubRow extends StatelessWidget {
  const _ClubRow({
    required this.club,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleActive,
  });
  final AdminClub club;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleActive;

  // Stored logo if any, otherwise the same name-based CDN fallback the game uses.
  String _effectiveLogoUrl() {
    final stored = AdminApi.resolveAssetUrl(club.logoUrl);
    return stored.isNotEmpty ? stored : (clubLogoFallbackUrl(club.name) ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final active = club.active;
    return InkWell(
      onTap: onEdit,
      child: Opacity(
        opacity: active ? 1 : 0.5,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              AdminImagePreview(
                url: _effectiveLogoUrl(),
                size: 36,
                placeholder: Icons.shield_outlined,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      club.name,
                      style: const TextStyle(
                        color: HEColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      club.league,
                      style: const TextStyle(
                        color: HEColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                club.slug,
                style: const TextStyle(
                  color: HEColors.textMuted,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 8),
              // "Allowed to play with" toggle — mirrors the league toggle.
              Text(
                active ? 'Allowed' : 'Off',
                style: TextStyle(
                  color: active ? HEColors.accent : HEColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Switch(
                value: active,
                onChanged: (_) => onToggleActive(),
                activeColor: HEColors.accent,
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
      ),
    );
  }
}

class _ClubFormDialog extends StatefulWidget {
  const _ClubFormDialog({this.club});
  final AdminClub? club;

  @override
  State<_ClubFormDialog> createState() => _ClubFormDialogState();
}

class _ClubFormDialogState extends State<_ClubFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;

  // League dropdown (replaces free-text field)
  List<AdminLeague> _leagues = [];
  AdminLeague? _selectedLeague;
  bool _loadingLeagues = true;
  String? _leagueError;

  // Kit colors (jersey-back player card design)
  late final TextEditingController _primaryColorCtrl;
  late final TextEditingController _secondaryColorCtrl;
  late final TextEditingController _tertiaryColorCtrl;
  // Which field the swatch palette below writes into when tapped.
  final _activeColorField = ValueNotifier(_ColorTarget.primary);
  // null = "auto" (deterministic per-club-name pattern, no admin override).
  late final ValueNotifier<KitPattern?> _kitPattern;

  // Special card frame — null = normal rating-tier frame, 'icon'/'hero' =
  // gold/brown or blue/purple override (see CardTier.forCard).
  late final ValueNotifier<String?> _cardStyle;

  // Logo
  late final TextEditingController _logoUrlCtrl;
  Uint8List? _pendingLogoBytes;
  String? _pendingLogoFilename;
  UploadStatus _logoUploadStatus = UploadStatus.idle;
  String? _logoUploadError;
  String? _savedLogoPath;

  bool _saving = false;
  bool get _isEdit => widget.club != null;

  @override
  void initState() {
    super.initState();
    final c = widget.club;
    _name = TextEditingController(text: c?.name ?? '');
    _primaryColorCtrl = TextEditingController(text: c?.primaryColor ?? '');
    _secondaryColorCtrl = TextEditingController(text: c?.secondaryColor ?? '');
    _tertiaryColorCtrl = TextEditingController(text: c?.tertiaryColor ?? '');
    _kitPattern = ValueNotifier(kitPatternFromName(c?.kitPattern));
    _cardStyle = ValueNotifier(c?.cardStyle);
    _savedLogoPath = c?.logoUrl;
    // Show the stored logo if any; otherwise pre-fill the same name-based
    // fallback the game card uses, so the admin sees & can edit the real URL.
    final resolved = AdminApi.resolveAssetUrl(c?.logoUrl);
    final effective = resolved.isNotEmpty
        ? resolved
        : (clubLogoFallbackUrl(c?.name) ?? '');
    _logoUrlCtrl = TextEditingController(text: effective);
    _loadLeagues(c);
  }

  @override
  void dispose() {
    _name.dispose();
    _primaryColorCtrl.dispose();
    _secondaryColorCtrl.dispose();
    _tertiaryColorCtrl.dispose();
    _activeColorField.dispose();
    _kitPattern.dispose();
    _cardStyle.dispose();
    _logoUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLeagues(AdminClub? c) async {
    try {
      final leagues = await AdminApi.getLeagues();
      if (!mounted) return;
      setState(() {
        _leagues = leagues;
        _loadingLeagues = false;
        if (c != null) {
          _selectedLeague = leagues
              .where((l) => l.name == c.league)
              .firstOrNull;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _loadingLeagues = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedLeague == null) {
      setState(() => _leagueError = 'Required');
      return;
    }

    setState(() => _saving = true);
    try {
      final manualLogoUrl = _logoUrlCtrl.text.trim();
      final originalLogoUrl = AdminApi.resolveAssetUrl(
        widget.club?.logoUrl ?? '',
      );

      final primaryColor = _primaryColorCtrl.text.trim();
      final secondaryColor = _secondaryColorCtrl.text.trim();
      final tertiaryColor = _tertiaryColorCtrl.text.trim();
      final dto = {
        'name': _name.text.trim(),
        'league': _selectedLeague!.name,
        if (manualLogoUrl.isNotEmpty &&
            manualLogoUrl != originalLogoUrl &&
            _pendingLogoBytes == null)
          'logoUrl': manualLogoUrl,
        if (primaryColor.isNotEmpty) 'primaryColor': primaryColor,
        if (secondaryColor.isNotEmpty) 'secondaryColor': secondaryColor,
        if (tertiaryColor.isNotEmpty) 'tertiaryColor': tertiaryColor,
        if (_kitPattern.value != null) 'kitPattern': _kitPattern.value!.name,
        // Sent unconditionally (even null) so picking "Auto" actually clears
        // a previously-set special style rather than leaving it untouched.
        'cardStyle': _cardStyle.value,
      };

      final AdminClub saved;
      if (_isEdit) {
        saved = await AdminApi.updateClub(widget.club!.slug, dto);
      } else {
        saved = await AdminApi.createClub(dto);
      }

      if (_pendingLogoBytes != null) {
        setState(() => _logoUploadStatus = UploadStatus.uploading);
        try {
          final updated = await AdminApi.uploadClubLogo(
            saved.slug,
            _pendingLogoBytes!,
            _pendingLogoFilename!,
          );
          if (mounted) {
            setState(() {
              _logoUploadStatus = UploadStatus.success;
              _savedLogoPath = updated.logoUrl;
              _logoUrlCtrl.text = AdminApi.resolveAssetUrl(updated.logoUrl);
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _saving = false;
              _logoUploadStatus = UploadStatus.error;
              _logoUploadError = e.toString();
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Club saved, but logo upload failed: $e')),
            );
          }
          return;
        }
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
    return AdminFormScaffold(
      formKey: _formKey,
      title: _isEdit ? 'Edit Club' : 'Add Club',
      saving: _saving,
      isEdit: _isEdit,
      onSave: _save,
      children: [
        AdminTextField(
          controller: _name,
          label: 'Name',
          hint: 'e.g. Manchester City',
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
        const SizedBox(height: 16),
        // League dropdown — no free text
        AdminSearchableDropdown<AdminLeague>(
          label: 'League',
          items: _leagues,
          labelOf: (l) => l.name,
          value: _selectedLeague,
          hint: 'Select league',
          errorText: _leagueError,
          loading: _loadingLeagues,
          leadingOf: (l) => AdminImagePreview(
            url: AdminApi.resolveAssetUrl(l.logoUrl),
            size: 22,
            placeholder: Icons.sports_soccer_rounded,
          ),
          onChanged: (l) => setState(() {
            _selectedLeague = l;
            _leagueError = null;
          }),
        ),
        const SizedBox(height: 20),
        const AdminSectionHeader('Kit Colors'),
        const SizedBox(height: 4),
        const Text(
          'Drive the in-game jersey-back player card design. Leave blank to '
          'use a generated color for this club.',
          style: TextStyle(color: HEColors.textMuted, fontSize: 11),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _HexColorField(
                          controller: _primaryColorCtrl,
                          label: 'Primary',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _HexColorField(
                          controller: _secondaryColorCtrl,
                          label: 'Secondary',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 220,
                    child: _HexColorField(
                      controller: _tertiaryColorCtrl,
                      label: 'Trim (collar & cuffs)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  _ActiveColorTarget(notifier: _activeColorField),
                  const SizedBox(height: 6),
                  _ColorSwatchPalette(
                    onPicked: (hex) {
                      final target = switch (_activeColorField.value) {
                        _ColorTarget.secondary => _secondaryColorCtrl,
                        _ColorTarget.tertiary => _tertiaryColorCtrl,
                        _ColorTarget.primary => _primaryColorCtrl,
                      };
                      target.text = hex;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  const Text(
                    'Preview',
                    style: TextStyle(
                      color: HEColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  AnimatedBuilder(
                    animation: Listenable.merge([
                      _primaryColorCtrl,
                      _secondaryColorCtrl,
                      _tertiaryColorCtrl,
                      _name,
                      _kitPattern,
                    ]),
                    builder: (context, _) => Container(
                      width: 120,
                      height: 130,
                      decoration: BoxDecoration(
                        color: HEColors.surface,
                        borderRadius: BorderRadius.circular(HERadius.sm),
                        border: Border.all(color: HEColors.divider),
                      ),
                      child: JerseyBack(
                        playerName: '',
                        club: _name.text.trim(),
                        primaryColorHex: _primaryColorCtrl.text.trim(),
                        secondaryColorHex: _secondaryColorCtrl.text.trim(),
                        tertiaryColorHex: _tertiaryColorCtrl.text.trim(),
                        kitPattern: _kitPattern.value,
                        numberSeed: 'preview',
                        kitNumber: 7,
                        fit: JerseyFit.contain,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        // Full width rather than tucked in beside the preview — there are 14
        // tiles and they need the room to lay out a few per row.
        const Text(
          'KIT STYLE',
          style: TextStyle(
            color: HEColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Pick the design this club plays in. "Auto" keeps the generated one.',
          style: TextStyle(color: HEColors.textMuted, fontSize: 11),
        ),
        const SizedBox(height: 8),
        _KitPatternPicker(
          notifier: _kitPattern,
          club: _name,
          primaryColor: _primaryColorCtrl,
          secondaryColor: _secondaryColorCtrl,
          tertiaryColor: _tertiaryColorCtrl,
        ),
        const SizedBox(height: 20),
        const Text(
          'CARD STYLE',
          style: TextStyle(
            color: HEColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Overrides the normal rating-tier frame with a special design, like '
          'real Icon/Hero cards. "Auto" keeps the normal rating frame.',
          style: TextStyle(color: HEColors.textMuted, fontSize: 11),
        ),
        const SizedBox(height: 8),
        _CardStylePicker(notifier: _cardStyle),
        const SizedBox(height: 20),
        const AdminSectionHeader('Club Logo'),
        const SizedBox(height: 10),
        AdminImageUploader(
          currentUrl: AdminApi.resolveAssetUrl(widget.club?.logoUrl),
          placeholder: Icons.shield_outlined,
          status: _logoUploadStatus,
          errorMessage: _logoUploadError,
          savedPath: _savedLogoPath,
          urlController: _logoUrlCtrl,
          onFilePicked: (bytes, name) {
            setState(() {
              _pendingLogoBytes = bytes;
              _pendingLogoFilename = name;
              _logoUploadStatus = UploadStatus.idle;
              _logoUploadError = null;
            });
          },
        ),
      ],
    );
  }
}

// ── Hex color field ────────────────────────────────────────────────────────────

/// A text field for a "#RRGGBB" hex color, with a live swatch preview and
/// format validation. Used for club kit colors (jersey-back player card).
class _HexColorField extends StatefulWidget {
  const _HexColorField({required this.controller, required this.label});
  final TextEditingController controller;
  final String label;

  @override
  State<_HexColorField> createState() => _HexColorFieldState();
}

class _HexColorFieldState extends State<_HexColorField> {
  static final _hexPattern = RegExp(r'^#[0-9A-Fa-f]{6}$');

  Color? get _swatchColor {
    final text = widget.controller.text.trim();
    if (!_hexPattern.hasMatch(text)) return null;
    return Color(0xFF000000 | int.parse(text.substring(1), radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final swatch = _swatchColor;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: AdminTextField(
                controller: widget.controller,
                label: widget.label,
                hint: '#RRGGBB',
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return null;
                  return _hexPattern.hasMatch(t) ? null : 'Format: #RRGGBB';
                },
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(top: 18),
              decoration: BoxDecoration(
                color: swatch ?? HEColors.surfaceElevated,
                shape: BoxShape.circle,
                border: Border.all(color: HEColors.divider),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Color swatch palette ─────────────────────────────────────────────────────

enum _ColorTarget { primary, secondary, tertiary }

/// Two chips choosing which field ([_ColorTarget.primary] or `.secondary`)
/// the swatch palette below writes into when tapped.
class _ActiveColorTarget extends StatelessWidget {
  const _ActiveColorTarget({required this.notifier});
  final ValueNotifier<_ColorTarget> notifier;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_ColorTarget>(
      valueListenable: notifier,
      builder: (context, active, _) {
        Widget chip(String label, _ColorTarget target) {
          final selected = active == target;
          return GestureDetector(
            onTap: () => notifier.value = target,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: selected
                    ? HEColors.accent.withValues(alpha: 0.20)
                    : HEColors.surfaceElevated,
                borderRadius: BorderRadius.circular(HERadius.xs),
                border: Border.all(
                  color: selected ? HEColors.accent : HEColors.divider,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? HEColors.accent : HEColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }

        // Wrap, not Row — this sits in a narrower column next to the live
        // preview, and a Row here overflowed rather than dropping to a
        // second line (found by actually rendering the dialog, not just
        // reading the layout).
        return Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 4,
          children: [
            const Text(
              'Tap a swatch to set:',
              style: TextStyle(color: HEColors.textMuted, fontSize: 11),
            ),
            chip('Primary', _ColorTarget.primary),
            chip('Secondary', _ColorTarget.secondary),
            chip('Trim', _ColorTarget.tertiary),
          ],
        );
      },
    );
  }
}

/// One-tap preset color swatches — the fast path for setting a kit color
/// without knowing or looking up a hex code. The hex field still takes any
/// custom value directly.
class _ColorSwatchPalette extends StatelessWidget {
  const _ColorSwatchPalette({required this.onPicked});
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (name, hex) in _kitColorPresets)
          Tooltip(
            message: name,
            child: GestureDetector(
              onTap: () => onPicked(hex),
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: Color(
                    0xFF000000 | int.parse(hex.substring(1), radix: 16),
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(color: HEColors.divider, width: 1.5),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Kit pattern picker ────────────────────────────────────────────────────────

/// One tile per [KitPattern] plus an "Auto" option (the deterministic
/// per-club-name pattern, no override) — each rendered as a real mini jersey
/// in the club's current colors, so picking a style is "which of these looks
/// right" rather than reading pattern names off a dropdown.
class _KitPatternPicker extends StatelessWidget {
  const _KitPatternPicker({
    required this.notifier,
    required this.club,
    required this.primaryColor,
    required this.secondaryColor,
    required this.tertiaryColor,
  });

  final ValueNotifier<KitPattern?> notifier;
  final TextEditingController club;
  final TextEditingController primaryColor;
  final TextEditingController secondaryColor;
  final TextEditingController tertiaryColor;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        notifier,
        club,
        primaryColor,
        secondaryColor,
        tertiaryColor,
      ]),
      builder: (context, _) {
        Widget tile(String label, KitPattern? value) {
          final selected = notifier.value == value;
          return GestureDetector(
            onTap: () => notifier.value = value,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 64,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: selected
                    ? HEColors.accent.withValues(alpha: 0.14)
                    : HEColors.surfaceElevated,
                borderRadius: BorderRadius.circular(HERadius.sm),
                border: Border.all(
                  color: selected ? HEColors.accent : HEColors.divider,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 40,
                    height: 44,
                    child: JerseyBack(
                      playerName: '',
                      club: club.text.trim(),
                      primaryColorHex: primaryColor.text.trim(),
                      secondaryColorHex: secondaryColor.text.trim(),
                      tertiaryColorHex: tertiaryColor.text.trim(),
                      kitPattern: value,
                      numberSeed: 'preview',
                      fit: JerseyFit.contain,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: selected
                          ? HEColors.accent
                          : HEColors.textSecondary,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            tile('Auto', null),
            for (final p in KitPattern.values) tile(p.label, p),
          ],
        );
      },
    );
  }
}

// ── Card style picker ─────────────────────────────────────────────────────────

/// The special-frame options a club's cards can override the normal
/// rating-tier band with — see CardTier's `_specialStyles` map
/// (card_details_modal.dart), which these slugs must match exactly.
const List<(String, String, Color)> _cardStyleOptions = [
  ('icon', 'Icon', Color(0xFFF2C879)),
  ('hero', 'Hero', Color(0xFF9B6BFF)),
];

/// "Auto" (normal rating-tier frame) plus one tile per special style — a
/// simple swatch-chip picker since there are only 2 special styles today,
/// unlike the many-option kit-pattern picker above.
class _CardStylePicker extends StatelessWidget {
  const _CardStylePicker({required this.notifier});
  final ValueNotifier<String?> notifier;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: notifier,
      builder: (context, _) {
        Widget tile(String label, String? value, Color color) {
          final selected = notifier.value == value;
          return GestureDetector(
            onTap: () => notifier.value = value,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: selected
                    ? color.withValues(alpha: 0.20)
                    : HEColors.surfaceElevated,
                borderRadius: BorderRadius.circular(HERadius.xs),
                border: Border.all(
                  color: selected ? color : HEColors.divider,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: selected ? color : HEColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            tile('Auto', null, HEColors.textMuted),
            for (final (slug, label, color) in _cardStyleOptions)
              tile(label, slug, color),
          ],
        );
      },
    );
  }
}
