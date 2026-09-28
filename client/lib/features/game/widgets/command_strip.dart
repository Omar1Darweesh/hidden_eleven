import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/app/theme.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/widgets/turn_timer_widget.dart';
import 'package:hidden_eleven/shared/audio/audio_service.dart';
import 'package:hidden_eleven/shared/widgets/he_card.dart';

/// The persistent turn/phase header — renamed from `DraftStatusBar` to match
/// the "Matchday Intelligence" dossier's vocabulary and retinted to its
/// token set, but functionally the SAME widget: round progress, current
/// phase, whose turn it is, and the turn timer, in one block. Cyan marks
/// the actionable "your turn" state; gold marks the final-round moment —
/// consistent with the dossier's rule that gold is reserved for
/// hidden/reveal/premium moments, and a final round is exactly that kind of
/// moment.
///
/// Post-draft Track B phases (`bench_selection`, `ability_activation`,
/// `lineup_edit`) adapt the bar: phase label, instruction, and full progress
/// (draft complete). Those phases are **parallel** for every player — not
/// turn-based — so the bar always presents them as active local work rather
/// than "Waiting for {stale draft activePlayer}".
class CommandStrip extends StatelessWidget {
  const CommandStrip({
    super.key,
    required this.currentRound,
    required this.totalRounds,
    required this.turnPhase,
    required this.currentPlayer,
    required this.isLocalPlayerTurn,
    this.gameStatus,
    this.timerStartedAt,
    this.timerDurationSeconds,
    this.compact = false,
    this.onSettingsTap,
  });

  /// Narrow (mobile) layout: tighten padding and vertical spacing so the bar
  /// takes less height, leaving more room for the pitch below it. Kept under
  /// the dossier's 56px mobile Command Strip budget (§5.P Rule 2) at this
  /// setting.
  final bool compact;

  final int currentRound;
  final int totalRounds;
  final String turnPhase;
  final GamePlayer? currentPlayer;
  final bool isLocalPlayerTurn;

  /// Overall game status (e.g. 'drafting', 'bench_selection', 'lineup_edit',
  /// 'ability_activation'). Used to show phase-appropriate labels when the
  /// turn-level [turnPhase] string doesn't map to a user-facing label.
  final String? gameStatus;

  final DateTime? timerStartedAt;
  final int? timerDurationSeconds;

  /// Optional settings entry point rendered in the strip itself — the
  /// dossier requires Settings/Sound reachable in under two taps from
  /// anywhere during live gameplay, never buried behind a menu. Null hides
  /// the icon entirely, so existing call sites compile unchanged until this
  /// is wired up.
  final VoidCallback? onSettingsTap;

  bool get _isBenchSelection => gameStatus == 'bench_selection';
  bool get _isLineupEdit => gameStatus == 'lineup_edit';
  bool get _isAbilityActivation => gameStatus == 'ability_activation';

  /// Track B post-draft phases — shared chrome (100% progress) applies to all;
  /// label / instruction / icon differ per phase.
  bool get _isPostDraft =>
      _isBenchSelection || _isLineupEdit || _isAbilityActivation;

  /// Post-draft work is simultaneous for every seat. Ignore the draft
  /// turn's `activePlayerId` so the bar doesn't show a stale "Waiting for".
  bool get _showAsActive => isLocalPlayerTurn || _isPostDraft;

  String get _phaseLabel => _isBenchSelection
      ? 'BENCH SELECT'
      : _isAbilityActivation
      ? 'ABILITY'
      : _isLineupEdit
      ? 'FINAL LINEUP'
      : switch (turnPhase) {
          'selecting_position' => 'Pick Slot',
          'selecting_card' => 'Pick Card',
          'first_player_order' => 'Order Deck',
          'hidden_pick' => 'Sealed Dossier',
          'hidden_pick_reveal' => 'Reveal',
          _ => turnPhase,
        };

  String get _eyebrow => _isBenchSelection
      ? 'BENCH SELECTION'
      : _isAbilityActivation
      ? 'TACTICAL PHASE'
      : _isLineupEdit
      ? 'FINAL LINEUP'
      : 'ROUND $currentRound/$totalRounds';

  String get _activeInstruction => _isBenchSelection
      ? 'Pick & lock your bench'
      : _isAbilityActivation
      ? 'Use your tactical card'
      : _isLineupEdit
      ? 'Rearrange & submit lineup'
      : switch (turnPhase) {
          'selecting_position' => 'Tap a position on the pitch',
          'selecting_card' => 'Choose a player',
          _ => 'Pick your player',
        };

