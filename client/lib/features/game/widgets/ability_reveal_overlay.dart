import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/models/ability.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/widgets/ability_reveal_card.dart';
import 'package:hidden_eleven/features/game/widgets/ability_resolution_banner.dart';
import 'package:hidden_eleven/features/game/widgets/ability_resolved_summary.dart';

/// Full-screen dramatic reveal sequence, played once per ability-activation
/// phase. Entirely self-paced client-side — the server already handed us
/// the complete, authoritative, deterministically-ordered `activations`
/// list in one atomic reveal (see backend `_revealAbilityActivations`), so
/// there's nothing left to fetch or guess: this widget's only job is to
/// PACE the display of data it already fully has, the same way
/// `FormationRevealOverlay` paces a formation it already knows.
///
/// Deliberately NOT gated by `game.status` — the caller (GameScreen) keeps
/// this mounted via local state that outlives the server's brief
/// `ability_activation` → `lineup_edit` transition (which happens ~3.5s after
/// reveal, often before a several-ability sequence finishes animating), so
/// the cinematic reveal is never cut off mid-flight by the underlying phase
/// change. See GameScreen's `_abilityRevealBatch` handling.
class AbilityRevealOverlay extends StatefulWidget {
  const AbilityRevealOverlay({
    super.key,
    required this.activations,
    required this.players,
    required this.localPlayerId,
    required this.onDone,
  });

  /// The full, already-resolved reveal log, in deterministic server order.
  final List<AbilityActivation> activations;

  /// Every player in the room — including those with no activation entry
  /// (discarded, or no ability at all), who stay face-down the whole time.
  final List<GamePlayer> players;

  final String localPlayerId;

  /// Called once the player dismisses the final summary (or immediately,
  /// with an empty summary, if nobody used a card this round).
  final VoidCallback onDone;

  @override
  State<AbilityRevealOverlay> createState() => _AbilityRevealOverlayState();
}

enum _Stage { intro, revealing, summary }

class _AbilityRevealOverlayState extends State<AbilityRevealOverlay> {
  _Stage _stage = _Stage.intro;
  int _revealIndex = -1;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 650), _startStepping);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startStepping() {
    if (!mounted) return;
    if (widget.activations.isEmpty) {
      setState(() => _stage = _Stage.summary);
      return;
    }
    setState(() {
      _stage = _Stage.revealing;
      _revealIndex = 0;
    });
    _armNextStep();
  }

  void _armNextStep() {
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      final next = _revealIndex + 1;
      if (next >= widget.activations.length) {
        setState(() => _stage = _Stage.summary);
      } else {
        setState(() => _revealIndex = next);
        _armNextStep();
      }
    });
  }

  void _skip() {
    _timer?.cancel();
    setState(() {
      _stage = _Stage.summary;
      _revealIndex = widget.activations.length - 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 520;

    return Positioned.fill(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 350),
        opacity: 1,
        curve: Curves.easeOut,
        child: Container(
          color: Colors.black.withValues(alpha: 0.78),
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 14 : 32,
                vertical: 18,
              ),
              child: Column(
                children: [
                  Expanded(child: Center(child: _body(isCompact))),
                  if (_stage == _Stage.revealing)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: TextButton.icon(
                        onPressed: _skip,
                        icon: const Icon(
                          Icons.fast_forward_rounded,
                          color: HETheme.pfTextSecondary,
                          size: 16,
                        ),
                        label: const Text(
                          'Skip reveal',
                          style: TextStyle(color: HETheme.pfTextSecondary),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(bool isCompact) {
    switch (_stage) {
      case _Stage.intro:
        return const _IntroText();
      case _Stage.revealing:
        return _RevealBody(
          activations: widget.activations,
          revealIndex: _revealIndex,
          players: widget.players,
          localPlayerId: widget.localPlayerId,
          isCompact: isCompact,
        );
      case _Stage.summary:
        return AbilityResolvedSummary(
          activations: widget.activations,
          localPlayerId: widget.localPlayerId,
          onContinue: widget.onDone,
        );
    }
  }
}

class _IntroText extends StatelessWidget {
  const _IntroText();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.9 + 0.1 * t, child: child),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.visibility_rounded, color: HETheme.pfAccentViolet, size: 34),
          SizedBox(height: 10),
          Text(
            'Everyone has locked in…',
            style: TextStyle(
              color: HETheme.pfTextPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Revealing abilities',
            style: TextStyle(color: HETheme.pfTextSecondary, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _RevealBody extends StatelessWidget {
  const _RevealBody({
    required this.activations,
    required this.revealIndex,
    required this.players,
    required this.localPlayerId,
    required this.isCompact,
  });

  final List<AbilityActivation> activations;
  final int revealIndex;
  final List<GamePlayer> players;
  final String localPlayerId;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final current = activations[revealIndex];
    // Cumulative: every activation up to and including the current step
    // stays visibly flipped — only what's still strictly ahead is hidden.
    final revealedByPlayer = <String, AbilityType>{
      for (var i = 0; i <= revealIndex; i++)
        activations[i].byPlayerId: activations[i].type,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AbilityResolutionBanner(
          activation: current,
          isYou: current.byPlayerId == localPlayerId,
        ),
        SizedBox(height: isCompact ? 20 : 28),
        SizedBox(
          height: isCompact ? 108 : 118,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final p in players)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: AbilityRevealCard(
                      playerName: p.displayName,
                      isYou: p.id == localPlayerId,
                      type: revealedByPlayer[p.id],
                      revealed: revealedByPlayer.containsKey(p.id),
                      highlighted: p.id == current.byPlayerId,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '${revealIndex + 1} of ${activations.length}',
          style: const TextStyle(
            color: HETheme.pfTextMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
