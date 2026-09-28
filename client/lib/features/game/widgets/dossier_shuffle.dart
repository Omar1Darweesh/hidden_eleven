import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_motion.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/widgets/sealed_dossier_card.dart'
    show DossierFolderClip, DossierFolderPainter;

/// The Sealed Dossier Shuffle choreography — a single, scrubbable timeline.
///
/// ## Why this exists
///
/// The sequence used to be driven by nine independent `Timer`s
/// (`_toFlip`, nine `_shuffleTimers`, `_toDone`). That worked, but it meant
/// the choreography could not be eased, scrubbed or tested as a unit, and
/// every timer was a separate late-fire/leak risk that had to be cancelled by
/// hand. This collapses the whole thing into ONE [AnimationController] with
/// named [Interval] stages: one object to create, one to dispose, one source
/// of truth for "where are we in the sequence".
///
/// ## Privacy contract — the important part
///
/// **No motion parameter may be derived from card content.** Every offset,
/// rotation, scale, shadow, duration and z-order below is a function of
/// *display position* (`0..n-1`) and the shared clock `t` only. Two decks
/// with completely different cards must produce byte-identical motion.
/// `dossier_shuffle_test.dart` asserts exactly this by rendering two intros
/// with different cards and comparing transforms at matched `t`.
///
/// The permutation itself ([DossierShuffleTimeline.orderAt]) is likewise a
/// pure function of the stage index and the *initial* order — never of the
/// cards, and never fed back into any real slot data.
class DossierShuffleTimeline {
  const DossierShuffleTimeline._();

  // ── Stage boundaries, in milliseconds ───────────────────────────────────
  //
  // Total 4100ms, down from ~6600ms. The face-up preview hold was the least
  // interesting part of the old sequence and carried most of the excess.
  static const int enterMs = 300;
  static const int previewMs = 2200;
  static const int flipMs = 380;
  static const int shuffleMs = 1000;
  static const int settleMs = 220;

  static const int totalMs =
      enterMs + previewMs + flipMs + shuffleMs + settleMs;

  static const Duration total = Duration(milliseconds: totalMs);

  // Normalised stage bounds on the 0..1 controller.
  static const double enterEnd = enterMs / totalMs;
  static const double previewEnd = (enterMs + previewMs) / totalMs;
  static const double flipEnd = (enterMs + previewMs + flipMs) / totalMs;
  static const double shuffleEnd =
      (enterMs + previewMs + flipMs + shuffleMs) / totalMs;

  /// The three deliberate swap moves inside the shuffle stage, as normalised
  /// fractions of the shuffle window. Three *readable* moves rather than a
  /// blur — you can follow an individual dossier, which is what separates a
  /// dealer from a slot machine.
  static const List<double> moveBounds = [0.0, 0.34, 0.68, 1.0];

  /// Progress 0..1 within the shuffle stage, or null outside it.
  static double? shuffleProgress(double t) {
    if (t < flipEnd || t > shuffleEnd) return null;
    return ((t - flipEnd) / (shuffleEnd - flipEnd)).clamp(0.0, 1.0);
  }

  /// How many of the three moves have completed at time [t] (0..3).
  static int completedMoves(double t) {
    final p = shuffleProgress(t);
    if (p == null) return t > shuffleEnd ? moveBounds.length - 1 : 0;
    var done = 0;
    for (var i = 1; i < moveBounds.length; i++) {
      if (p >= moveBounds[i]) done++;
    }
    return done;
  }

