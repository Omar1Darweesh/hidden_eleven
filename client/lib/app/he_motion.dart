import 'package:flutter/material.dart';

/// "Night Tactics" motion constants — one place for every duration and curve
/// the game screen animates with, so the whole screen moves with one rhythm
/// instead of each widget inventing its own timing.
///
/// The contract these encode (see the Night Tactics motion spec):
///  1. Exactly ONE looping ambient system, plus genuine loading indicators.
///     Nothing else loops.
///  2. No animation sits on the critical path of a tap — state commits
///     immediately and the visual follows.
///  3. No animation decides or delays game state.
///  4. Every effect has a reduced-motion answer, and under reduced motion no
///     `AnimationController` is *constructed* at all (not merely paused).
class HEMotion {
  HEMotion._();

  // ── Ambient ──────────────────────────────────────────────────────────────
  /// The single arena background clock. One controller drives the light
  /// field, the tactical grid and the arena focus halo.
  static const ambient = Duration(seconds: 40);

  /// Shared by every "breathing" affordance (selectable slots, waiting dots).
  /// One controller is created per screen and passed down as a value, rather
  /// than each slot owning its own ticker.
  static const breathe = Duration(milliseconds: 2400);

  /// The live round slot's pulse — faster than [breathe] so the one hot
  /// element reads as more urgent than the merely-selectable ones.
  static const pulse = Duration(milliseconds: 1600);

  /// Timer urgency pulse, under 25% remaining.
  static const urgent = Duration(milliseconds: 1400);

  /// Opponent-turn waiting indicator.
  static const waiting = Duration(milliseconds: 1800);

  // ── Entrance ─────────────────────────────────────────────────────────────
  /// Total screen-entrance sequence. Layers are staggered inside this with
  /// [entranceBackground] / [entranceArena] / [entrancePanels] intervals.
  static const entrance = Duration(milliseconds: 480);
  static const entranceBackground = Interval(0.0, 0.62, curve: easeOut);
  static const entranceArena = Interval(0.12, 0.92, curve: easeOut);
  static const entrancePanels = Interval(0.25, 1.0, curve: easeOut);

  // ── Interaction ──────────────────────────────────────────────────────────
  /// Hover / focus ring response.
  static const focus = Duration(milliseconds: 140);

  /// Press down / release.
  static const pressDown = Duration(milliseconds: 90);
  static const pressUp = Duration(milliseconds: 160);

  /// Card selected — lift + glow.
  static const select = Duration(milliseconds: 180);

  /// Mission card waking up when the turn becomes yours.
  static const wake = Duration(milliseconds: 420);

  /// Card landing on the pitch. Matches the existing `AnimatedSwitcher` in
  /// `pitch_view.dart` exactly — restated here, not changed.
  static const land = Duration(milliseconds: 340);

  /// Phase transition. Must stay under 450ms: gameplay continues underneath.
  static const phase = Duration(milliseconds: 380);

  /// Drawer detent change.
  static const drawer = Duration(milliseconds: 280);

  /// Confirm / lock.
  static const confirm = Duration(milliseconds: 240);

  /// Success rim flash.
  static const success = Duration(milliseconds: 300);

  // ── Curves ───────────────────────────────────────────────────────────────
  static const easeOut = Curves.easeOutCubic;
  static const easeInOut = Curves.easeInOut;

  /// Landing / confirm overshoot. Deliberately NOT used for anything docked
  /// near the thumb on mobile — overshoot under a finger reads as a misfire.
  static const overshoot = Curves.easeOutBack;

  /// Returns true when the OS asks for reduced motion.
  ///
  /// Call this in `didChangeDependencies` and skip constructing controllers
  /// entirely when it's true — the pattern `MatchdayBackground` and
  /// `HeroEntrance` already prove. Pausing a controller still schedules
  /// frames; not building one is the only way to actually go quiet.
  static bool reduced(BuildContext context) =>
      MediaQuery.of(context).disableAnimations;
}
