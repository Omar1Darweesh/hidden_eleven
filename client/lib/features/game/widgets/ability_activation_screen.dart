import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/models/ability.dart';
import 'package:hidden_eleven/features/game/models/ability_phase.dart';
import 'package:hidden_eleven/features/game/models/chemistry_vars.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/services/chemistry_evaluator.dart';
import 'package:hidden_eleven/features/game/widgets/ability_lock_status_row.dart';
import 'package:hidden_eleven/features/game/widgets/compact_bench_summary.dart';
import 'package:hidden_eleven/features/game/widgets/panel_header.dart';
import 'package:hidden_eleven/features/lobby/room_provider.dart';
import 'package:hidden_eleven/shared/audio/audio_service.dart';
import 'package:hidden_eleven/shared/widgets/he_button.dart';

/// Side-panel UI for the `ability_activation` phase (rendered next to the
/// pitch, like the subs panel) so the player can see their starting 11 and
/// switch to opponents' squads while choosing a target.
///
/// Ability choices are HIDDEN, not broadcast: every player commits silently
/// (`ability_select` → `ability_locked_wait`), and only once everyone has
/// locked in does the server reveal what happened, all at once, in a
/// dedicated cinematic sequence (`AbilityRevealOverlay`, mounted by
/// `GameScreen` above this panel). This panel itself never shows what a
/// rival chose — only whether they're still choosing or already locked
/// (`AbilityLockStatusRow`).
class AbilityActivationPanel extends ConsumerStatefulWidget {
  const AbilityActivationPanel({
    super.key,
    required this.game,
    required this.localPlayerId,
  });

  final GameState game;
  final String localPlayerId;

  @override
  ConsumerState<AbilityActivationPanel> createState() =>
      _AbilityActivationPanelState();
}

/// Every non-GK base position a Coach card can add (mirrors the server's
/// COACHABLE_POSITIONS in ability.interface.ts). GK is excluded on both sides.
const List<String> _kCoachablePositions = [
  'LB',
  'CB',
  'RB',
  'CDM',
  'CM',
  'CAM',
  'LM',
  'RM',
  'LW',
  'RW',
  'CF',
  'ST',
];

