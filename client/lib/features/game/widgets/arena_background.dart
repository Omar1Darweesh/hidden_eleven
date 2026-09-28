import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_motion.dart';
import 'package:hidden_eleven/app/he_theme.dart';

/// Which arrangement the arena lays its light and geometry out in.
///
/// Deliberately an explicit enum passed down by the layout rather than
/// something this widget derives from its own width: the game screen already
/// knows which composition it chose, and a background that re-derives the
/// breakpoint independently is one refactor away from disagreeing with the
/// foreground about which layout is on screen.
enum ArenaLayout { desktop, tablet, mobile }

/// Owns and publishes the game screen's **single** ambient animation clock.
///
/// This wraps both the background and the foreground, because the two need
/// to share one controller: the pitch's centre-circle light sweep is
/// conceptually part of the arena's ambience but renders deep inside
/// `PitchView`. Giving `PitchView` its own controller would mean two ambient
/// loops, which the art direction forbids.
///
/// Under reduced motion no controller is constructed and [maybeOf] returns
/// null, so every consumer falls back to its static resting state and the
/// screen schedules no frames at all.
class ArenaClock extends StatefulWidget {
  const ArenaClock({super.key, required this.child});

  final Widget child;

  /// The shared 0..1 ambient animation, or null when motion is reduced or
  /// there is no [ArenaClock] above this context. Never throws — a widget
  /// that can render statically should not require an arena to exist.
  static Animation<double>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_ArenaClockScope>()
      ?.listenable;

  @override
  State<ArenaClock> createState() => _ArenaClockState();
}

class _ArenaClockState extends State<ArenaClock>
    with SingleTickerProviderStateMixin {
  AnimationController? _clock;
  bool _checked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    if (!HEMotion.reduced(context)) {
      _clock = AnimationController(vsync: this, duration: HEMotion.ambient)
        ..repeat();
    }
  }

  @override
  void dispose() {
    _clock?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _ArenaClockScope(listenable: _clock, child: widget.child);
}

class _ArenaClockScope extends InheritedWidget {
  const _ArenaClockScope({required this.listenable, required super.child});

  final Animation<double>? listenable;

  @override
  bool updateShouldNotify(_ArenaClockScope oldWidget) =>
      oldWidget.listenable != listenable;
}

/// The "Night Tactics" gameplay background — a lit stadium arena rather than
/// a dark canvas.
///
/// Six layers, one clock:
///   1. Plum base gradient (static)
///   2. Light field — large soft violet/magenta radials (drifting)
///   3. Tactical grid — oversized pitch geometry at 4-6% alpha (shimmering)
///   4. Arena focus — a brighter halo positioned behind the pitch
///   5. Mission field — a magenta wash behind the mission card, on your turn
///   6. Vignette (static)
///
/// **Performance contract.** Exactly ONE [AnimationController] drives layers
/// 2-4 — this is the single ambient system the art direction permits. Each
/// painter sits in its own [RepaintBoundary] and quantises the clock in
/// `shouldRepaint`, so the arena repaints at roughly 20fps rather than 60
/// and costs a fraction of a frame. No `BackdropFilter` over moving content
/// (the single most expensive thing available on Flutter web's canvas
/// renderer), no particle system, no per-frame allocation.
///
/// **Reduced motion.** The controller is never *constructed* when
/// `MediaQuery.disableAnimations` is set — every layer renders once at
/// `t = 0` and no frames are scheduled at rest. Pausing a controller would
/// still schedule frames; this is the pattern `MatchdayBackground` already
/// proves.
class ArenaBackground extends StatelessWidget {
  const ArenaBackground({
    super.key,
    required this.layout,
    this.focusAlignment = const Alignment(-0.32, 0.06),
    this.missionActive = false,
    this.missionAlignment = const Alignment(0.72, -0.34),
  });

  /// Which of the three compositions to lay out. See [ArenaLayout].
  final ArenaLayout layout;

  /// Where the bright arena halo centres — the layout passes the pitch's
  /// position, so the brightest part of the room is always behind the pitch.
  final Alignment focusAlignment;

  /// Whether the secondary magenta field behind the mission card is lit.
  /// True only when it is the local player's turn — this is the background's
  /// half of the "one hot thing on screen" rule.
  final bool missionActive;

  /// Where that mission field centres.
  final Alignment missionAlignment;

  /// Builds one ambient layer, wired to the shared [ArenaClock] when there is
  /// one and rendered statically at `t = 0` when there isn't.
  static Widget _ambient(
    Animation<double>? clock,
    Widget Function(double t) build,
  ) {
    return RepaintBoundary(
      child: clock == null
          ? build(0)
          : AnimatedBuilder(
              animation: clock,
              builder: (_, _) => build(clock.value),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clock = ArenaClock.maybeOf(context);

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1 ── Plum base. Lighter at the top, where the light reads as
          // coming from, settling into the void at the bottom.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF150E28), HETheme.pfBgVoid],
                stops: [0.0, 0.78],
              ),
            ),
          ),