  /// The display permutation after [move] completed moves.
  ///
  /// Deterministic and content-blind: it is a fixed sequence of positional
  /// swaps over the identity ordering, so it produces the same visual result
  /// for any deck of the same size. Crucially the result is a permutation of
  /// *display positions*, which have no relationship to real slot indices —
  /// see `HiddenDraftIntro`'s class doc comment.
  static List<int> orderAt(int count, int move) {
    final order = List<int>.generate(count, (i) => i);
    if (count < 2) return order;

    void swap(int a, int b) {
      if (a < 0 || b < 0 || a >= count || b >= count || a == b) return;
      final tmp = order[a];
      order[a] = order[b];
      order[b] = tmp;
    }

    // Move 1 — the two outer dossiers cross (one passes behind, see zOrder).
    if (move >= 1) swap(0, count - 1);
    // Move 2 — a centre dossier slides out and tucks in at the far end.
    if (move >= 2) swap(count ~/ 2, count - 1);
    // Move 3 — the row compresses and reforms, offsetting by one.
    if (move >= 3) swap(0, count ~/ 2);

    return order;
  }

  /// Paint order for a card at [displayPos] during [move].
  ///
  /// Returns a higher number for cards that should render on top. During the
  /// first move exactly one card passes *behind* another, which is what makes
  /// the shuffle read as physical rather than as a grid reflow.
  static int zOrder(int displayPos, int count, int move, double? moveT) {
    if (moveT == null || move != 1) return displayPos;
    // The card travelling right-to-left dips behind.
    return displayPos == count - 1 ? -1 : displayPos;
  }

  /// Vertical lift for a card mid-move — an arc peaking at the midpoint of
  /// its travel, like a magician clearing the table before a flick.
  /// Depends only on progress, never on content.
  static double liftFor(double moveT) => math.sin(moveT * math.pi) * 24.0;

  /// Rotational flourish (radians) for a card mid-move — zero at both ends
  /// (it lands flat), peaking mid-flight. The caller multiplies this by the
  /// travel direction's sign, so a card moving right tilts one way and a
  /// card moving left tilts the other — the wrist-flick a real card cut has.
  static double tiltFor(double moveT) => math.sin(moveT * math.pi) * 0.16;

  /// A small "pop" scale for a card mid-move — it lifts slightly larger, as
  /// if closer to the eye while airborne, and settles back to 1.0 on landing.
  static double popFor(double moveT) => 1.0 + math.sin(moveT * math.pi) * 0.08;

  /// Fan rotation (radians) for [displayPos] while the cards are still face
  /// up. Flattens to zero the moment the flip starts, so the hand-off to the
  /// unfanned grid feels intentional rather than abrupt.
  static double fanAngle(int displayPos, int count, double t) {
    if (t > previewEnd) return 0.0;
    final spread = (displayPos - (count - 1) / 2) * 0.05;
    // Ease the fan in during the enter stage.
    final in_ = (t / enterEnd).clamp(0.0, 1.0);
    return spread * in_;
  }

  /// Staggered entrance progress for [displayPos] — cards arrive in sequence
  /// rather than all at once.
  static double entranceFor(int displayPos, int count, double t) {
    final stagger = count <= 1 ? 0.0 : (displayPos / count) * 0.5;
    final local = ((t / enterEnd) - stagger) / (1 - stagger).clamp(0.001, 1.0);
    return local.clamp(0.0, 1.0);
  }

  /// Flip progress 0..1 (0 = face up, 1 = face down).
  static double flipProgress(double t) {
    if (t <= previewEnd) return 0.0;
    if (t >= flipEnd) return 1.0;
    return ((t - previewEnd) / (flipEnd - previewEnd)).clamp(0.0, 1.0);
  }
}

/// The face-down side of a card during the shuffle sequence.
///
/// Before this, the shuffle showed the deck's own [PlayerCard] face-down
/// state — a plain navy rectangle with an emerald shield, the OLD `HEColors`
/// palette. The instant the intro finished, the exact same slot re-rendered
/// as a gold-and-plum [SealedDossierCard] folder. That mismatch — one design
/// language for the four seconds of shuffle, a different one the moment it
/// mattered — is what read as unpolished. This reuses the dossier's own
/// [DossierFolderClip]/[DossierFolderPainter], so the shuffle and the real
/// grid are visibly the same object throughout.
///
/// [glowT] drives a slow orbiting rim highlight — the same sweep-gradient
/// technique the arena background and pitch centre circle already use, so
/// this reads as one visual system rather than a one-off effect. Null (idle,
/// no card is travelling) renders the calm resting glow only.
class ShuffleCardBack extends StatelessWidget {
  const ShuffleCardBack({super.key, this.glowT});

