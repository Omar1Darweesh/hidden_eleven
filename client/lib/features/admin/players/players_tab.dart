import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hidden_eleven/app/theme.dart';
import 'package:hidden_eleven/features/admin/models/admin_models.dart';
import 'package:hidden_eleven/features/admin/services/admin_api.dart';
import 'package:hidden_eleven/features/admin/widgets/admin_widgets.dart';
import 'package:hidden_eleven/shared/data/asset_fallbacks.dart';
import 'package:hidden_eleven/shared/widgets/jersey_back.dart'
    show squadNumberFor;

class PlayersTab extends StatefulWidget {
  const PlayersTab({super.key});

  @override
  State<PlayersTab> createState() => _PlayersTabState();
}

// A photo counts as "legal" once it's a properly-licensed Wikimedia Commons
// image — either self-hosted from the batch download (stored under
// /assets/players/photos/wikimedia/) or manually pasted straight from
// Commons via the admin's "Paste URL" method (saved as the raw
// upload.wikimedia.org URL, never downloaded to the server). Both are the
// same CC-licensed source, just hosted differently, so both count. Anything
// else — including the original SoFIFA hotlink fallback every player started
// with — is still using EA-copyrighted artwork and needs a manual replacement.
bool _hasLegalPhoto(AdminPlayer p) {
  final url = p.photoUrl ?? '';
  return url.contains('/wikimedia/') ||
      url.contains('upload.wikimedia.org') ||
      p.photoLegalOverride;
}

enum _PlayerSort {
  ratingDesc('Rating (high → low)'),
  ratingAsc('Rating (low → high)'),
  nameAsc('Name (A → Z)'),
  nameDesc('Name (Z → A)'),
  clubAsc('Club (A → Z)'),
  kitNumberAsc('Kit number (low → high)');

  const _PlayerSort(this.label);
  final String label;

  int compare(AdminPlayer a, AdminPlayer b) {
    switch (this) {
      case _PlayerSort.ratingDesc:
        return b.rating.compareTo(a.rating);
      case _PlayerSort.ratingAsc:
        return a.rating.compareTo(b.rating);
      case _PlayerSort.nameAsc:
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case _PlayerSort.nameDesc:
        return b.name.toLowerCase().compareTo(a.name.toLowerCase());
      case _PlayerSort.clubAsc:
        final c = a.club.toLowerCase().compareTo(b.club.toLowerCase());
        return c != 0
            ? c
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case _PlayerSort.kitNumberAsc:
        final an = a.kitNumber ?? squadNumberFor(a.id);
        final bn = b.kitNumber ?? squadNumberFor(b.id);
        return an.compareTo(bn);
    }
  }
}

class _PlayersTabState extends State<PlayersTab> {
  List<AdminPlayer>? _players;
  List<AdminClub> _allClubs = [];
  String? _error;
  bool _loading = true;
  String _query = '';

  // Structured filters (null/0/empty = "all").
  String? _league;
  final Set<String> _positions = {};
  // When true the position filter matches a player's PRIMARY position only;
  // otherwise it matches any of their positions (primary or alternate).
  bool _primaryOnly = false;
  String? _nation;
  String? _club;
  int _minRating = 0;
  // 'legal' = self-hosted, properly-attributed photo (currently Wikimedia
  // Commons downloads); 'illegal' = still on the copyrighted SoFIFA hotlink
  // fallback and needs a manual replacement; null = no filter.
  String? _photoStatus;
  _PlayerSort _sortBy = _PlayerSort.ratingDesc;

  bool get _hasActiveFilter =>
      _league != null ||
      _positions.isNotEmpty ||
      _nation != null ||
      _club != null ||
      _minRating > 0 ||
      _photoStatus != null;

  void _clearFilters() => setState(() {
    _league = null;
    _positions.clear();
    _nation = null;
    _club = null;
    _minRating = 0;
    _photoStatus = null;
  });

  List<String> get _leagueOptions {
    final set = <String>{};
    for (final c in _allClubs) {
      if (c.league.isNotEmpty) set.add(c.league);
    }
    return set.toList()..sort();
  }

  List<String> get _nationOptions {
    final set = <String>{};
    for (final p in _players ?? const <AdminPlayer>[]) {
      if (p.nationality.isNotEmpty) set.add(p.nationality);
    }
    return set.toList()..sort();
  }