          // 2 ── Light field.
          _ambient(
            clock,
            (t) => CustomPaint(
              painter: _LightFieldPainter(t: t, layout: layout),
            ),
          ),

          // 3 ── Tactical grid.
          _ambient(
            clock,
            (t) => CustomPaint(
              painter: _TacticalGridPainter(t: t, layout: layout),
            ),
          ),

          // 4 ── Arena focus halo, behind the pitch.
          _ambient(
            clock,
            (t) => CustomPaint(
              painter: _ArenaFocusPainter(
                t: t,
                alignment: focusAlignment,
                layout: layout,
              ),
            ),
          ),

          // 5 ── Mission field. Not on the ambient clock: it is a state
          // change, not an ambience, so it cross-fades on turn start and
          // then holds.
          AnimatedOpacity(
            opacity: missionActive ? 1.0 : 0.0,
            duration: HEMotion.wake,
            curve: HEMotion.easeOut,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _MissionFieldPainter(
                  alignment: missionAlignment,
                  layout: layout,
                ),
              ),
            ),
          ),

          // 6 ── Vignette. Keeps the corners grounded so foreground text
          // never has to compete with the brightest part of a blob.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.0, -0.24),
                radius: 1.15,
                colors: [Colors.transparent, Color(0xDB0A0714)],
                stops: [0.42, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared helpers ───────────────────────────────────────────────────────────

/// Quantises the 0..1 ambient clock so painters repaint ~20 times a second
/// instead of 60. At a 40s cycle the visual difference is undetectable — the
/// motion is far slower than the quantisation step — but it cuts ambient
/// repaint cost to a third.
int _q(double t) => (t * HEMotion.ambient.inSeconds * 20).floor();

/// A slow symmetric oscillation in -1..1 with an arbitrary phase offset, so
/// each blob drifts on its own rhythm off one shared clock.
double _wave(double t, double phase) => math.sin((t + phase) * 2 * math.pi);

// ── Layer 2: light field ─────────────────────────────────────────────────────

class _Blob {
  const _Blob({
    required this.center,
    required this.radius,
    required this.color,
    required this.alpha,
    required this.phase,
    this.drift = 0.03,
  });

  /// Normalised position (0..1 of the canvas), before drift.
  final Offset center;

  /// Radius as a fraction of the canvas's longest side.
  final double radius;
  final Color color;
  final double alpha;
  final double phase;

  /// How far the blob wanders, as a fraction of the canvas.
  final double drift;
}

class _LightFieldPainter extends CustomPainter {
  const _LightFieldPainter({required this.t, required this.layout});

  final double t;
  final ArenaLayout layout;

  /// Deliberately different arrangements per breakpoint rather than one set
  /// of blobs scaled down — a scaled desktop background reads as "the same
  /// picture, smaller", which is exactly the thing that makes responsive
  /// backgrounds feel like an afterthought.
  List<_Blob> get _blobs => switch (layout) {
    ArenaLayout.desktop => const [
      _Blob(
        center: Offset(0.06, 0.02),
        radius: 0.52,
        color: HETheme.pfAccentViolet,
        alpha: 0.30,
        phase: 0.0,
      ),
      _Blob(
        center: Offset(0.94, 0.14),
        radius: 0.44,
        color: HETheme.pfAccentMagenta,
        alpha: 0.16,
        phase: 0.37,
      ),
      _Blob(
        center: Offset(0.46, 1.02),
        radius: 0.58,
        color: HETheme.pfSecondaryViolet,
        alpha: 0.22,
        phase: 0.68,
      ),
    ],
    ArenaLayout.tablet => const [
      _Blob(
        center: Offset(0.16, 0.02),
        radius: 0.62,
        color: HETheme.pfAccentViolet,
        alpha: 0.28,
        phase: 0.0,
      ),
      _Blob(
        center: Offset(0.86, 0.20),
        radius: 0.50,
        color: HETheme.pfAccentMagenta,
        alpha: 0.15,
        phase: 0.42,
      ),
    ],
    ArenaLayout.mobile => const [
      _Blob(
        center: Offset(0.50, -0.04),
        radius: 0.86,
        color: HETheme.pfAccentViolet,
        alpha: 0.30,
        phase: 0.0,
        drift: 0.02,
      ),
      _Blob(
        center: Offset(0.50, 1.04),
        radius: 0.74,
        color: HETheme.pfSecondaryViolet,
        alpha: 0.20,
        phase: 0.5,
        drift: 0.02,
      ),
    ],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final longest = math.max(size.width, size.height);

    for (final b in _blobs) {
      // Drift + a gentle scale breath, both off the one shared clock.
      final dx = _wave(t, b.phase) * b.drift * size.width;
      final dy = _wave(t, b.phase + 0.25) * b.drift * size.height;
      final scale = 1.0 + _wave(t, b.phase + 0.5) * 0.09;

      final center = Offset(
        b.center.dx * size.width + dx,
        b.center.dy * size.height + dy,
      );
      final radius = b.radius * longest * scale;
      final rect = Rect.fromCircle(center: center, radius: radius);

      // A radial *shader* rather than a blurred circle: MaskFilter blur at
      // this radius is one of the most expensive operations available on
      // Flutter web, and the gradient produces a softer falloff anyway.
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              b.color.withValues(alpha: b.alpha),
              b.color.withValues(alpha: 0),
            ],
            stops: const [0.0, 1.0],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_LightFieldPainter old) =>
      old.layout != layout || _q(old.t) != _q(t);
}

// ── Layer 3: tactical grid ───────────────────────────────────────────────────

/// Oversized pitch geometry — a centre circle, halfway line and penalty-box
/// corners at 4-6% alpha, scaled far beyond the viewport so only a fragment
/// is ever visible. Reads as "you are standing on an enormous tactics board"
/// rather than as a decorative pattern.
class _TacticalGridPainter extends CustomPainter {
  const _TacticalGridPainter({required this.t, required this.layout});

  final double t;
  final ArenaLayout layout;

  double get _scale => switch (layout) {
    ArenaLayout.desktop => 0.46,
    ArenaLayout.tablet => 0.62,
    ArenaLayout.mobile => 0.96,
  };

  @override
  void paint(Canvas canvas, Size size) {
    // A ±1.5% alpha shimmer — perceptible as "alive" without ever being
    // readable as a discrete animation.
    final shimmer = 0.045 + _wave(t, 0.12) * 0.015;
    final paint = Paint()
      ..color = HETheme.pfLavenderText.withValues(alpha: shimmer)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final cx = size.width * 0.5;
    final cy = size.height * (layout == ArenaLayout.mobile ? 0.42 : 0.52);
    final r = size.width * _scale;

    canvas.drawCircle(Offset(cx, cy), r, paint);
    canvas.drawCircle(Offset(cx, cy), r * 0.30, paint);
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), paint);

    // Penalty-box corners — two brackets, top and bottom, suggesting a box
    // far larger than the screen.
    final boxW = r * 1.5;
    final boxH = size.height * 0.30;
    for (final dir in const [-1.0, 1.0]) {
      final y = cy + dir * (r * 1.35);
      final path = Path()
        ..moveTo(cx - boxW, y + dir * boxH)
        ..lineTo(cx - boxW, y)
        ..lineTo(cx + boxW, y)
        ..lineTo(cx + boxW, y + dir * boxH);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_TacticalGridPainter old) =>
      old.layout != layout || _q(old.t) != _q(t);
}