  final double? glowT;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: HETheme.pfGold.withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipPath(
        clipper: const DossierFolderClip(),
        child: CustomPaint(
          foregroundPainter: glowT == null
              ? null
              : _ShuffleRimGlowPainter(t: glowT!),
          painter: const DossierFolderPainter(
            fill: HETheme.pfSurfaceRaised,
            accent: HETheme.pfGold,
            borderWidth: 1.5,
            showLavenderRim: false,
          ),
          child: LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth;
              return Padding(
                padding: EdgeInsets.only(top: w * 0.14),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: w * 0.30,
                      height: w * 0.30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: HETheme.pfGold.withValues(alpha: 0.7),
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Transform.rotate(
                          angle: 0.785398,
                          child: Container(
                            width: w * 0.09,
                            height: w * 0.09,
                            decoration: BoxDecoration(
                              color: HETheme.pfGold.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: w * 0.09),
                    Text(
                      'SEALED',
                      style: HETheme.mono(
                        size: (w * 0.10).clamp(7.5, 10.0),
                        weight: FontWeight.w800,
                        color: HETheme.pfGold.withValues(alpha: 0.75),
                      ).copyWith(letterSpacing: 1.0),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A slow travelling highlight around the folder's rim — the shuffle's own
/// small share of ambient life. Purely decorative, driven only by the shared
/// timeline `t`, never by card identity.
class _ShuffleRimGlowPainter extends CustomPainter {
  const _ShuffleRimGlowPainter({required this.t});

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final path = const DossierFolderClip().getClip(size);
    final rect = Offset.zero & size;

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..shader = SweepGradient(
          transform: GradientRotation(t * 2 * math.pi),
          colors: [
            HETheme.pfAccentVioletGlow.withValues(alpha: 0),
            HETheme.pfAccentVioletGlow.withValues(alpha: 0),
            HETheme.pfAccentVioletGlow.withValues(alpha: 0.85),
            HETheme.pfAccentVioletGlow.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.7, 0.85, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_ShuffleRimGlowPainter old) => old.t != t;
}

/// Caption shown above the dossiers for a given point on the timeline.
enum DossierStage { entering, preview, flipping, shuffling, ready }

DossierStage dossierStageAt(double t) {
  if (t < DossierShuffleTimeline.enterEnd) return DossierStage.entering;
  if (t < DossierShuffleTimeline.previewEnd) return DossierStage.preview;
  if (t < DossierShuffleTimeline.flipEnd) return DossierStage.flipping;
  if (t < DossierShuffleTimeline.shuffleEnd) return DossierStage.shuffling;
  return DossierStage.ready;
}

String dossierCaptionFor(DossierStage stage) => switch (stage) {
  DossierStage.entering ||
  DossierStage.preview => "Here's what's left in the deck…",
  DossierStage.flipping => 'Sealing them…',
  DossierStage.shuffling => 'Mixing them up…',
  DossierStage.ready => 'Choose one dossier',
};

/// The caption strip above the shuffling dossiers.
class DossierCaption extends StatelessWidget {
  const DossierCaption({super.key, required this.stage});

  final DossierStage stage;

  @override
  Widget build(BuildContext context) {
    final ready = stage == DossierStage.ready;
    return AnimatedSwitcher(
      duration: HEMotion.focus,
      child: Container(
        key: ValueKey(stage),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: (ready ? HETheme.pfGold : HETheme.pfSecondaryViolet)
              .withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: (ready ? HETheme.pfGold : HETheme.pfSecondaryViolet)
                .withValues(alpha: 0.42),
          ),
        ),
        child: Text(
          dossierCaptionFor(stage),
          style: HETheme.body(
            size: 12,
            weight: FontWeight.w600,
            color: ready ? HETheme.pfGold : HETheme.pfLavenderText,
          ),
        ),
      ),
    );
  }
}
