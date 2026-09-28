import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hidden_eleven/app/he_motion.dart';
import 'package:hidden_eleven/app/he_shape.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/widgets/turn_timer_widget.dart';
import 'package:hidden_eleven/shared/audio/audio_service.dart';
import 'package:hidden_eleven/shared/widgets/he_card.dart';

/// The Mission Card — "what am I supposed to do right now", as one friendly
/// floating object rather than a thin outlined technical strip.
///
/// This is `CommandStrip` re-dressed, not replaced: **the public API is
/// identical**, and every piece of phase logic (the post-draft parallel-phase
/// handling, the label/eyebrow/instruction/icon switches, the final-round
/// gold treatment) is carried over verbatim. Only the presentation changed.
///
/// Two structural changes worth knowing about:
///
///  * **The round progress bar is gone.** It merged into the timer as a
///    concentric outer ring — see [TimerRing.roundProgress]. That removes a
///    horizontal bar, reclaims vertical space, and puts both readouts in one
///    place the eye already goes.
///  * **Opponent turns get a breathing indicator**, never a spinner and
///    never a static frozen panel. A player must always be able to tell the
///    app is alive while they wait.
class MissionCard extends StatelessWidget {
  const MissionCard({
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

  /// Narrow (mobile) layout: tighter padding and spacing so the card takes
  /// less height, leaving more room for the pitch below it.
  final bool compact;

  final int currentRound;
  final int totalRounds;
  final String turnPhase;
  final GamePlayer? currentPlayer;
  final bool isLocalPlayerTurn;

  /// Overall game status (e.g. 'drafting', 'bench_selection', 'lineup_edit',
  /// 'ability_activation').
  final String? gameStatus;

  final DateTime? timerStartedAt;
  final int? timerDurationSeconds;

  /// Settings entry point. Settings/Sound must stay reachable in under two
  /// taps from anywhere during live gameplay. Null hides the icon.
  final VoidCallback? onSettingsTap;

  // ── Phase logic — carried over from CommandStrip unchanged ──────────────
  bool get _isBenchSelection => gameStatus == 'bench_selection';
  bool get _isLineupEdit => gameStatus == 'lineup_edit';
  bool get _isAbilityActivation => gameStatus == 'ability_activation';

  bool get _isPostDraft =>
      _isBenchSelection || _isLineupEdit || _isAbilityActivation;

  /// Post-draft work is simultaneous for every seat. Ignore the draft turn's
  /// `activePlayerId` so the card doesn't show a stale "Waiting for".
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
    final progress = _isPostDraft
        ? 1.0
        : (totalRounds > 0 ? currentRound / totalRounds : 0.0).clamp(0.0, 1.0);
    final name = currentPlayer?.displayName ?? '—';
    final hasTimer = timerStartedAt != null && timerDurationSeconds != null;

    return AnimatedContainer(
      duration: HEMotion.wake,
      curve: HEMotion.easeOut,
      padding: EdgeInsets.all(compact ? 14 : 18),
      // e3 when it's your move, e1 when you're waiting. That single swap is
      // what makes "is it my turn" readable from across the room.
      decoration: _showAsActive
          ? HEElevation.e3()
          : HEElevation.e1(radius: HEShape.signature),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Flexible: "BENCH SELECTION" and other longer eyebrow labels
              // were themselves wide enough to overflow before the phase
              // pill even got a chance to compete for space.
              Flexible(
                child: _EyebrowPill(
                  text: _eyebrow,
                  highlight: _isFinalRound && !_isPostDraft,
                ),
              ),
              if (_isFinalRound && !_isPostDraft) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.emoji_events_rounded,
                  color: HETheme.pfGold,
                  size: 13,
                ),
              ],
              const Spacer(),
              // Flexible, not a bare child: at narrow (compact) widths the
              // eyebrow pill + trophy icon + this pill + settings button
              // together exceeded the available 262px (the exact reported
              // "2.8 pixels" overflow) whenever the phase label was one of
              // the longer ones. The pill itself now truncates instead.
              Flexible(
                child: _PhasePill(label: _phaseLabel, active: _showAsActive),
              ),
              if (onSettingsTap != null) ...[
                const SizedBox(width: 6),
                _SettingsButton(onTap: onSettingsTap!),
              ],
            ],
          ),
          SizedBox(height: compact ? 12 : 16),
          Row(
            children: [
              if (_showAsActive)
                _IconCapsule(icon: _activeIcon, compact: compact)
              else
                HEAvatar(name: name, size: compact ? 36 : 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          _showAsActive ? 'Your turn' : 'Waiting for',
                          style: HETheme.body(
                            size: 11,
                            color: HETheme.pfTextMuted,
                          ),
                        ),
                        if (!_showAsActive) ...[
                          const SizedBox(width: 7),
                          const _BreathingDots(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _showAsActive ? _activeInstruction : name,
                      style: HETheme.body(
                        size: compact ? 15 : 17,
                        weight: FontWeight.w700,
                        color: _showAsActive
                            ? HETheme.pfTextPrimary
                            : HETheme.pfTextSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (hasTimer) ...[
                const SizedBox(width: 10),
                // A Consumer here (rather than making the whole card a
                // ConsumerWidget) keeps the audio trigger local to the one
                // piece of UI that needs it.
                Consumer(
                  builder: (context, ref, _) => TurnTimerWidget(
                    startedAt: timerStartedAt!,
                    durationSeconds: timerDurationSeconds!,
                    muted: !_showAsActive,
                    // The round dial only makes sense on the active turn —
                    // a muted observer timer stays the small bare ring.
                    roundProgress: _showAsActive ? progress : null,
                    onUrgent: () =>
                        ref.read(audioServiceProvider).playSfx(Sfx.timerTicker),
                    onCritical: () => ref
                        .read(audioServiceProvider)
                        .playSfx(Sfx.timerWarning),
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

// ── Parts ────────────────────────────────────────────────────────────────────

class _EyebrowPill extends StatelessWidget {
  const _EyebrowPill({required this.text, required this.highlight});

  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = highlight ? HETheme.pfGold : HETheme.pfLavenderText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: HEShape.pill,
        border: Border.all(color: color.withValues(alpha: 0.38)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: HETheme.mono(
          size: 9.5,
          weight: FontWeight.w700,
          color: color,
        ).copyWith(letterSpacing: 1.3),
      ),
    );
  }
}

class _PhasePill extends StatelessWidget {
  const _PhasePill({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? HETheme.pfAccentMagenta : HETheme.pfSecondaryViolet;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: HEShape.pill,
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: HETheme.mono(
          size: 9.5,
          weight: FontWeight.w800,
          color: active ? HETheme.pfAccentMagenta : HETheme.pfLavenderText,
        ).copyWith(letterSpacing: 1.0),
      ),
    );
  }
}

/// The rounded capsule holding the phase icon on an active turn. Replaces
/// the old hard-cornered filled square.
class _IconCapsule extends StatelessWidget {
  const _IconCapsule({required this.icon, required this.compact});

  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 36.0 : 42.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [HETheme.pfAccentVioletGlow, HETheme.pfAccentViolet],
        ),
        borderRadius: BorderRadius.circular(HEShape.rMd),
        boxShadow: [
          BoxShadow(
            color: HETheme.pfAccentViolet.withValues(alpha: 0.45),
            blurRadius: 16,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Icon(icon, color: HETheme.pfBgVoid, size: compact ? 19 : 22),
    );
  }
}

class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 44px minimum tap target even though the glyph is 18px.
    return SizedBox(
      width: 44,
      height: 32,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 18,
        tooltip: 'Settings',
        icon: const Icon(Icons.settings_outlined, color: HETheme.pfTextMuted),
        onPressed: onTap,
      ),
    );
  }
}

/// Three softly breathing dots for the opponent-turn state.
///
/// Deliberately not a `CircularProgressIndicator`: a spinner reads as "the
/// app is loading / possibly stuck", whereas this reads as "someone else is
/// thinking". Under reduced motion no controller is constructed and the dots
/// render statically at mid-opacity.
class _BreathingDots extends StatefulWidget {
  const _BreathingDots();

  @override
  State<_BreathingDots> createState() => _BreathingDotsState();
}

class _BreathingDotsState extends State<_BreathingDots>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;
  bool _checked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    if (!HEMotion.reduced(context)) {
      _c = AnimationController(vsync: this, duration: HEMotion.waiting)
        ..repeat();
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  Widget _dots(double t) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Opacity(
            // Staggered phase per dot, so the group reads as a wave.
            opacity: 0.30 + 0.55 * _ramp(t, i * 0.22),
            child: Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: HETheme.pfLavenderText,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// A 0..1 triangle wave with a phase offset — cheaper than a sine and
  /// visually indistinguishable at this size.
  static double _ramp(double t, double phase) {
    final v = (t + phase) % 1.0;
    return v < 0.5 ? v * 2 : (1 - v) * 2;
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return _dots(0.5);
    return AnimatedBuilder(animation: c, builder: (_, _) => _dots(c.value));
  }
}
