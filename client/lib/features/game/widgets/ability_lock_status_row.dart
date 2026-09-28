import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/models/ability_phase.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';

/// Room-progress row for the `ability_activation` phase: one chip per
/// player, showing ONLY whether they're still choosing or already locked —
/// never what they chose. Replaces the old per-row ability-type display,
/// which relied on `abilityActivations` staying empty pre-reveal (still
/// true) but showed a stale/misleading label ("PLAYED") for a state that
/// no longer applies now that activation is a hidden commit, not an
/// immediate public action.
class AbilityLockStatusRow extends StatelessWidget {
  const AbilityLockStatusRow({
    super.key,
    required this.game,
    required this.localPlayerId,
  });

  final GameState game;
  final String localPlayerId;

  @override
  Widget build(BuildContext context) {
    final resolved = game.abilityActivationResolved ?? const {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              'ROOM PROGRESS',
              style: TextStyle(
                color: HETheme.pfTextMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const Spacer(),
            Text(
              '${resolved.values.where((v) => v).length} of ${game.players.length} locked',
              style: const TextStyle(
                color: HETheme.pfTextSecondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final p in game.players)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _LockStatusChip(
              key: ValueKey('ability-lock-${p.id}'),
              isYou: p.id == localPlayerId,
              name: p.id == localPlayerId ? 'You' : p.displayName,
              isConnected: p.isConnected,
              hasResolved: resolved[p.id] ?? false,
            ),
          ),
      ],
    );
  }
}

/// A single player's status chip. Stateful only to detect a
/// disconnected→connected transition and hold a brief "Rejoined" label
/// before settling back to the plain Choosing/Locked status — purely a
/// local presentation nicety, never a source of truth (the underlying
/// status is always re-derived from `isConnected`/`hasResolved`).
class _LockStatusChip extends StatefulWidget {
  const _LockStatusChip({
    super.key,
    required this.isYou,
    required this.name,
    required this.isConnected,
    required this.hasResolved,
  });

  final bool isYou;
  final String name;
  final bool isConnected;
  final bool hasResolved;

  @override
  State<_LockStatusChip> createState() => _LockStatusChipState();
}

class _LockStatusChipState extends State<_LockStatusChip> {
  bool _showRejoined = false;
  Timer? _rejoinTimer;

  @override
  void didUpdateWidget(_LockStatusChip old) {
    super.didUpdateWidget(old);
    if (!old.isConnected && widget.isConnected) {
      _rejoinTimer?.cancel();
      setState(() => _showRejoined = true);
      _rejoinTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _showRejoined = false);
      });
    }
  }

  @override
  void dispose() {
    _rejoinTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon, String label) = _showRejoined
        ? (HETheme.pfAccentViolet, Icons.wifi_rounded, 'Rejoined')
        : switch (computeAbilityLockStatus(
            isConnected: widget.isConnected,
            hasResolved: widget.hasResolved,
          )) {
            AbilityLockStatus.locked => (
              HETheme.pfAccentViolet,
              Icons.lock_rounded,
              'Locked',
            ),
            AbilityLockStatus.choosing => (
              HETheme.pfTextSecondary,
              Icons.hourglass_top_rounded,
              'Choosing…',
            ),
            AbilityLockStatus.disconnected => (
              // Unavailable due to connection failure — coral/danger, not a
              // routine wait state.
              HETheme.pfDanger,
              Icons.wifi_off_rounded,
              'Disconnected',
            ),
          };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          // A face-down slot glyph — deliberately generic (no ability icon
          // at all) so this row can never leak what's underneath.
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: HETheme.pfSurfaceRaised,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: HETheme.pfBorder),
            ),
            child: const Icon(
              Icons.help_outline_rounded,
              color: HETheme.pfTextMuted,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.name,
              style: TextStyle(
                color: widget.isYou ? HETheme.pfAccentViolet : HETheme.pfTextPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Row(
              key: ValueKey(label),
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 15),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