  // When a league is selected, only show clubs in that league.
  List<String> get _clubOptions {
    if (_league != null) {
      final leagueClubs = _allClubs
          .where((c) => c.league == _league)
          .map((c) => c.name)
          .toSet();
      final set = <String>{};
      for (final p in _players ?? const <AdminPlayer>[]) {
        if (p.club.isNotEmpty && leagueClubs.contains(p.club)) set.add(p.club);
      }
      return set.toList()..sort();
    }
    final set = <String>{};
    for (final p in _players ?? const <AdminPlayer>[]) {
      if (p.club.isNotEmpty) set.add(p.club);
    }
    return set.toList()..sort();
  }

  Set<String> get _clubsInLeague {
    if (_league == null) return {};
    return _allClubs
        .where((c) => c.league == _league)
        .map((c) => c.name)
        .toSet();
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
      final (players, clubs) = await (
        AdminApi.getPlayers(),
        AdminApi.getClubs(),
      ).wait;
      if (mounted) {
        setState(() {
          _players = players;
          _allClubs = clubs;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  List<AdminPlayer> get _filtered {
    var list = _players ?? const <AdminPlayer>[];
    final q = _query.toLowerCase().trim();
    if (q.isNotEmpty) {
      list = list
          .where(
            (p) =>
                p.name.toLowerCase().contains(q) ||
                p.club.toLowerCase().contains(q) ||
                p.nationality.toLowerCase().contains(q) ||
                p.positions.any((pos) => pos.toLowerCase().contains(q)),
          )
          .toList();
    }
    if (_league != null) {
      final clubs = _clubsInLeague;
      list = list.where((p) => clubs.contains(p.club)).toList();
    }
    if (_positions.isNotEmpty) {
      list = list
          .where(
            (p) => _primaryOnly
                // Primary position only.
                ? _positions.contains(p.primaryPosition)
                // Any of the player's positions (primary or alternate).
                : p.positions.any(_positions.contains),
          )
          .toList();
    }
    if (_nation != null) {
      list = list.where((p) => p.nationality == _nation).toList();
    }
    if (_club != null) {
      list = list.where((p) => p.club == _club).toList();
    }
    if (_minRating > 0) {
      list = list.where((p) => p.rating >= _minRating).toList();
    }
    if (_photoStatus == 'legal') {
      list = list.where((p) => _hasLegalPhoto(p)).toList();
    } else if (_photoStatus == 'illegal') {
      list = list.where((p) => !_hasLegalPhoto(p)).toList();
    }
    list = List.of(list)..sort(_sortBy.compare);
    return list;
  }

  Future<void> _openForm([AdminPlayer? player]) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _PlayerFormDialog(player: player),
    );
    if (result == true) _load();
  }

  Future<void> _delete(AdminPlayer player) async {
    final confirmed = await showDeleteConfirm(context, player.name);
    if (confirmed != true) return;
    try {
      await AdminApi.deletePlayer(player.id);
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
        _Toolbar(
          query: _query,
          onQueryChanged: (q) => setState(() => _query = q),
          onAdd: () => _openForm(),
        ),
        const SizedBox(height: 12),
        if (_players != null)
          _FilterBar(
            league: _league,
            positions: _positions,
            nation: _nation,
            club: _club,
            minRating: _minRating,
            leagueOptions: _leagueOptions,
            nationOptions: _nationOptions,
            clubOptions: _clubOptions,
            resultCount: _filtered.length,
            totalCount: _players!.length,
            hasActiveFilter: _hasActiveFilter,
            onLeague: (v) => setState(() {
              _league = v;
              // Reset club if it no longer belongs to the new league.
              if (v != null && _club != null) {
                final leagueClubs = _allClubs
                    .where((c) => c.league == v)
                    .map((c) => c.name)
                    .toSet();
                if (!leagueClubs.contains(_club)) _club = null;
              }
            }),
            primaryOnly: _primaryOnly,
            onTogglePosition: (pos) => setState(() {
              if (!_positions.add(pos)) _positions.remove(pos);
            }),
            onPrimaryOnly: (v) => setState(() => _primaryOnly = v),
            onNation: (v) => setState(() => _nation = v),
            onClub: (v) => setState(() => _club = v),
            onMinRating: (v) => setState(() => _minRating = v),
            photoStatus: _photoStatus,
            onPhotoStatus: (v) => setState(() => _photoStatus = v),
            sortBy: _sortBy,
            onSortBy: (v) => setState(() => _sortBy = v),
            onClear: _clearFilters,
          ),
        const SizedBox(height: 12),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return AdminErrorState(error: _error!, onRetry: _load);
    final players = _filtered;
    if (players.isEmpty) {
      return AdminEmptyState(
        label: _query.isNotEmpty
            ? 'No players match "$_query"'
            : 'No players yet',
      );
    }
    return ListView.separated(
      itemCount: players.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, i) => _PlayerRow(
        player: players[i],
        onEdit: () => _openForm(players[i]),
        onDelete: () => _delete(players[i]),
      ),
    );
  }
}

// ── Toolbar ────────────────────────────────────────────────────────────────────

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.query,
    required this.onQueryChanged,
    required this.onAdd,
  });

  final String query;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            onChanged: onQueryChanged,
            style: const TextStyle(color: HEColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search players…',
              hintStyle: const TextStyle(
                color: HEColors.textMuted,
                fontSize: 14,
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: HEColors.textSecondary,
                size: 18,
              ),
              suffixIcon: query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: HEColors.textSecondary,
                        size: 16,
                      ),
                      onPressed: () => onQueryChanged(''),
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: onAdd,
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add Player'),
        ),
      ],
    );
  }
}

