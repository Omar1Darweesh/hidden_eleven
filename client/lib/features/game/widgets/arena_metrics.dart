import 'dart:math';

import 'package:hidden_eleven/features/game/widgets/arena_frame.dart';

/// The wide (desktop) game layout's pitch-sizing math, extracted as a pure
/// value type.
///
/// This is the code that produced the constant 3px overflow, so it is
/// deliberately *not* inlined in a `LayoutBuilder` closure any more: pulling
/// it out means `game_layout_overflow_test.dart` can sweep real viewport
/// sizes and assert on the actual numbers, rather than re-deriving the
/// formula in the test and only ever proving the copy self-consistent.
///
/// Every dimension it reports is floored to whole pixels — see [pitchW].
class GameArenaMetrics {
  const GameArenaMetrics._({
    required this.sidebarW,
    required this.pitchW,
    required this.pitchH,
    required this.availPitchH,
    required this.needsScroll,
  });

  /// Width of the right-hand panel column.
  final double sidebarW;

  /// The pitch box itself — NOT including the arena frame around it.
  final double pitchW;
  final double pitchH;

  /// Vertical space available to the pitch after all chrome.
  final double availPitchH;

  /// True when a legible pitch genuinely cannot fit and the left column must
  /// scroll instead of shrinking below [kMinPitchW].
  final bool needsScroll;

  /// Bezel between the arena frame's edge and the pitch.
  static const double kBezel = 14.0;

  /// How far the player tab pills stand proud of the frame's top edge.
  static const double kTabOverlap = 30.0;

  /// Legibility floor. Below this the 11 position cards overlap into an
  /// unreadable, un-tappable cluster, so we scroll rather than shrink.
  static const double kMinPitchW = 280.0;

  /// Portrait pitch ratio (w:h). Shared with `PitchView`'s `AspectRatio`.
  static const double kRatio = 0.625;

  /// Vertical chrome outside the pitch in the left column:
  /// top padding + tab overlap band + the frame's FULL inset + gap + bottom
  /// padding.
  ///
  /// The frame's cost comes from [ArenaFrame.totalInset], never from
  /// `kBezel * 2`. Restating it as `kBezel * 2` is precisely the bug this
  /// class exists to prevent: `Container` adds its border's dimensions to
  /// its padding, so the frame costs 31px, not 28.
  static double get vChrome =>
      16 + kTabOverlap + ArenaFrame.totalInset(kBezel) + 16 + 16;

  /// Outer horizontal padding (20 + 20) + inter-column gap (24) + the frame.
  static double get hChrome => 64.0 + ArenaFrame.totalInset(kBezel);

  /// Computes the layout for a viewport of [vw] × [vh] (the body region,
  /// below the match bar and inside any safe area).
  factory GameArenaMetrics.forViewport({
    required double vw,
    required double vh,
  }) {
    // Narrower ratio and a higher floor than the original 0.28/270: at 1366
    // the old math gave a 382px sidebar against a height-capped pitch, which
    // is what made the right column read as mostly empty. 300 is the width
    // at which the mission card's instruction still sets on two lines
    // without the timer dial crowding it.
    final sidebarW = (vw * 0.26).clamp(300.0, 380.0);
    final leftColW = vw - hChrome - sidebarW;
    final availPitchH = (vh - vChrome).clamp(200.0, double.infinity);

    // Fit to whichever axis binds first, then apply the legibility floor.
    //
    // Floored BEFORE deriving the height: a fractional width becomes a
    // fractional height that can round up past the available space. That
    // sub-pixel drift is what the old `+ 4` tolerance in `needsScroll` was
    // hiding — and the tolerance let up to 4px of genuine overflow through
    // with it. Flooring removes the cause, so the tolerance is gone.
    final fitW = min(leftColW, availPitchH * kRatio).floorToDouble();
    final pitchW = max(fitW, kMinPitchW);
    final pitchH = (pitchW / kRatio).floorToDouble();

    return GameArenaMetrics._(
      sidebarW: sidebarW,
      pitchW: pitchW,
      pitchH: pitchH,
      availPitchH: availPitchH,
      // No tolerance. Reachable only via the legibility floor — a viewport
      // so short that a readable pitch cannot fit — which is the one case
      // where an intentional scroll beats unusably small tactical cards.
      needsScroll: pitchH > availPitchH,
    );
  }

  /// Total height the left column will occupy, including all chrome. Used by
  /// tests to assert the column fits inside [vh].
  double get columnHeight => pitchH + vChrome;

  /// Total width the framed arena occupies.
  double get arenaW => pitchW + ArenaFrame.totalInset(kBezel);
}
