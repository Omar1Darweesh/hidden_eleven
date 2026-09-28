import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/app/routes.dart';
import 'package:hidden_eleven/features/admin/models/admin_models.dart';
import 'package:hidden_eleven/features/admin/services/admin_api.dart';
import 'package:hidden_eleven/features/lobby/room_provider.dart';
import 'package:hidden_eleven/features/lobby/room_socket_service.dart';
import 'package:hidden_eleven/shared/widgets/first_touch_layout.dart';
import 'package:hidden_eleven/shared/widgets/focusable_tap.dart';
import 'package:hidden_eleven/shared/widgets/he_button.dart';
import 'package:hidden_eleven/shared/widgets/he_logo_mark.dart';
import 'package:hidden_eleven/shared/widgets/hero_entrance.dart';
import 'package:hidden_eleven/shared/widgets/matchday_background.dart';
import 'package:hidden_eleven/shared/widgets/primary_cta_glow.dart';
import 'package:hidden_eleven/shared/widgets/screen_entrance.dart';

class HostRoomScreen extends ConsumerStatefulWidget {
  const HostRoomScreen({
    super.key,
    required this.displayName,
    this.initialBotCount = 0,
  });

  final String displayName;

  /// Seeds the AI-opponents count on open — used by the home screen's
  /// "Play vs AI" entry point so it lands here (with every normal host
  /// setting — leagues, tournament, timers — available) already defaulted
  /// to a 1-bot solo game, rather than skipping this screen and its
  /// settings entirely.
  final int initialBotCount;

  @override
  ConsumerState<HostRoomScreen> createState() => _HostRoomScreenState();
}

class _HostRoomScreenState extends ConsumerState<HostRoomScreen> {
  bool _loading = false;
  bool _leaguesLoading = true;
  List<AdminLeague> _allLeagues = [];
  final Set<String> _selectedNames = {};
  String? _leagueError;

  /// `bundle` = pick an admin pack; `manual` = existing multi-select.
  String _leagueMode = 'manual';
  List<ActiveLeagueBundle> _bundles = [];
  String? _selectedBundleId;
  bool _bundlesLoading = false;

  // null = no limit
  int? _turnTimerSeconds = 30;
  int? _subsTimerSeconds = 120;
  // null = falls back to the turn timer, then a fixed server-side default.
  int? _abilityTimerSeconds = 45;

  // Formations
  List<AdminFormation> _formations = [];
  String? _selectedFormationSlug; // null = random

  // Tournament mode — off by default; host must explicitly enable it.
  bool _tournamentEnabled = false;
  // Only meaningful once a tournament actually simulates match events —
  // defaults to today's existing pacing when the host never touches it.
  String _simulationSpeed = 'normal';

  // AI opponents — seeded from widget.initialBotCount (0 for a normal hosted
  // room, 1 for the "Play vs AI" entry point), but always host-adjustable:
  // a solo game can be widened to more bots, and a normal room can add
  // bots too, e.g. to fill seats real players haven't taken yet.
  late int _botCount = widget.initialBotCount;

  // Advanced settings collapsed by default — quick-create tier (Leagues,
  // Turn Timer, AI Opponents) always stays visible; everything else lives
  // behind this toggle unless a validation error belongs to it. Nothing
  // mandatory for a valid room configuration is ever hidden here — every
  // field behind this toggle already has a working server-side default.
  bool _moreSettingsExpanded = false;

  /// True only if the host actually changed something away from its
  /// default — computed, not tracked imperatively, so it can't drift out of
  /// sync with the many existing `setState` call sites above. Backs the
  /// back-button discard confirmation: no dialog for an untouched screen.
  bool get _isDirty =>
      _leagueMode != 'manual' ||
      _selectedNames.isNotEmpty ||
      _turnTimerSeconds != 30 ||
      _subsTimerSeconds != 120 ||
      _abilityTimerSeconds != 45 ||
      _selectedFormationSlug != null ||
      _tournamentEnabled ||
      _simulationSpeed != 'normal' ||
      _botCount != widget.initialBotCount;