class _AbilityActivationPanelState
    extends ConsumerState<AbilityActivationPanel> {
  int? _ownSlot;
  String? _targetUser;
  int? _targetSlot;

  /// Rival bench group for red/sub (`att`/`mid`/`def`). XOR with `_targetSlot`.
  String? _targetBenchGroup;

  /// Own bench group for coach. XOR with `_ownSlot`.
  String? _ownBenchGroup;

  /// Coach: the new position chosen for the selected own player.
  String? _coachedPosition;

  GameState get game => widget.game;

  List<PitchSlot> _filled(String? userId) =>
      game.pitches[userId]?.slots.where((s) => s.isFilled).toList() ?? const [];

  /// Bench cards available during ability_activation (att/mid/def only).
  List<(String group, SubSlot slot)> _benchFilled(String? userId) {
    final subs = game.subsPhase?.userSubs[userId];
    if (subs == null) return const [];
    final out = <(String, SubSlot)>[];
    for (final g in const ['att', 'mid', 'def']) {
      final slot = switch (g) {
        'att' => subs.att,
        'mid' => subs.mid,
        'def' => subs.def,
        _ => null,
      };
      if (slot?.benchCard != null || slot?.chosenPlayerId != null) {
        // Prefer benchCard (full identity); fall back when only chosen* exists.
        if (slot!.benchCard != null || slot.chosenPlayerId != null) {
          out.add((g, slot));
        }
      }
    }
    return out;
  }

  String _benchName(SubSlot slot) =>
      slot.benchCard?.playerName ??
      slot.chosenPlayerName ??
      slot.benchedPlayerName ??
      '?';

  String? _benchBasePos(SubSlot slot) =>
      slot.benchCard?.basePositionType ??
      slot.benchedPlayerPosition ??
      slot.chosenPlayerPosition;

  Set<String> _benchNaturalPositions(SubSlot slot) {
    final card = slot.benchCard;
    if (card != null) {
      if (card.naturalPositions.isNotEmpty)
        return card.naturalPositions.toSet();
      return {card.basePositionType, ...card.altPositions};
    }
    final base = slot.benchedPlayerPosition ?? slot.chosenPlayerPosition;
    final alts = slot.benchedNaturalPositions;
    if (base == null) return {};
    return {base, ...alts};
  }

  String _nameOf(String? id) =>
      game.players.where((p) => p.id == id).firstOrNull?.displayName ?? '—';

  bool get _canUse {
    final type = game.myAbility?.type;
    return switch (type) {
      AbilityType.captain => _ownSlot != null,
      AbilityType.yellow => _targetUser != null,
      AbilityType.red =>
        _targetUser != null &&
            ((_targetSlot != null) ^ (_targetBenchGroup != null)),
      AbilityType.extraBench => true,
      AbilityType.sub =>
        _ownSlot != null &&
            _targetUser != null &&
            ((_targetSlot != null) ^ (_targetBenchGroup != null)),
      AbilityType.coach =>
        ((_ownSlot != null) ^ (_ownBenchGroup != null)) &&
            _coachedPosition != null,
      // Self-targeting — nothing to choose.
      AbilityType.protect => true,
      // Same shape as yellow: pick which rival to disable.
      AbilityType.freeze => _targetUser != null,
      null => false,
    };
  }

  void _use() {
    final type = game.myAbility?.type;
    final notifier = ref.read(roomProvider.notifier);
    if (type != null) {
      ref.read(audioServiceProvider).playSfx(Sfx.abilityUse);
    }
    switch (type) {
      case AbilityType.captain:
        notifier.activateAbility(ownSlotIndex: _ownSlot);
      case AbilityType.yellow:
        notifier.activateAbility(targetUserId: _targetUser);
      case AbilityType.red:
        notifier.activateAbility(
          targetUserId: _targetUser,
          targetSlotIndex: _targetSlot,
          targetBenchGroup: _targetBenchGroup,
        );
      case AbilityType.extraBench:
        notifier.activateAbility();
      case AbilityType.sub:
        notifier.activateAbility(
          ownSlotIndex: _ownSlot,
          targetUserId: _targetUser,
          targetSlotIndex: _targetSlot,
          targetBenchGroup: _targetBenchGroup,
        );
      case AbilityType.coach:
        notifier.activateAbility(
          ownSlotIndex: _ownSlot,
          ownBenchGroup: _ownBenchGroup,
          coachedPosition: _coachedPosition,
        );
      case AbilityType.protect:
        notifier.activateAbility();
      case AbilityType.freeze:
        notifier.activateAbility(targetUserId: _targetUser);
      case null:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final myAbility = game.myAbility;
    final phase = computeAbilitySelectPhase(game);
    final mySubs = game.subsPhase?.userSubs[widget.localPlayerId];
    final selecting = phase == AbilitySelectPhase.select && myAbility != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelHeader(
          icon: Icons.auto_awesome_rounded,
          eyebrow: 'HIDDEN ABILITY',
          title: selecting
              ? 'Bench is locked. Use or discard your card — rivals '
                    'cannot see your choice until everyone locks.'
              : 'Waiting for the room to finish locking abilities.',
          emphasized: selecting,
        ),
        const SizedBox(height: 12),
        // Continuity: keep the locked bench visible while the sidebar is
        // no longer SubsPanel — pitch stays central; this is the compact
        // bench representation so picks don't feel like they vanished.
        CompactBenchSummary(
          subs: mySubs,
          lineup:
              game.pitches[widget.localPlayerId]?.slots
                  .where((s) => s.isFilled)
                  .map(LineupCard.fromSlot)
                  .toList() ??
              const [],
        ),
        const SizedBox(height: 14),

        if (selecting)
          _activationCard(myAbility.type)
        else
          _waitingCard(myAbility, phase),

        const SizedBox(height: 16),
        AbilityLockStatusRow(game: game, localPlayerId: widget.localPlayerId),
      ],
    );
  }

  Widget _waitingCard(PlayerAbility? ability, AbilitySelectPhase phase) {
    if (phase == AbilitySelectPhase.revealed) {
      // The reveal overlay owns the screen now — this panel has nothing
      // useful left to show underneath it.
      return const SizedBox.shrink();
    }
    final (String headline, String detail, IconData icon) = ability == null
        ? (
            'No card to play',
            'Waiting for other players to lock their abilities…',
            Icons.block_rounded,
          )
        : ability.status == 'used'
        ? (
            'Ability locked',
            ability.pendingSummary != null
                ? '${ability.pendingSummary}. Hidden until everyone locks — then the reveal.'
                : 'Your choice is hidden. Waiting for other players to lock…',
            Icons.lock_rounded,
          )
        : (
            'Card discarded',
            'Waiting for other players to lock their abilities…',
            Icons.hourglass_top_rounded,
          );
    return Container(
      key: const ValueKey('ability-locked-wait'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: HETheme.pfAccentViolet.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HETheme.pfAccentViolet.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: HETheme.pfAccentViolet, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: const TextStyle(
                    color: HETheme.pfAccentViolet,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: const TextStyle(
                    color: HETheme.pfTextSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                const Row(
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: HETheme.pfTextMuted,
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Reveal starts when the room is fully locked.',
                        style: TextStyle(
                          color: HETheme.pfTextMuted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _activationCard(AbilityType type) {
    final meta = AbilityMeta.of(type);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HETheme.pfSurfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: meta.color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: meta.color.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                  border: Border.all(color: meta.color.withValues(alpha: 0.6)),
                ),
                child: Icon(meta.icon, color: meta.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meta.name,
                      style: TextStyle(
                        color: meta.color,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      _instruction(type),
                      style: const TextStyle(
                        color: HETheme.pfTextSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ..._targetPicker(type),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: HEButton(
                  variant: HEButtonVariant.secondary,
                  small: true,
                  label: 'Discard',
                  onPressed: () =>
                      ref.read(roomProvider.notifier).discardAbility(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: HEButton(
                  small: true,
                  label: 'Use Card',
                  color: meta.color,
                  onPressed: _canUse ? _use : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _instruction(AbilityType type) => ChemistryVars.resolve(switch (type) {
    AbilityType.captain => 'Pick one of YOUR starting-XI players to captain.',
    AbilityType.yellow => 'Pick a rival to dock {yellowPenalty} points.',
    AbilityType.red =>
      'Pick a rival, then a starting-XI or bench player to disable.',
    AbilityType.extraBench => 'Adds an any-position bench player.',
    AbilityType.sub =>
      'Swap your starter with a rival’s starter or bench player (same position).',
    AbilityType.coach =>
      'Pick one of YOUR starters or bench players, then add a new position.',
    AbilityType.protect =>
      'Shields you from every hostile ability this round — unless someone '
          'freezes you first.',
    AbilityType.freeze => 'Pick a rival to disable their ability entirely.',
  });

  List<Widget> _targetPicker(AbilityType type) {
    switch (type) {
      case AbilityType.coach:
        final coachablePitch = _filled(
          widget.localPlayerId,
        ).where((s) => s.basePositionType != 'GK').toList();
        final coachableBench = _benchFilled(
          widget.localPlayerId,
        ).where((e) => _benchBasePos(e.$2) != 'GK').toList();

        Set<String> owned = const {};
        if (_ownSlot != null) {
          final slot = coachablePitch
              .where((s) => s.index == _ownSlot)
              .firstOrNull;
          owned = slot?.effectiveNaturalPositions.toSet() ?? const {};
        } else if (_ownBenchGroup != null) {
          final entry = coachableBench
              .where((e) => e.$1 == _ownBenchGroup)
              .firstOrNull;
          if (entry != null) owned = _benchNaturalPositions(entry.$2);
        }
        final options = _kCoachablePositions
            .where((p) => !owned.contains(p))
            .toList();
        final hasSelection = _ownSlot != null || _ownBenchGroup != null;

        return [
          _SectionLabel('Your player to coach'),
          _PlayerGrid(
            slots: coachablePitch,
            selectedIndex: _ownSlot,
            onTap: (i) => setState(() {
              _ownSlot = i;
              _ownBenchGroup = null;
              _coachedPosition = null;
            }),
          ),
          if (coachableBench.isNotEmpty) ...[
            const SizedBox(height: 10),
            _SectionLabel('Your bench'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (group, slot) in coachableBench)
                  _OptionChip(
                    label: _benchName(slot),
                    sub:
                        '${_benchBasePos(slot) ?? group.toUpperCase()} · bench',
                    selected: _ownBenchGroup == group,
                    onTap: () => setState(() {
                      _ownBenchGroup = group;
                      _ownSlot = null;
                      _coachedPosition = null;
                    }),
                  ),
              ],
            ),
          ],
          if (hasSelection) ...[
            const SizedBox(height: 12),
            _SectionLabel('New position to add'),
            if (options.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'This player already has every position.',
                  style: TextStyle(color: HETheme.pfTextMuted, fontSize: 12),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final pos in options)
                    _OptionChip(
                      label: pos,
                      sub: null,
                      selected: _coachedPosition == pos,
                      onTap: () => setState(() => _coachedPosition = pos),
                    ),
                ],
              ),
          ],
        ];
      case AbilityType.captain:
        return [
          _SectionLabel('Your starting XI'),
          _PlayerGrid(
            slots: _filled(widget.localPlayerId),
            selectedIndex: _ownSlot,
            onTap: (i) => setState(() => _ownSlot = i),
          ),
        ];
      case AbilityType.yellow:
        return [
          _SectionLabel('Rivals'),
          _UserGrid(
            users: game.players
                .where((p) => p.id != widget.localPlayerId)
                .toList(),
            selectedId: _targetUser,
            onTap: (id) => setState(() => _targetUser = id),
          ),
        ];
      case AbilityType.red:
        final rivalBench = _targetUser == null
            ? const <(String, SubSlot)>[]
            : _benchFilled(_targetUser);
        return [
          _SectionLabel('Rival'),
          _UserGrid(
            users: game.players
                .where((p) => p.id != widget.localPlayerId)
                .toList(),
            selectedId: _targetUser,
            onTap: (id) => setState(() {
              _targetUser = id;
              _targetSlot = null;
              _targetBenchGroup = null;
            }),
          ),
          if (_targetUser != null) ...[
            const SizedBox(height: 12),
            _SectionLabel('${_nameOf(_targetUser)}’s starting XI'),
            _PlayerGrid(
              slots: _filled(_targetUser),
              selectedIndex: _targetSlot,
              onTap: (i) => setState(() {
                _targetSlot = i;
                _targetBenchGroup = null;
              }),
            ),
            if (rivalBench.isNotEmpty) ...[
              const SizedBox(height: 10),
              _SectionLabel('${_nameOf(_targetUser)}’s bench'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (group, slot) in rivalBench)
                    _OptionChip(
                      label: _benchName(slot),
                      sub:
                          '${_benchBasePos(slot) ?? group.toUpperCase()} · bench',
                      selected: _targetBenchGroup == group,
                      onTap: () => setState(() {
                        _targetBenchGroup = group;
                        _targetSlot = null;
                      }),
                    ),
                ],
              ),
            ],
          ],
        ];
      case AbilityType.extraBench:
        return const [];
      case AbilityType.protect:
        // Self-targeting: nothing to pick.
        return const [];
      case AbilityType.freeze:
        return [
          _SectionLabel('Rival to disable'),
          _UserGrid(
            users: game.players
                .where((p) => p.id != widget.localPlayerId)
                .toList(),
            selectedId: _targetUser,
            onTap: (id) => setState(() => _targetUser = id),
          ),
        ];
      case AbilityType.sub:
        final ownPos = _ownSlot == null
            ? null
            : _filled(
                widget.localPlayerId,
              ).where((s) => s.index == _ownSlot).firstOrNull?.basePositionType;
        final rivalPitchOptions = <(String, PitchSlot)>[];
        final rivalBenchOptions = <(String, String, SubSlot)>[];
        if (ownPos != null) {
          for (final p in game.players) {
            if (p.id == widget.localPlayerId) continue;
            for (final s in _filled(p.id)) {
              if (s.basePositionType == ownPos) {
                rivalPitchOptions.add((p.id, s));
              }
            }
            for (final (group, slot) in _benchFilled(p.id)) {
              if (_benchBasePos(slot) == ownPos) {
                rivalBenchOptions.add((p.id, group, slot));
              }
            }
          }
        }
        final noRivals = rivalPitchOptions.isEmpty && rivalBenchOptions.isEmpty;
        return [
          _SectionLabel('Your starter'),
          _PlayerGrid(
            slots: _filled(widget.localPlayerId),
            selectedIndex: _ownSlot,
            onTap: (i) => setState(() {
              _ownSlot = i;
              _targetUser = null;
              _targetSlot = null;
              _targetBenchGroup = null;
            }),
          ),
          if (ownPos != null) ...[
            const SizedBox(height: 12),
            _SectionLabel('Rival ${ownPos}s to swap with'),
            if (noRivals)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No rival player in that position.',
                  style: TextStyle(color: HETheme.pfTextMuted, fontSize: 12),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (uid, s) in rivalPitchOptions)
                    _OptionChip(
                      label: '${s.cardPlayerName ?? '?'} · ${_nameOf(uid)}',
                      sub: '${s.basePositionType} · ${s.cardRating ?? ''}',
                      selected:
                          _targetUser == uid &&
                          _targetSlot == s.index &&
                          _targetBenchGroup == null,
                      onTap: () => setState(() {
                        _targetUser = uid;
                        _targetSlot = s.index;
                        _targetBenchGroup = null;
                      }),
                    ),
                  for (final (uid, group, slot) in rivalBenchOptions)
                    _OptionChip(
                      label: '${_benchName(slot)} · ${_nameOf(uid)}',
                      sub: '${_benchBasePos(slot) ?? group} · bench',
                      selected:
                          _targetUser == uid &&
                          _targetBenchGroup == group &&
                          _targetSlot == null,
                      onTap: () => setState(() {
                        _targetUser = uid;
                        _targetBenchGroup = group;
                        _targetSlot = null;
                      }),
                    ),
                ],
              ),
          ],
        ];
    }
  }
}

// ── Pickers ───────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: HETheme.pfTextMuted,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1,
      ),
    ),
  );
}