  IconData get _activeIcon => _isAbilityActivation
      ? Icons.auto_awesome_rounded
      : _isBenchSelection
      ? Icons.event_seat_rounded
      : _isLineupEdit
      ? Icons.swap_horiz_rounded
      : Icons.sports_soccer_rounded;

  bool get _isFinalRound => totalRounds > 0 && currentRound >= totalRounds;

  @override
  Widget build(BuildContext context) {
    final progress = totalRounds > 0 ? currentRound / totalRounds : 0.0;
    final name = currentPlayer?.displayName ?? '—';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: EdgeInsets.all(compact ? HESpacing.md : HESpacing.lg),
      decoration: BoxDecoration(
        color: _showAsActive
            ? HETheme.pfAccentViolet.withValues(alpha: 0.08)
            : HETheme.pfSurfaceRaised,
        borderRadius: BorderRadius.circular(HERadius.lg),
        border: Border.all(
          color: _showAsActive
              ? HETheme.pfAccentViolet.withValues(alpha: 0.55)
              : HETheme.pfBorder,
          width: _showAsActive ? 1.5 : 1,
        ),
        boxShadow: _showAsActive
            ? [
                BoxShadow(
                  color: HETheme.pfAccentViolet.withValues(alpha: 0.14),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (_isPostDraft)
                Text(_eyebrow, style: HETheme.displayLabel(size: 10))
              else ...[
                Text(_eyebrow, style: HETheme.displayLabel(size: 10)),
                if (_isFinalRound) ...[
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.emoji_events_rounded,
                    color: HETheme.pfGold,
                    size: 12,
                  ),
                ],
              ],
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: HESpacing.sm,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: HETheme.pfAccentViolet.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(HERadius.xs),
                  border: Border.all(
                    color: HETheme.pfAccentViolet.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  _phaseLabel.toUpperCase(),
                  style: HETheme.mono(
                    size: 10,
                    weight: FontWeight.w800,
                    color: HETheme.pfAccentViolet,
                  ).copyWith(letterSpacing: 1.0),
                ),
              ),
              if (onSettingsTap != null) ...[
                const SizedBox(width: HESpacing.sm),
                // 44x44 minimum touch target (dossier §9) even though the
                // visible icon is smaller — InkResponse's tap area, not the
                // icon glyph, is what must clear the minimum.
                SizedBox(
                  width: 44,
                  height: 32,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    tooltip: 'Settings',
                    icon: const Icon(
                      Icons.settings_outlined,
                      color: HETheme.pfTextSecondary,
                    ),
                    onPressed: onSettingsTap,
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: compact ? 6 : 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(HERadius.xs.toDouble()),
            child: LinearProgressIndicator(
              value: _isPostDraft ? 1.0 : progress.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: HETheme.pfBorder,
              color: _isPostDraft
                  ? HETheme.pfAccentViolet.withValues(alpha: 0.5)
                  : _isFinalRound
                  ? HETheme.pfGold
                  : HETheme.pfAccentViolet,
            ),
          ),
          SizedBox(height: compact ? 9 : 14),

          Row(
            children: [
              _showAsActive
                  ? Container(
                      width: compact ? 34 : 40,
                      height: compact ? 34 : 40,
                      decoration: BoxDecoration(
                        color: HETheme.pfAccentViolet,
                        borderRadius: BorderRadius.circular(HERadius.sm),
                      ),
                      child: Center(
                        child: Icon(
                          _activeIcon,
                          color: HETheme.pfBgVoid,
                          size: compact ? 18 : 20,
                        ),
                      ),
                    )
                  : HEAvatar(name: name, size: compact ? 34 : 40),
              const SizedBox(width: HESpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _showAsActive ? 'Your turn' : 'Waiting for',
                      style: HETheme.body(
                        size: 11,
                        color: HETheme.pfTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _showAsActive ? _activeInstruction : name,
                      style: HETheme.body(
                        size: 15,
                        weight: FontWeight.w700,
                        color: _showAsActive
                            ? HETheme.pfAccentViolet
                            : HETheme.pfTextPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (timerStartedAt != null && timerDurationSeconds != null) ...[
                const SizedBox(width: HESpacing.sm),
                // A Consumer here (rather than making the whole strip a
                // ConsumerWidget) keeps the audio trigger local to the one
                // piece of UI that needs it.
                Consumer(
                  builder: (context, ref, _) => TurnTimerWidget(
                    startedAt: timerStartedAt!,
                    durationSeconds: timerDurationSeconds!,
                    muted: !_showAsActive,
                    onUrgent: () =>
                        ref.read(audioServiceProvider).playSfx(Sfx.timerTicker),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