  Future<void> _handleBack() async {
    if (!_isDirty) {
      context.pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HETheme.pfSurfaceGlass,
        title: const Text('Discard room settings?'),
        content: const Text(
          "You've changed some settings for this room. Going back will "
          'discard them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: HETheme.pfDanger),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) context.pop();
  }

  @override
  void initState() {
    super.initState();
    _loadLeagues();
    _loadBundles();
    _loadFormations();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(roomSocketServiceProvider).connect();
    });
    ref.listenManual(serverErrorProvider, (_, next) {
      next.whenData((err) {
        if (!mounted) return;
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlyServerError(err.code))));
      });
    });
    ref.listenManual(socketDisconnectedProvider, (prev, next) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not connect to server.')),
      );
    });
  }

  Future<void> _loadFormations() async {
    try {
      final formations = await AdminApi.getFormations();
      if (!mounted) return;
      setState(() {
        _formations = formations.where((f) => f.active).toList();
      });
    } catch (_) {}
  }

  Future<void> _loadLeagues() async {
    try {
      final leagues = await AdminApi.getLeagues();
      if (!mounted) return;
      setState(() {
        // Only leagues toggled "allowed" in the admin can be played in rooms.
        _allLeagues = leagues.where((l) => l.active).toList();
        _leaguesLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _leaguesLoading = false);
    }
  }

  Future<void> _loadBundles() async {
    setState(() => _bundlesLoading = true);
    try {
      final bundles = await AdminApi.getActiveLeagueBundles();
      if (!mounted) return;
      setState(() {
        _bundles = bundles;
        _bundlesLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _bundlesLoading = false);
    }
  }

  void _toggleLeague(String name) {
    setState(() {
      if (_selectedNames.contains(name)) {
        _selectedNames.remove(name);
      } else {
        _selectedNames.add(name);
      }
      _leagueError = null;
    });
  }

  void _setLeagueMode(String mode) {
    setState(() {
      _leagueMode = mode;
      _leagueError = null;
      if (mode == 'manual') {
        _selectedBundleId = null;
      } else {
        _selectedNames.clear();
      }
    });
  }

  void _selectBundle(String id) {
    setState(() {
      _selectedBundleId = id;
      _leagueError = null;
    });
  }

  String _friendlyServerError(String code) => switch (code) {
    'INVALID_LEAGUE_BUNDLE' =>
      'That league bundle could not be used. Pick another bundle, '
          'or switch to Select manually. (Admin → League Bundles to manage packs.)',
    'AMBIGUOUS_LEAGUES' =>
      'Choose either a bundle or manual leagues, not both.',
    'INVALID_RATING_RANGE' =>
      'The minimum rating can\'t be higher than the maximum.',
    _ => 'Error: $code',
  };

  void _openLobby() {
    if (_leagueMode == 'bundle' && _selectedBundleId == null) {
      setState(() => _leagueError = 'Select a league bundle to continue.');
      return;
    }
    // Manual mode: empty selection is intentional — server treats [] as all
    // leagues. Bundle mode always sends leagueBundleId instead.
    setState(() => _loading = true);
    ref
        .read(roomProvider.notifier)
        .createRoom(
          widget.displayName,
          leagues: _leagueMode == 'manual' ? _selectedNames.toList() : const [],
          leagueBundleId: _leagueMode == 'bundle' ? _selectedBundleId : null,
          turnTimerSeconds: _turnTimerSeconds,
          subsTimerSeconds: _subsTimerSeconds,
          abilityTimerSeconds: _abilityTimerSeconds,
          formationSlug: _selectedFormationSlug,
          tournamentEnabled: _tournamentEnabled,
          simulationSpeed: _simulationSpeed,
          botCount: _botCount > 0 ? _botCount : null,
          // Rating window is now set live in the LOBBY (against the real
          // player count), not blind at creation — see _RatingRangeCard.
        );
  }

  // ── Section card scaffold ──────────────────────────────────────────────────

  /// Consistent section card: thin cyan-tinted left accent bar, icon, label,
  /// subtitle, then [child] content. Replaces the raw HECard+Row+Icon pattern.
  Widget _sectionCard({
    required IconData icon,
    required String label,
    required String subtitle,
    required Widget content,
    Widget? trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: HETheme.pfSurfaceGlass,
        borderRadius: BorderRadius.circular(HETheme.radiusLg),
        border: Border.all(color: HETheme.pfBorder),
        // Subtle left accent bar implemented via a left border override below.
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HETheme.spaceXl,
              HETheme.spaceLg,
              HETheme.spaceXl,
              0,
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: HETheme.pfAccentViolet.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(HETheme.radiusSm),
                    border: Border.all(
                      color: HETheme.pfAccentViolet.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Icon(icon, color: HETheme.pfAccentViolet, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label.toUpperCase(),
                        style: const TextStyle(
                          color: HETheme.pfTextSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: HETheme.pfTextMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(HETheme.spaceXl),
            child: content,
          ),
        ],
      ),
    );
  }

  Widget _buildTournamentToggle() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: _tournamentEnabled
            ? HETheme.pfGold.withValues(alpha: 0.06)
            : HETheme.pfSurfaceGlass,
        borderRadius: BorderRadius.circular(HETheme.radiusLg),
        border: Border.all(
          color: _tournamentEnabled
              ? HETheme.pfGold.withValues(alpha: 0.30)
              : HETheme.pfBorder,
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: HETheme.spaceXl,
        vertical: HETheme.spaceLg,
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color:
                  (_tournamentEnabled ? HETheme.pfGold : HETheme.pfAccentViolet)
                      .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(HETheme.radiusSm),
              border: Border.all(
                color:
                    (_tournamentEnabled
                            ? HETheme.pfGold
                            : HETheme.pfAccentViolet)
                        .withValues(alpha: 0.28),
              ),
            ),
            child: Icon(
              Icons.emoji_events_outlined,
              color: _tournamentEnabled
                  ? HETheme.pfGold
                  : HETheme.pfAccentViolet,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'TOURNAMENT MODE',
                  style: TextStyle(
                    color: _tournamentEnabled
                        ? HETheme.pfGold
                        : HETheme.pfTextSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 1),
                const Text(
                  'Knockout bracket after the draft.',
                  style: TextStyle(color: HETheme.pfTextMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          Switch(
            value: _tournamentEnabled,
            onChanged: (v) => setState(() => _tournamentEnabled = v),
            activeThumbColor: HETheme.pfGold,
            activeTrackColor: HETheme.pfGold.withValues(alpha: 0.25),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(roomProvider, (_, room) {
      if (room != null && mounted) {
        context.goNamed(Routes.lobby, pathParameters: {'roomCode': room.code});
      }
    });

    return Scaffold(
      backgroundColor: HETheme.pfBgVoid,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: _loading ? null : _handleBack,
        ),
        title: const Text('Set Up Room'),
      ),
      body: Stack(
        children: [
          const MatchdayBackground(),
          SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: FirstTouchLayout(
                  child: ScreenEntrance(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Hero header ──────────────────────────────────────────────
                        HeroEntrance(
                          child: _HostHeroHeader(
                            displayName: widget.displayName,
                          ),
                        ),

                        const SizedBox(height: 28),

                        // ── League picker ─────────────────────────────────────────────
                        _sectionCard(
                          icon: Icons.sports_soccer_rounded,
                          label: 'Leagues',
                          subtitle: _leagueMode == 'bundle'
                              ? 'Choose one ready-made pack. Its leagues are copied into this room.'
                              : 'Select leagues to draft from, or leave none selected to use all allowed leagues.',
                          trailing:
                              _leagueMode == 'manual' && _allLeagues.isNotEmpty
                              ? _CountBadge(
                                  count: _selectedNames.length,
                                  total: _allLeagues.length,
                                )
                              : null,
                          content: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _LeagueModeChip(
                                    label: 'Use a bundle',
                                    selected: _leagueMode == 'bundle',
                                    onTap: () => _setLeagueMode('bundle'),
                                  ),
                                  _LeagueModeChip(
                                    label: 'Select manually',
                                    selected: _leagueMode == 'manual',
                                    onTap: () => _setLeagueMode('manual'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              if (_leagueMode == 'bundle') ...[
                                if (_bundlesLoading)
                                  const Center(
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: CircularProgressIndicator(
                                        color: HETheme.pfAccentViolet,
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                else if (_bundles.isEmpty)
                                  const Text(
                                    'No active league bundles yet. Open Admin → '
                                    'League Bundles to create one (New bundle), '
                                    'or switch to Select manually.',
                                    style: TextStyle(
                                      color: HETheme.pfTextSecondary,
                                      fontSize: 13,
                                    ),
                                  )
                                else
                                  _BundlePicker(
                                    bundles: _bundles,
                                    selectedId: _selectedBundleId,
                                    onSelect: _selectBundle,
                                  ),
                              ] else if (_leaguesLoading)
                                const Center(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 8),
                                    child: CircularProgressIndicator(
                                      color: HETheme.pfAccentViolet,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              else if (_allLeagues.isEmpty)
                                const Text(
                                  'No leagues found. Add leagues in the Admin panel first.',
                                  style: TextStyle(
                                    color: HETheme.pfTextSecondary,
                                    fontSize: 13,
                                  ),
                                )
                              else ...[
                                _LeagueGrid(
                                  leagues: _allLeagues,
                                  selected: _selectedNames,
                                  onToggle: _toggleLeague,
                                ),
                                if (_selectedNames.isEmpty) ...[
                                  const SizedBox(height: 10),
                                  const Text(
                                    'None selected — this room will use every allowed league.',
                                    style: TextStyle(
                                      color: HETheme.pfTextMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                              if (_leagueError != null) ...[
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.warning_rounded,
                                      color: HETheme.pfDanger,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _leagueError!,
                                        style: const TextStyle(
                                          color: HETheme.pfDanger,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ── Formation picker — always visible (quick-create tier).
                        // Moved out of "More settings": this is a core
                        // room-creation decision on par with League, not a
                        // secondary/advanced field, so it must never be hidden
                        // behind a collapsed disclosure on any viewport.
                        if (_formations.isNotEmpty) ...[
                          _sectionCard(
                            icon: Icons.grid_view_rounded,
                            label: 'Formation',
                            subtitle:
                                'Pick a specific formation or let the server choose.',
                            content: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _FormationChip(
                                  label: 'Random',
                                  isSelected: _selectedFormationSlug == null,
                                  onTap: () => setState(
                                    () => _selectedFormationSlug = null,
                                  ),
                                ),
                                for (final f in _formations)
                                  _FormationChip(
                                    label: f.name,
                                    isSelected:
                                        _selectedFormationSlug == f.slug,
                                    onTap: () => setState(
                                      () => _selectedFormationSlug = f.slug,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // ── Turn timer (quick-create tier) ───────────────────────────
                        _sectionCard(
                          icon: Icons.timer_rounded,
                          label: 'Turn Time Limit',
                          subtitle: 'Auto-pick fires when time runs out.',
                          content: _TurnTimerSelector(
                            value: _turnTimerSeconds,
                            onChanged: (v) =>
                                setState(() => _turnTimerSeconds = v),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ── AI opponents (quick-create tier) ─────────────────────────
                        // Deliberately independent of who else joins: bots fill seats
                        // real players haven't taken, so "1 friend + 2 bots" and
                        // "solo vs AI" are the same slider, not two separate modes.
                        _sectionCard(
                          icon: Icons.smart_toy_outlined,
                          label: 'AI Opponents',
                          subtitle: _botCount == 0
                              ? 'Add bots to play solo, or to fill seats real players haven\'t taken.'
                              : '$_botCount AI ${_botCount == 1 ? 'opponent' : 'opponents'} will join this room.',
                          content: _BotCountSelector(
                            value: _botCount,
                            onChanged: (v) => setState(() => _botCount = v),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ── More settings — collapsed by default. Every field in
                        // here already has a working server-side default, so
                        // nothing mandatory for a valid room is ever hidden.
                        _MoreSettingsToggle(
                          expanded: _moreSettingsExpanded,
                          onTap: () => setState(
                            () =>
                                _moreSettingsExpanded = !_moreSettingsExpanded,
                          ),
                        ),
                        if (_moreSettingsExpanded) ...[
                          const SizedBox(height: 16),

                          // ── Subs timer ──────────────────────────────────────────
                          _sectionCard(
                            icon: Icons.hourglass_bottom_rounded,
                            label: 'Subs Phase Limit',
                            subtitle:
                                'Auto-confirm all lineups when the timer expires.',
                            content: _TurnTimerSelector(
                              value: _subsTimerSeconds,
                              onChanged: (v) =>
                                  setState(() => _subsTimerSeconds = v),
                              options: const [
                                (60, '1 min'),
                                (120, '2 min'),
                                (180, '3 min'),
                                (300, '5 min'),
                                (null, 'No limit'),
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),

                          // ── Ability usage timer ────────────────────────────────
                          _sectionCard(
                            icon: Icons.auto_awesome_rounded,
                            label: 'Ability Usage Time',
                            subtitle:
                                'Auto-discards an unused ability when time runs out.',
                            content: _TurnTimerSelector(
                              value: _abilityTimerSeconds,
                              onChanged: (v) =>
                                  setState(() => _abilityTimerSeconds = v),
                              options: const [
                                (15, '15s'),
                                (30, '30s'),
                                (45, '45s'),
                                (60, '60s'),
                                (90, '90s'),
                                // A genuine no-limit choice — the server no longer
                                // arms any safety-net deadline for this phase when
                                // null, same semantics as the Turn/Subs timers above.
                                (null, 'No limit'),
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),

                          // ── Tournament toggle ──────────────────────────────────
                          _buildTournamentToggle(),

                          // ── Simulation speed — only meaningful once a tournament
                          // actually simulates match events ─────────────────────
                          if (_tournamentEnabled) ...[
                            const SizedBox(height: 16),
                            _sectionCard(
                              icon: Icons.speed_rounded,
                              label: 'Simulation Speed',
                              subtitle:
                                  'How fast match events play out during a live sim.',
                              content: _SimSpeedSelector(
                                value: _simulationSpeed,
                                onChanged: (v) =>
                                    setState(() => _simulationSpeed = v),
                              ),
                            ),
                          ],
                        ],

                        const SizedBox(height: 24),

                        // ── Room Brief — live summary of what's about to be
                        // created, derived from local state already above ────────
                        _RoomBriefSummary(
                          leagueSummary: _leagueMode == 'bundle'
                              ? (_selectedBundleId != null
                                    ? _bundles
                                          .firstWhere(
                                            (b) => b.id == _selectedBundleId,
                                          )
                                          .name
                                    : 'No bundle selected')
                              : (_selectedNames.isEmpty
                                    ? 'All allowed leagues'
                                    : _selectedNames.join(', ')),
                          turnTimerLabel: _turnTimerSeconds == null
                              ? 'No turn limit'
                              : '${_turnTimerSeconds}s turns',
                          botLabel: _botCount == 0
                              ? 'No AI opponents'
                              : '$_botCount AI ${_botCount == 1 ? 'opponent' : 'opponents'}',
                          formationLabel: _selectedFormationSlug == null
                              ? 'Random formation'
                              : _formations
                                    .firstWhere(
                                      (f) => f.slug == _selectedFormationSlug,
                                    )
                                    .name,
                          tournamentEnabled: _tournamentEnabled,
                        ),

                        const SizedBox(height: 24),

                        // ── Primary CTA — cyan glow: this is the primary action,
                        // not a hidden/reveal moment (gold stays reserved for
                        // classified/hidden-pick contexts only) ─────────────────
                        PrimaryCtaGlow(
                          child: HEButton(
                            label: 'Open Lobby',
                            icon: Icons.meeting_room_rounded,
                            loading: _loading,
                            onPressed: _loading ? null : _openLobby,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Host hero header ──────────────────────────────────────────────────────────

/// Branded setup header — establishes context ("you are setting up a match")
/// using the navy/cyan visual language rather than a generic form icon.
class _HostHeroHeader extends StatelessWidget {
  const _HostHeroHeader({required this.displayName});
  final String displayName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(HETheme.spaceXxl),
      decoration: BoxDecoration(
        color: HETheme.pfSurfaceDeep.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(HETheme.radiusLg),
        border: Border.all(
          color: HETheme.pfAccentViolet.withValues(alpha: 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: HETheme.pfAccentViolet.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Real Hidden Eleven logo — the same treatment used on the Home page,
          // so these screens feel branded rather than generic.
          const HELogoMark(height: 72, compact: true),
          const SizedBox(height: 16),
          Text(
            'Set Up Your Room',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: HETheme.pfTextPrimary,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 6),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: const TextStyle(
                color: HETheme.pfTextSecondary,
                fontSize: 13,
              ),
              children: [
                const TextSpan(text: 'Hosting as '),
                TextSpan(
                  text: displayName,
                  style: const TextStyle(
                    color: HETheme.pfAccentViolet,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const TextSpan(
                  text: '  ·  A unique room code will be generated for you.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── More settings toggle ──────────────────────────────────────────────────────

/// Progressive-disclosure control for the advanced settings group (Subs
/// timer, Ability timer, Formation, Tournament mode). A first-time host can
/// create a room from the always-visible quick-create tier alone; nothing
/// behind this toggle is mandatory for a valid configuration.
class _MoreSettingsToggle extends StatelessWidget {
  const _MoreSettingsToggle({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: expanded ? 'Hide more settings' : 'Show more settings',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(HETheme.radiusMd),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                expanded ? 'Hide more settings' : 'More settings',
                style: const TextStyle(
                  color: HETheme.pfAccentViolet,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: HETheme.pfAccentViolet,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Room brief summary ────────────────────────────────────────────────────────

/// Live, read-only recap of the room about to be created — derived purely
/// from this screen's own local state, no new backend calls. Lets a host
/// confirm at a glance what they've configured without hunting back through
/// every section card, especially once some of them are collapsed.
class _RoomBriefSummary extends StatelessWidget {
  const _RoomBriefSummary({
    required this.leagueSummary,
    required this.turnTimerLabel,
    required this.botLabel,
    required this.formationLabel,
    required this.tournamentEnabled,
  });

  final String leagueSummary;
  final String turnTimerLabel;
  final String botLabel;
  final String formationLabel;
  final bool tournamentEnabled;

  @override
  Widget build(BuildContext context) {
    final parts = [
      leagueSummary,
      turnTimerLabel,
      botLabel,
      formationLabel,
      if (tournamentEnabled) 'Tournament mode',
    ];
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: HETheme.spaceLg,
        vertical: HETheme.spaceMd,
      ),
      decoration: BoxDecoration(
        color: HETheme.pfSurfaceRaised,
        borderRadius: BorderRadius.circular(HETheme.radiusMd),
        border: Border.all(color: HETheme.pfBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.summarize_outlined,
            color: HETheme.pfTextMuted,
            size: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              parts.join('  ·  '),
              style: const TextStyle(
                color: HETheme.pfTextSecondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Count badge ───────────────────────────────────────────────────────────────

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.total});
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final hasSelection = count > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: hasSelection
            ? HETheme.pfAccentViolet.withValues(alpha: 0.12)
            : HETheme.pfSurfaceGlass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasSelection
              ? HETheme.pfAccentViolet.withValues(alpha: 0.40)
              : HETheme.pfBorder,
        ),
      ),
      child: Text(
        '$count / $total',
        style: TextStyle(
          color: hasSelection ? HETheme.pfAccentViolet : HETheme.pfTextMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── Formation chip ────────────────────────────────────────────────────────────

class _FormationChip extends StatelessWidget {
  const _FormationChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FocusableTap(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected
              ? HETheme.pfAccentViolet.withValues(alpha: 0.12)
              : HETheme.pfSurfaceRaised,
          borderRadius: BorderRadius.circular(HETheme.radiusSm),
          border: Border.all(
            color: isSelected
                ? HETheme.pfAccentViolet.withValues(alpha: 0.55)
                : HETheme.pfBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? HETheme.pfAccentViolet : HETheme.pfTextPrimary,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ── Turn timer selector ───────────────────────────────────────────────────────

class _TurnTimerSelector extends StatelessWidget {
  const _TurnTimerSelector({
    required this.value,
    required this.onChanged,
    this.options = _defaultOptions,
  });

  final int? value;
  final ValueChanged<int?> onChanged;
  final List<(int?, String)> options;

  static const _defaultOptions = <(int?, String)>[
    (15, '15s'),
    (30, '30s'),
    (45, '45s'),
    (60, '60s'),
    (90, '90s'),
    (null, 'No limit'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final (secs, label) = opt;
        final isSelected = value == secs;
        return FocusableTap(
          onTap: () => onChanged(secs),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: isSelected
                  ? HETheme.pfAccentViolet.withValues(alpha: 0.12)
                  : HETheme.pfSurfaceRaised,
              borderRadius: BorderRadius.circular(HETheme.radiusSm),
              border: Border.all(
                color: isSelected
                    ? HETheme.pfAccentViolet.withValues(alpha: 0.55)
                    : HETheme.pfBorder,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? HETheme.pfAccentViolet
                    : HETheme.pfTextPrimary,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── AI opponent count selector ────────────────────────────────────────────────

class _BotCountSelector extends StatelessWidget {
  const _BotCountSelector({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  // Capped at 4 here (not the server's 9): the room still needs room for
  // actual humans in the common case, and a wall of bot chips would crowd
  // out the far more likely "0, 1, or a couple" choices.
  static const _options = <(int, String)>[
    (0, 'None'),
    (1, '1'),
    (2, '2'),
    (3, '3'),
    (4, '4'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _options.map((opt) {
        final (count, label) = opt;
        final isSelected = value == count;
        return FocusableTap(
          onTap: () => onChanged(count),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: isSelected
                  ? HETheme.pfAccentViolet.withValues(alpha: 0.12)
                  : HETheme.pfSurfaceRaised,
              borderRadius: BorderRadius.circular(HETheme.radiusSm),
              border: Border.all(
                color: isSelected
                    ? HETheme.pfAccentViolet.withValues(alpha: 0.55)
                    : HETheme.pfBorder,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? HETheme.pfAccentViolet
                    : HETheme.pfTextPrimary,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Simulation speed selector ─────────────────────────────────────────────────

/// Fast / Normal / Slow — controls how quickly tournament match events are
/// delivered to clients during a live simulation. Purely a pacing/
/// presentation choice: the simulated result itself is already fully decided
/// before this timing applies, so it can never change match outcomes.
class _SimSpeedSelector extends StatelessWidget {
  const _SimSpeedSelector({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  static const _options = <(String, String, String)>[
    ('fast', 'Fast', 'Quicker recap'),
    ('normal', 'Normal', 'Default pace'),
    ('slow', 'Slow', 'Savor the drama'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (speed, label, hint) in _options) ...[
          if (speed != _options.first.$1) const SizedBox(width: 8),
          Expanded(
            child: _SimSpeedChip(
              label: label,
              hint: hint,
              isSelected: value == speed,
              onTap: () => onChanged(speed),
            ),
          ),
        ],
      ],
    );
  }
}

class _SimSpeedChip extends StatelessWidget {
  const _SimSpeedChip({
    required this.label,
    required this.hint,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final String hint;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FocusableTap(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? HETheme.pfAccentViolet.withValues(alpha: 0.12)
              : HETheme.pfSurfaceRaised,
          borderRadius: BorderRadius.circular(HETheme.radiusSm),
          border: Border.all(
            color: isSelected
                ? HETheme.pfAccentViolet.withValues(alpha: 0.55)
                : HETheme.pfBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? HETheme.pfAccentViolet
                    : HETheme.pfTextPrimary,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: const TextStyle(color: HETheme.pfTextMuted, fontSize: 9.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ── League mode / bundle picker ───────────────────────────────────────────────

class _LeagueModeChip extends StatelessWidget {
  const _LeagueModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FocusableTap(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? HETheme.pfAccentViolet.withValues(alpha: 0.14)
              : HETheme.pfSurfaceRaised,
          borderRadius: BorderRadius.circular(HETheme.radiusMd),
          border: Border.all(
            color: selected
                ? HETheme.pfAccentViolet.withValues(alpha: 0.55)
                : HETheme.pfBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? HETheme.pfAccentViolet : HETheme.pfTextPrimary,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _BundlePicker extends StatelessWidget {
  const _BundlePicker({
    required this.bundles,
    required this.selectedId,
    required this.onSelect,
  });

  final List<ActiveLeagueBundle> bundles;
  final String? selectedId;
  final void Function(String id) onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final b in bundles) ...[
          _BundleCard(
            bundle: b,
            selected: selectedId == b.id,
            onTap: () => onSelect(b.id),
          ),
          if (b != bundles.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _BundleCard extends StatelessWidget {
  const _BundleCard({
    required this.bundle,
    required this.selected,
    required this.onTap,
  });

  final ActiveLeagueBundle bundle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FocusableTap(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? HETheme.pfAccentViolet.withValues(alpha: 0.10)
              : HETheme.pfSurfaceRaised,
          borderRadius: BorderRadius.circular(HETheme.radiusMd),
          border: Border.all(
            color: selected
                ? HETheme.pfAccentViolet.withValues(alpha: 0.55)
                : HETheme.pfBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    bundle.name,
                    style: TextStyle(
                      color: selected
                          ? HETheme.pfAccentViolet
                          : HETheme.pfTextPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${bundle.leagues.length}',
                  style: const TextStyle(
                    color: HETheme.pfTextMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (bundle.description != null &&
                bundle.description!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                bundle.description!,
                style: const TextStyle(
                  color: HETheme.pfTextSecondary,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final league in bundle.leagues)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: HETheme.pfSurfaceGlass,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: HETheme.pfBorder),
                    ),
                    child: Text(
                      league.name,
                      style: const TextStyle(
                        color: HETheme.pfTextSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── League grid ───────────────────────────────────────────────────────────────

class _LeagueGrid extends StatelessWidget {
  const _LeagueGrid({
    required this.leagues,
    required this.selected,
    required this.onToggle,
  });

  final List<AdminLeague> leagues;
  final Set<String> selected;
  final void Function(String slug) onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: leagues.map((league) {
        final isSelected = selected.contains(league.name);
        return _LeagueChip(
          league: league,
          isSelected: isSelected,
          onTap: () => onToggle(league.name),
        );
      }).toList(),
    );
  }
}

class _LeagueChip extends StatelessWidget {
  const _LeagueChip({
    required this.league,
    required this.isSelected,
    required this.onTap,
  });

  final AdminLeague league;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FocusableTap(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? HETheme.pfAccentViolet.withValues(alpha: 0.12)
              : HETheme.pfSurfaceRaised,
          borderRadius: BorderRadius.circular(HETheme.radiusMd),
          border: Border.all(
            color: isSelected
                ? HETheme.pfAccentViolet.withValues(alpha: 0.55)
                : HETheme.pfBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: isSelected ? HETheme.pfAccentViolet : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isSelected
                      ? HETheme.pfAccentViolet
                      : HETheme.pfTextSecondary,
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check_rounded,
                      size: 11,
                      color: HETheme.pfBgVoid,
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Text(
              league.name,
              style: TextStyle(
                color: isSelected
                    ? HETheme.pfAccentViolet
                    : HETheme.pfTextPrimary,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