class _PlayerGrid extends StatelessWidget {
  const _PlayerGrid({
    required this.slots,
    required this.selectedIndex,
    required this.onTap,
  });
  final List<PitchSlot> slots;
  final int? selectedIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in slots)
          _OptionChip(
            label: s.cardPlayerName ?? '?',
            sub: '${s.label} · ${s.cardRating ?? ''}',
            selected: selectedIndex == s.index,
            onTap: () => onTap(s.index),
          ),
      ],
    );
  }
}

class _UserGrid extends StatelessWidget {
  const _UserGrid({
    required this.users,
    required this.selectedId,
    required this.onTap,
  });
  final List<GamePlayer> users;
  final String? selectedId;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final u in users)
          _OptionChip(
            label: u.displayName,
            sub: null,
            selected: selectedId == u.id,
            onTap: () => onTap(u.id),
          ),
      ],
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.sub,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final String? sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? HETheme.pfAccentViolet.withValues(alpha: 0.18)
              : HETheme.pfSurfaceRaised,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? HETheme.pfAccentViolet : HETheme.pfBorder,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? HETheme.pfAccentViolet : HETheme.pfTextPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (sub != null)
              Text(
                sub!,
                style: const TextStyle(
                  color: HETheme.pfTextMuted,
                  fontSize: 10.5,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