// ── Layer 4: arena focus ─────────────────────────────────────────────────────

/// The brighter halo that sits directly behind the pitch, so the pitch is
/// never a bright object on an empty dark field — it is the lit centre of a
/// lit room.
class _ArenaFocusPainter extends CustomPainter {
  const _ArenaFocusPainter({
    required this.t,
    required this.alignment,
    required this.layout,
  });

  final double t;
  final Alignment alignment;
  final ArenaLayout layout;

  @override
  void paint(Canvas canvas, Size size) {
    final center = alignment.alongSize(size);
    // Tall ellipse — the pitch is portrait (0.625), so a circular halo would
    // spill wide and light the gutters instead of the pitch.
    final breath = 1.0 + _wave(t, 0.6) * 0.06;
    final rx =
        size.width * (layout == ArenaLayout.desktop ? 0.34 : 0.46) * breath;
    final ry = size.height * 0.56 * breath;

    final rect = Rect.fromCenter(center: center, width: rx * 2, height: ry * 2);

    canvas.drawOval(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            HETheme.pfAccentViolet.withValues(alpha: 0.26),
            HETheme.pfSecondaryViolet.withValues(alpha: 0.10),
            HETheme.pfAccentViolet.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.48, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_ArenaFocusPainter old) =>
      old.alignment != alignment || old.layout != layout || _q(old.t) != _q(t);
}

// ── Layer 5: mission field ───────────────────────────────────────────────────

/// A magenta wash behind the mission card, lit only while it is your turn.
/// Static by design: this is a *state*, and putting it on the ambient clock
/// would make "it's your turn" feel decorative rather than declarative.
class _MissionFieldPainter extends CustomPainter {
  const _MissionFieldPainter({required this.alignment, required this.layout});

  final Alignment alignment;
  final ArenaLayout layout;

  @override
  void paint(Canvas canvas, Size size) {
    final center = alignment.alongSize(size);
    final r = size.width * (layout == ArenaLayout.desktop ? 0.30 : 0.52);
    final rect = Rect.fromCircle(center: center, radius: r);

    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            HETheme.pfAccentMagenta.withValues(alpha: 0.20),
            HETheme.pfAccentMagenta.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_MissionFieldPainter old) =>
      old.alignment != alignment || old.layout != layout;
}