// ── Filter bar ─────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.league,
    required this.positions,
    required this.nation,
    required this.club,
    required this.minRating,
    required this.leagueOptions,
    required this.nationOptions,
    required this.clubOptions,
    required this.resultCount,
    required this.totalCount,
    required this.hasActiveFilter,
    required this.primaryOnly,
    required this.onLeague,
    required this.onTogglePosition,
    required this.onPrimaryOnly,
    required this.onNation,
    required this.onClub,
    required this.onMinRating,
    required this.photoStatus,
    required this.onPhotoStatus,
    required this.sortBy,
    required this.onSortBy,
    required this.onClear,
  });

  final String? league;
  final Set<String> positions;
  final String? nation;
  final String? club;
  final int minRating;
  final List<String> leagueOptions;
  final List<String> nationOptions;
  final List<String> clubOptions;
  final int resultCount;
  final int totalCount;
  final bool hasActiveFilter;
  final bool primaryOnly;
  final ValueChanged<String?> onLeague;
  final ValueChanged<String> onTogglePosition;
  final ValueChanged<bool> onPrimaryOnly;
  final ValueChanged<String?> onNation;
  final ValueChanged<String?> onClub;
  final ValueChanged<int> onMinRating;
  final String? photoStatus;
  final ValueChanged<String?> onPhotoStatus;
  final _PlayerSort sortBy;
  final ValueChanged<_PlayerSort> onSortBy;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _FilterDropdown<String?>(
              label: 'League',
              value: league,
              items: [
                const DropdownMenuItem(value: null, child: Text('All leagues')),
                ...leagueOptions.map(
                  (l) => DropdownMenuItem(value: l, child: Text(l)),
                ),
              ],
              onChanged: onLeague,
            ),
            _FilterDropdown<String?>(
              label: 'Club',
              value: club,
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(
                    league != null ? 'All clubs in league' : 'All clubs',
                  ),
                ),
                ...clubOptions.map(
                  (c) => DropdownMenuItem(value: c, child: Text(c)),
                ),
              ],
              onChanged: onClub,
            ),
            _FilterDropdown<String?>(
              label: 'Nation',
              value: nation,
              items: [
                const DropdownMenuItem(value: null, child: Text('All nations')),
                ...nationOptions.map(
                  (n) => DropdownMenuItem(value: n, child: Text(n)),
                ),
              ],
              onChanged: onNation,
            ),
            _FilterDropdown<int>(
              label: 'Rating',
              value: minRating,
              items: const [
                DropdownMenuItem(value: 0, child: Text('Any rating')),
                DropdownMenuItem(value: 70, child: Text('70+')),
                DropdownMenuItem(value: 75, child: Text('75+')),
                DropdownMenuItem(value: 80, child: Text('80+')),
                DropdownMenuItem(value: 85, child: Text('85+')),
                DropdownMenuItem(value: 90, child: Text('90+')),
              ],
              onChanged: (v) => onMinRating(v ?? 0),
            ),
            _FilterDropdown<String?>(
              label: 'Photo',
              value: photoStatus,
              items: const [
                DropdownMenuItem(value: null, child: Text('Any photo status')),
                DropdownMenuItem(
                  value: 'legal',
                  child: Text('Legal (attributed)'),
                ),
                DropdownMenuItem(
                  value: 'illegal',
                  child: Text('Needs replacement'),
                ),
              ],
              onChanged: onPhotoStatus,
            ),
            _FilterDropdown<_PlayerSort>(
              label: 'Sort',
              value: sortBy,
              items: _PlayerSort.values
                  .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                  .toList(),
              onChanged: (v) => onSortBy(v ?? _PlayerSort.ratingDesc),
            ),
            if (hasActiveFilter)
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
                label: const Text('Clear'),
                style: TextButton.styleFrom(foregroundColor: HEColors.error),
              ),
            Text(
              '$resultCount of $totalCount',
              style: const TextStyle(color: HEColors.textMuted, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Multi-select position filter — tap to toggle several at once.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 6, right: 8),
              child: Text(
                'POSITIONS',
                style: TextStyle(
                  color: HEColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: kAllPositions.map((pos) {
                  final selected = positions.contains(pos);
                  return GestureDetector(
                    onTap: () => onTogglePosition(pos),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
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
                        pos,
                        style: TextStyle(
                          color: selected
                              ? HEColors.accent
                              : HEColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
        // Primary-only toggle for the position filter.
        if (positions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: InkWell(
              onTap: () => onPrimaryOnly(!primaryOnly),
              borderRadius: BorderRadius.circular(HERadius.xs),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: Checkbox(
                        value: primaryOnly,
                        onChanged: (v) => onPrimaryOnly(v ?? false),
                        activeColor: HEColors.accent,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Primary position only',
                      style: TextStyle(
                        color: HEColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
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

// ── Player row ─────────────────────────────────────────────────────────────────

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.player,
    required this.onEdit,
    required this.onDelete,
  });

  final AdminPlayer player;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AdminImagePreview(
                  url: AdminApi.resolveAssetUrl(player.photoUrl),
                  size: 40,
                  placeholder: Icons.person_outline_rounded,
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Tooltip(
                    message: _hasLegalPhoto(player)
                        ? 'Legal photo (attributed)'
                        : 'Needs a legal photo replacement',
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _hasLegalPhoto(player)
                            ? HEColors.accent
                            : HEColors.error,
                        border: Border.all(color: HEColors.surface, width: 2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    player.name,
                    style: const TextStyle(
                      color: HEColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      PositionChip(player.primaryPosition, primary: true),
                      ...player.altPositions.map(
                        (p) => Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: PositionChip(p),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '${player.nationality} · ${player.club}',
                          style: const TextStyle(
                            color: HEColors.textSecondary,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (player.statBars.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    StatBarsStrip(stats: player.statBars, compact: true),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _KitNumberBadge(player: player),
            const SizedBox(width: 8),
            RatingBadge(player.rating),
            const SizedBox(width: 8),
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

// ── Kit number badge ─────────────────────────────────────────────────────────

/// Shows the shirt number the jersey-back card will actually render — the
/// admin's own [kitNumber] when set, otherwise the same generated fallback
/// the game uses (see squadNumberFor), so this always matches what a player
/// sees in a match rather than just showing "unset".
class _KitNumberBadge extends StatelessWidget {
  const _KitNumberBadge({required this.player});
  final AdminPlayer player;

  @override
  Widget build(BuildContext context) {
    final isSet = player.kitNumber != null;
    final number = player.kitNumber ?? squadNumberFor(player.id);
    return Tooltip(
      message: isSet ? 'Kit number (set)' : 'Kit number (auto-generated)',
      child: Container(
        constraints: const BoxConstraints(minWidth: 32),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: isSet
              ? HEColors.accent.withValues(alpha: 0.14)
              : HEColors.surfaceElevated,
          borderRadius: BorderRadius.circular(HERadius.xs),
          border: Border.all(
            color: isSet
                ? HEColors.accent.withValues(alpha: 0.5)
                : HEColors.divider,
          ),
        ),
        child: Text(
          '#$number',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSet ? HEColors.accent : HEColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ── Player form dialog ─────────────────────────────────────────────────────────

class _PlayerFormDialog extends StatefulWidget {
  const _PlayerFormDialog({this.player});
  final AdminPlayer? player;

  @override
  State<_PlayerFormDialog> createState() => _PlayerFormDialogState();
}

class _PlayerFormDialogState extends State<_PlayerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _rating;
  late final TextEditingController _kitNumber;

  // Stat bars (PAC/SHO/PAS/DRI/DEF/PHY)
  late final TextEditingController _pace;
  late final TextEditingController _shooting;
  late final TextEditingController _passing;
  late final TextEditingController _dribbling;
  late final TextEditingController _defending;
  late final TextEditingController _physical;

  // Positions
  late String _primaryPosition;
  late List<String> _altPositions;

  // Searchable dropdowns
  List<AdminLeague> _leagues = [];
  List<AdminNation> _nations = [];
  List<AdminClub> _clubs = [];
  bool _loadingRefs = true;

  AdminLeague? _selectedLeague;
  AdminNation? _selectedNation;
  AdminClub? _selectedClub;

  String? _nationError;
  String? _clubError;

  // Photo
  late final TextEditingController _photoUrlCtrl;
  Uint8List? _pendingPhotoBytes;
  String? _pendingPhotoFilename;
  UploadStatus _photoUploadStatus = UploadStatus.idle;
  String? _photoUploadError;
  String? _savedPhotoPath;
  late bool _photoLegalOverride;

  bool _saving = false;
  bool get _isEdit => widget.player != null;

  // Only clubs in the selected league (or all clubs when no league selected).
  List<AdminClub> get _filteredClubs {
    if (_selectedLeague == null) return _clubs;
    return _clubs.where((c) => c.league == _selectedLeague!.name).toList();
  }

  // Stored image or name-based CDN fallback, so dropdown rows always show a pic.
  String _clubUrl(AdminClub c) {
    final stored = AdminApi.resolveAssetUrl(c.logoUrl);
    return stored.isNotEmpty ? stored : (clubLogoFallbackUrl(c.name) ?? '');
  }

  String _natUrl(AdminNation n) {
    final stored = AdminApi.resolveAssetUrl(n.flagUrl);
    return stored.isNotEmpty ? stored : (nationFlagFallbackUrl(n.name) ?? '');
  }

  @override
  void initState() {
    super.initState();
    final p = widget.player;
    _name = TextEditingController(text: p?.name ?? '');
    _rating = TextEditingController(text: p != null ? '${p.rating}' : '');
    _kitNumber = TextEditingController(
      text: p?.kitNumber != null ? '${p!.kitNumber}' : '',
    );
    String s(int? v) => v != null ? '$v' : '';
    _pace = TextEditingController(text: s(p?.pace));
    _shooting = TextEditingController(text: s(p?.shooting));
    _passing = TextEditingController(text: s(p?.passing));
    _dribbling = TextEditingController(text: s(p?.dribbling));
    _defending = TextEditingController(text: s(p?.defending));
    _physical = TextEditingController(text: s(p?.physical));
    _primaryPosition = p != null && p.primaryPosition.isNotEmpty
        ? p.primaryPosition
        : 'ST';
    _altPositions = List.of(p?.altPositions ?? []);
    _savedPhotoPath = p?.photoUrl;
    _photoLegalOverride = p?.photoLegalOverride ?? false;
    _photoUrlCtrl = TextEditingController(
      text: AdminApi.resolveAssetUrl(p?.photoUrl),
    );
    _loadRefs(p);
  }

  @override
  void dispose() {
    _name.dispose();
    _rating.dispose();
    _kitNumber.dispose();
    _pace.dispose();
    _shooting.dispose();
    _passing.dispose();
    _dribbling.dispose();
    _defending.dispose();
    _physical.dispose();
    _photoUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRefs(AdminPlayer? p) async {
    try {
      final (nations, clubs, leagues) = await (
        AdminApi.getNations(),
        AdminApi.getClubs(),
        AdminApi.getLeagues(),
      ).wait;
      if (!mounted) return;
      setState(() {
        _nations = nations;
        _clubs = clubs;
        _leagues = leagues;
        _loadingRefs = false;
        if (p != null) {
          _selectedNation = nations
              .where((n) => n.name == p.nationality)
              .firstOrNull;
          _selectedClub = clubs.where((c) => c.name == p.club).firstOrNull;
          // Derive the league from the player's club.
          if (_selectedClub != null) {
            _selectedLeague = leagues
                .where((l) => l.name == _selectedClub!.league)
                .firstOrNull;
          }
        }
      });
    } catch (e) {
      if (mounted) setState(() => _loadingRefs = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    bool hasError = false;
    if (_selectedNation == null) {
      setState(() => _nationError = 'Required');
      hasError = true;
    }
    if (_selectedClub == null) {
      setState(() => _clubError = 'Required');
      hasError = true;
    }
    if (hasError) return;

    setState(() => _saving = true);
    try {
      final manualPhotoUrl = _photoUrlCtrl.text.trim();
      final originalPhotoUrl = AdminApi.resolveAssetUrl(
        widget.player?.photoUrl ?? '',
      );

      int? statOf(TextEditingController c) {
        final t = c.text.trim();
        return t.isEmpty ? null : int.tryParse(t);
      }

      final dto = {
        'name': _name.text.trim(),
        'rating': int.parse(_rating.text.trim()),
        'positions': [_primaryPosition, ..._altPositions],
        'nationality': _selectedNation!.name,
        'club': _selectedClub!.name,
        // Keep the player's league in sync with the chosen club.
        'league': _selectedLeague?.name ?? _selectedClub!.league,
        if (_selectedClub!.logoUrl != null)
          'clubLogoUrl': _selectedClub!.logoUrl,
        if (statOf(_kitNumber) != null) 'kitNumber': statOf(_kitNumber),
        // Stat bars — only sent when filled in.
        if (statOf(_pace) != null) 'pace': statOf(_pace),
        if (statOf(_shooting) != null) 'shooting': statOf(_shooting),
        if (statOf(_passing) != null) 'passing': statOf(_passing),
        if (statOf(_dribbling) != null) 'dribbling': statOf(_dribbling),
        if (statOf(_defending) != null) 'defending': statOf(_defending),
        if (statOf(_physical) != null) 'physical': statOf(_physical),
        // Include manually typed URL only if changed and no file is pending.
        if (manualPhotoUrl.isNotEmpty &&
            manualPhotoUrl != originalPhotoUrl &&
            _pendingPhotoBytes == null)
          'photoUrl': manualPhotoUrl,
        'photoLegalOverride': _photoLegalOverride,
      };

      final AdminPlayer saved;
      if (_isEdit) {
        saved = await AdminApi.updatePlayer(widget.player!.id, dto);
      } else {
        saved = await AdminApi.createPlayer(dto);
      }

      if (_pendingPhotoBytes != null) {
        setState(() => _photoUploadStatus = UploadStatus.uploading);
        try {
          final updated = await AdminApi.uploadPlayerPhoto(
            saved.id,
            _pendingPhotoBytes!,
            _pendingPhotoFilename!,
          );
          if (mounted) {
            setState(() {
              _photoUploadStatus = UploadStatus.success;
              _savedPhotoPath = updated.photoUrl;
              _photoUrlCtrl.text = AdminApi.resolveAssetUrl(updated.photoUrl);
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _saving = false;
              _photoUploadStatus = UploadStatus.error;
              _photoUploadError = e.toString();
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Player saved, but photo upload failed: $e'),
              ),
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
    return AlertDialog(
      backgroundColor: HEColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      contentPadding: EdgeInsets.zero,
      titlePadding: EdgeInsets.zero,
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      title: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
        decoration: const BoxDecoration(
          color: HEColors.surfaceElevated,
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Row(
          children: [
            Text(
              _isEdit ? 'Edit Player' : 'Add Player',
              style: const TextStyle(
                color: HEColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              color: HEColors.textSecondary,
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Basic info ──────────────────────────────────────────────
                AdminTextField(
                  controller: _name,
                  label: 'Name',
                  hint: 'e.g. Erling Haaland',
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 14),
                AdminTextField(
                  controller: _rating,
                  label: 'Rating',
                  hint: '1–99',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    if (n == null || n < 1 || n > 99) return '1–99';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                AdminTextField(
                  controller: _kitNumber,
                  label: 'Kit Number (optional)',
                  hint: 'Leave blank to auto-generate',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return null;
                    final n = int.tryParse(t);
                    return (n == null || n < 1 || n > 99) ? '1–99' : null;
                  },
                ),

                // ── Stat bars ───────────────────────────────────────────────
                const SizedBox(height: 20),
                const AdminSectionHeader('Stat Bars (1–99)'),
                const SizedBox(height: 10),
                _StatFieldsGrid(
                  pace: _pace,
                  shooting: _shooting,
                  passing: _passing,
                  dribbling: _dribbling,
                  defending: _defending,
                  physical: _physical,
                  onChanged: () => setState(() {}),
                ),

                // ── Nationality ─────────────────────────────────────────────
                const SizedBox(height: 20),
                AdminSearchableDropdown<AdminNation>(
                  label: 'Nationality',
                  items: _nations,
                  labelOf: (n) => n.name,
                  value: _selectedNation,
                  hint: 'Select nationality',
                  errorText: _nationError,
                  loading: _loadingRefs,
                  leadingOf: (n) => AdminImagePreview(
                    url: _natUrl(n),
                    size: 22,
                    placeholder: Icons.flag_outlined,
                  ),
                  onChanged: (n) => setState(() {
                    _selectedNation = n;
                    _nationError = null;
                  }),
                ),

                // ── League (filters club list) ──────────────────────────────
                const SizedBox(height: 16),
                AdminSearchableDropdown<AdminLeague>(
                  label: 'League',
                  items: _leagues,
                  labelOf: (l) => l.name,
                  value: _selectedLeague,
                  hint: 'Select league (filters clubs)',
                  loading: _loadingRefs,
                  leadingOf: (l) => AdminImagePreview(
                    url: AdminApi.resolveAssetUrl(l.logoUrl),
                    size: 22,
                    placeholder: Icons.sports_soccer_rounded,
                  ),
                  onChanged: (l) => setState(() {
                    _selectedLeague = l;
                    // Clear club if it doesn't belong to the new league.
                    if (l != null &&
                        _selectedClub != null &&
                        _selectedClub!.league != l.name) {
                      _selectedClub = null;
                    }
                  }),
                ),

                // ── Club (filtered by selected league) ──────────────────────
                const SizedBox(height: 16),
                AdminSearchableDropdown<AdminClub>(
                  label: 'Club',
                  items: _filteredClubs,
                  labelOf: (c) => c.name,
                  value: _selectedClub,
                  hint: _selectedLeague != null
                      ? 'Select club (${_filteredClubs.length} in league)'
                      : 'Select club',
                  errorText: _clubError,
                  loading: _loadingRefs,
                  leadingOf: (c) => AdminImagePreview(
                    url: _clubUrl(c),
                    size: 22,
                    placeholder: Icons.shield_outlined,
                  ),
                  onChanged: (c) => setState(() {
                    _selectedClub = c;
                    _clubError = null;
                  }),
                ),

                // ── Positions ───────────────────────────────────────────────
                const SizedBox(height: 20),
                _PositionsPicker(
                  primaryPosition: _primaryPosition,
                  altPositions: _altPositions,
                  onPrimaryChanged: (p) => setState(() {
                    _primaryPosition = p;
                    _altPositions.remove(p);
                  }),
                  onAltChanged: (alts) => setState(() => _altPositions = alts),
                ),

                // ── Photo ───────────────────────────────────────────────────
                const SizedBox(height: 20),
                const AdminSectionHeader('Player Photo'),
                const SizedBox(height: 10),
                AdminImageUploader(
                  currentUrl: AdminApi.resolveAssetUrl(widget.player?.photoUrl),
                  placeholder: Icons.person_outline_rounded,
                  status: _photoUploadStatus,
                  errorMessage: _photoUploadError,
                  savedPath: _savedPhotoPath,
                  urlController: _photoUrlCtrl,
                  onFilePicked: (bytes, name) => setState(() {
                    _pendingPhotoBytes = bytes;
                    _pendingPhotoFilename = name;
                    _photoUploadStatus = UploadStatus.idle;
                    _photoUploadError = null;
                  }),
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: () => setState(
                    () => _photoLegalOverride = !_photoLegalOverride,
                  ),
                  borderRadius: BorderRadius.circular(HERadius.xs),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: Checkbox(
                            value: _photoLegalOverride,
                            onChanged: (v) => setState(
                              () => _photoLegalOverride = v ?? false,
                            ),
                            activeColor: HEColors.accent,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Mark photo as legally verified',
                                style: TextStyle(
                                  color: HEColors.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'For uploaded files only — the app can already '
                                'auto-detect Wikimedia URLs as legal. Check this '
                                'only once you\'ve personally confirmed this '
                                'photo\'s source is properly licensed for use.',
                                style: TextStyle(
                                  color: HEColors.textMuted.withValues(
                                    alpha: 0.9,
                                  ),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 4),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          icon: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black54,
                  ),
                )
              : const Icon(Icons.check_rounded, size: 16),
          label: Text(_isEdit ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}

// ── Stat fields grid ─────────────────────────────────────────────────────────

class _StatFieldsGrid extends StatelessWidget {
  const _StatFieldsGrid({
    required this.pace,
    required this.shooting,
    required this.passing,
    required this.dribbling,
    required this.defending,
    required this.physical,
    required this.onChanged,
  });

  final TextEditingController pace;
  final TextEditingController shooting;
  final TextEditingController passing;
  final TextEditingController dribbling;
  final TextEditingController defending;
  final TextEditingController physical;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final fields = <(String, TextEditingController)>[
      ('PAC', pace),
      ('SHO', shooting),
      ('PAS', passing),
      ('DRI', dribbling),
      ('DEF', defending),
      ('PHY', physical),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        // 3 per row, accounting for spacing.
        final w = (constraints.maxWidth - 2 * 10) / 3;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: fields.map((f) {
            return SizedBox(
              width: w,
              child: TextFormField(
                controller: f.$2,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                onChanged: (_) => onChanged(),
                style: const TextStyle(
                  color: HEColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  labelText: f.$1,
                  hintText: '—',
                  labelStyle: const TextStyle(
                    color: HEColors.textSecondary,
                    fontSize: 12,
                  ),
                  hintStyle: const TextStyle(
                    color: HEColors.textMuted,
                    fontSize: 13,
                  ),
                  isDense: true,
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

// ── Positions picker ───────────────────────────────────────────────────────────

class _PositionsPicker extends StatelessWidget {
  const _PositionsPicker({
    required this.primaryPosition,
    required this.altPositions,
    required this.onPrimaryChanged,
    required this.onAltChanged,
  });

  final String primaryPosition;
  final List<String> altPositions;
  final ValueChanged<String> onPrimaryChanged;
  final ValueChanged<List<String>> onAltChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Primary
        Row(
          children: [
            const Text(
              'PRIMARY POSITION',
              style: TextStyle(
                color: HEColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: HEColors.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(HERadius.xs),
              ),
              child: Text(
                primaryPosition,
                style: const TextStyle(
                  color: HEColors.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: kAllPositions.map((pos) {
            final isSelected = pos == primaryPosition;
            return GestureDetector(
              onTap: () => onPrimaryChanged(pos),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? HEColors.accent.withValues(alpha: 0.20)
                      : HEColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(HERadius.xs),
                  border: Border.all(
                    color: isSelected ? HEColors.accent : HEColors.divider,
                  ),
                ),
                child: Text(
                  pos,
                  style: TextStyle(
                    color: isSelected
                        ? HEColors.accent
                        : HEColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 16),

        // Alt positions
        const Text(
          'ALT POSITIONS (optional)',
          style: TextStyle(
            color: HEColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Used for future lineup swap logic.',
          style: TextStyle(color: HEColors.textMuted, fontSize: 11),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: kAllPositions.map((pos) {
            final isPrimary = pos == primaryPosition;
            final isSelected = altPositions.contains(pos);
            return GestureDetector(
              onTap: isPrimary
                  ? null
                  : () {
                      final updated = List<String>.from(altPositions);
                      if (isSelected) {
                        updated.remove(pos);
                      } else {
                        updated.add(pos);
                      }
                      onAltChanged(updated);
                    },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: isPrimary
                      ? HEColors.surfaceElevated.withValues(alpha: 0.4)
                      : isSelected
                      ? HEColors.accentMuted.withValues(alpha: 0.18)
                      : HEColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(HERadius.xs),
                  border: Border.all(
                    color: isPrimary
                        ? HEColors.divider.withValues(alpha: 0.4)
                        : isSelected
                        ? HEColors.accentMuted
                        : HEColors.divider,
                  ),
                ),
                child: Text(
                  pos,
                  style: TextStyle(
                    color: isPrimary
                        ? HEColors.textMuted.withValues(alpha: 0.5)
                        : isSelected
                        ? HEColors.accentMuted
                        : HEColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
