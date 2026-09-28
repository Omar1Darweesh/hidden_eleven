import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_motion.dart';
import 'package:hidden_eleven/app/he_theme.dart';

/// Which event this atmosphere is dressing.
///
/// The two variants share one painter set and differ only in palette
/// weighting and geometry emphasis — they are the same room lit differently,
/// not two different backgrounds.
enum EventAtmosphereVariant {
  /// Tournament Hub — colder, more directional energy: the event is still
  /// being contested.
  tournament,

  /// Results / Tournament Complete — warmer and settled: the match is over.
  results,
}

/// The original "Night Tactics: Tournament Night" atmosphere behind the
/// Tournament and Results experiences.
///
/// Built entirely from gradients and paths — no images, no network, no
/// external or third-party assets of any kind.
///
/// **Atmosphere, never content.** Every layer stays well below the surfaces in
/// front of it, so the cards and text remain the thing you read.
///
/// The first pass took this far too literally — geometry at 4% alpha and
/// trails at 7% behind a 42px blur, on a near-black ground, added up to
/// nothing visible at all: the page simply read as flat black, and the
/// "deep violet/plum atmosphere" never existed on screen. The layers now sit
/// around 8–22% against a genuinely plum base. That is still far under the
/// card surfaces (which sit on opaque `pfSurfaceRaised`/`pfSurfaceDeep` fills),
/// so text contrast is unaffected — the atmosphere is simply perceptible now.
///
/// **Gold is reserved.** The gold radial paints *only* when [goldFocus] is
/// true, and only at [goldAlignment] — the final centre, the champion, the
/// winner hero, a rank-one moment. It is never ambient and never spread across
/// ordinary cards.
///
/// **One clock, or none.** The trails and particles drift on a single shared
/// 40-second [HEMotion.ambient] controller — never one ticker per layer, and
/// never a second looping animation on the same screen. Under reduced motion
/// (or with [animate] off) no controller is constructed at all: not one that
/// is paused, simply none, since a paused controller still schedules frames.
/// The composition then renders exactly as it did when this was a static
/// background, so reduced motion loses atmosphere but never information.
///
/// Particle placement comes from a fixed seed, so the layout is stable across
/// rebuilds — only the drift value moves anything.
class EventAtmosphereBackground extends StatefulWidget {
  const EventAtmosphereBackground({
    super.key,
    required this.variant,
    this.goldFocus = false,
    this.goldAlignment = Alignment.center,
    this.animate = true,
  });

  final EventAtmosphereVariant variant;

  /// Whether the reserved gold atmosphere paints at all.
  final bool goldFocus;

  /// Where the gold radial centres, when [goldFocus] is on.
  final Alignment goldAlignment;

  /// Whether the atmosphere drifts.
  ///
  /// Reduced motion overrides this to false regardless — a caller cannot opt
  /// back into movement for someone who asked for none.
  final bool animate;

  /// Hard cap on ambient particles. Deliberately small: this is dust caught in
  /// stadium light, not a particle system.
  static const int kMaxParticles = 20;

  /// Test-time escape hatch for the ambient drift.
  ///
  /// The drift is a *permanent* loop by design, which means `pumpAndSettle()`
  /// can never settle on any screen that shows this background — it would
  /// hang every existing test of the Tournament and Results screens. Rather
  /// than rewrite those tests to avoid `pumpAndSettle`, `flutter_test_config`
  /// turns the drift off for the whole suite, so tests keep asserting the
  /// settled composition while real users get the movement.
  ///
  /// Tests that specifically cover the drift set this back to true themselves.
  static bool debugAmbientDriftEnabled = true;

  @override
  State<EventAtmosphereBackground> createState() =>
      _EventAtmosphereBackgroundState();
}

class _EventAtmosphereBackgroundState extends State<EventAtmosphereBackground>
    with SingleTickerProviderStateMixin {
  /// The single ambient clock for the whole composition — trails and
  /// particles both read it. One ticker per screen, never one per element.
  ///
  /// Not constructed at all under reduced motion (or when [animate] is off),
  /// so the background is genuinely still rather than a paused loop that
  /// keeps scheduling frames.
  AnimationController? _clock;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(EventAtmosphereBackground old) {
    super.didUpdateWidget(old);
    if (old.animate != widget.animate) _sync();
  }

  void _sync() {
    final wanted =
        widget.animate &&
        EventAtmosphereBackground.debugAmbientDriftEnabled &&
        !HEMotion.reduced(context);
    if (!wanted) {
      _clock?.dispose();
      _clock = null;
      return;
    }
    if (_clock != null) return;
    // `ambient` is 40s — slow enough that nothing on screen appears to move
    // while you read it, but the composition is never quite the same twice.
    _clock = AnimationController(vsync: this, duration: HEMotion.ambient)
      ..repeat();
  }

  @override
  void dispose() {
    _clock?.dispose();
    super.dispose();
  }

  EventAtmosphereVariant get variant => widget.variant;
  bool get goldFocus => widget.goldFocus;
  Alignment get goldAlignment => widget.goldAlignment;

  @override
  Widget build(BuildContext context) {
    final results = variant == EventAtmosphereVariant.results;

    // Sizes to its parent and never takes a tap from the content in front of
    // it. Callers place it themselves (`Positioned.fill` inside a Stack), so
    // this widget stays usable outside a Stack too.
    return IgnorePointer(
      child: SizedBox.expand(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              // Real plum, not near-black. The first pass held every layer so
              // far under the "never compete with text" rule that the whole
              // atmosphere became imperceptible on a #0A0714 ground — the
              // page just read as flat black. These tones carry actual colour
              // while staying well below the surfaces in front of them.
              colors: results
                  ? const [
                      Color(0xFF2A1B47),
                      Color(0xFF150E28),
                      Color(0xFF0D0819),
                    ]
                  : const [
                      Color(0xFF241640),
                      Color(0xFF150E28),
                      Color(0xFF0C0718),
                    ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Each layer gets its own boundary so one repainting can never
              // drag the others (or the content in front) with it.
              RepaintBoundary(
                child: CustomPaint(
                  painter: _StadiumGeometryPainter(results: results),
                ),
              ),
              // Trails and particles share the one clock, so the whole
              // atmosphere is a single ticker no matter how many layers it
              // has. A null clock paints the static Stage 2 composition.
              RepaintBoundary(
                child: _Drifting(
                  clock: _clock,
                  builder: (t) => CustomPaint(
                    painter: _EnergyTrailPainter(results: results, drift: t),
                  ),
                ),
              ),
              RepaintBoundary(
                child: _Drifting(
                  clock: _clock,
                  builder: (t) => CustomPaint(
                    painter: _ParticlePainter(drift: t),
                  ),
                ),
              ),
              if (goldFocus)
                RepaintBoundary(
                  child: CustomPaint(
                    painter: _GoldAtmospherePainter(alignment: goldAlignment),
                  ),
                ),
              RepaintBoundary(
                child: CustomPaint(painter: const _VignettePainter()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rebuilds its child against the shared ambient clock, or once at rest when
/// there is no clock (reduced motion / animation disabled).
class _Drifting extends StatelessWidget {
  const _Drifting({required this.clock, required this.builder});

  final AnimationController? clock;
  final Widget Function(double t) builder;

  @override
  Widget build(BuildContext context) {
    final c = clock;
    if (c == null) return builder(0);
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) => builder(c.value),
    );
  }
}

/// Very low-contrast pitch geometry — a centre circle, halfway line and two
/// penalty arcs, drawn large and cropped so it reads as architecture rather
/// than a diagram of a football pitch.
class _StadiumGeometryPainter extends CustomPainter {
  const _StadiumGeometryPainter({required this.results});

  final bool results;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = HETheme.pfAccentViolet.withValues(alpha: results ? 0.10 : 0.13);

    final cx = size.width * (results ? 0.5 : 0.5);
    final cy = size.height * (results ? 0.30 : 0.42);
    final r = size.shortestSide * 0.42;

    canvas.drawCircle(Offset(cx, cy), r, paint);
    canvas.drawCircle(Offset(cx, cy), r * 0.42, paint);

    // Halfway line, held even fainter than the circles.
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = HETheme.pfAccentViolet.withValues(alpha: 0.075);
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), line);

    // Two penalty-box arcs entering from the sides.
    final arcRect = Rect.fromCircle(
      center: Offset(-size.width * 0.18, size.height * 0.78),
      radius: size.shortestSide * 0.34,
    );
    canvas.drawArc(arcRect, -math.pi / 2.4, math.pi / 1.7, false, line);
    canvas.drawArc(
      arcRect.shift(Offset(size.width * 1.36, -size.height * 0.52)),
      math.pi / 1.9,
      math.pi / 1.7,
      false,
      line,
    );
  }

  @override
  bool shouldRepaint(_StadiumGeometryPainter old) => old.results != results;
}

/// Two broad diagonal light bands — the "energy trails". Directional, soft,
/// and low alpha: they give the composition a diagonal grain without ever
/// becoming a shape the eye tries to read.
class _EnergyTrailPainter extends CustomPainter {
  const _EnergyTrailPainter({required this.results, this.drift = 0});

  final bool results;

  /// 0 → 1 across one ambient cycle. Each band sweeps slowly across the
  /// canvas and wraps, so the light direction is always shifting without any
  /// element ever appearing to "move" while you look at it.
  final double drift;

  @override
  void paint(Canvas canvas, Size size) {
    // The two bands travel at different rates and in opposite directions, so
    // the composition never repeats on a visible beat.
    _band(
      canvas,
      size,
      startX: -0.15 + drift * 0.5,
      width: 0.34,
      color: HETheme.pfAccentViolet,
      alpha: results ? 0.16 : 0.22,
    );
    _band(
      canvas,
      size,
      startX: 0.62 - drift * 0.35,
      width: 0.26,
      color: results ? HETheme.pfSecondaryViolet : HETheme.pfAccentVioletGlow,
      alpha: results ? 0.13 : 0.17,
    );
  }

  void _band(
    Canvas canvas,
    Size size, {
    required double startX,
    required double width,
    required Color color,
    required double alpha,
  }) {
    // A parallelogram sheared across the canvas — the diagonal light
    // direction the whole composition leans on.
    final x0 = size.width * startX;
    final w = size.width * width;
    final skew = size.width * 0.28;

    final path = Path()
      ..moveTo(x0, 0)
      ..lineTo(x0 + w, 0)
      ..lineTo(x0 + w - skew, size.height)
      ..lineTo(x0 - skew, size.height)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: alpha * 0.25),
            color.withValues(alpha: 0),
          ],
        ).createShader(Offset.zero & size)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 42),
    );
  }

  @override
  bool shouldRepaint(_EnergyTrailPainter old) => old.results != results;
}

/// Sparse dust caught in the light. Fixed seed, fixed count, no motion.
class _ParticlePainter extends CustomPainter {
  const _ParticlePainter({this.drift = 0});

  /// 0 → 1 across one ambient cycle. Particles rise slowly and wrap, each at
  /// its own rate, so they read as dust in the air rather than a field of
  /// synchronised dots.
  final double drift;

  @override
  void paint(Canvas canvas, Size size) {
    // Deterministic seed: the same particles every build, so nothing twitches
    // or reshuffles between rebuilds — only `drift` moves them.
    final rand = math.Random(20240917);
    final paint = Paint();

    for (var i = 0; i < EventAtmosphereBackground.kMaxParticles; i++) {
      final dx = rand.nextDouble() * size.width;
      final baseY = rand.nextDouble();
      final r = 0.8 + rand.nextDouble() * 1.6;
      final a = 0.14 + rand.nextDouble() * 0.16;
      // Per-particle rate, so they never travel as a block.
      final rate = 0.35 + rand.nextDouble() * 0.65;
      final dy = ((baseY - drift * rate) % 1.0 + 1.0) % 1.0 * size.height;

      paint.color = (i.isEven ? HETheme.pfAccentVioletGlow : HETheme.pfLavenderText)
          .withValues(alpha: a);
      canvas.drawCircle(Offset(dx, dy), r, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.drift != drift;
}

/// The reserved gold atmosphere. Only ever painted where achievement actually
/// happens — the final, the champion, the winner hero, rank one.
class _GoldAtmospherePainter extends CustomPainter {
  const _GoldAtmospherePainter({required this.alignment});

  final Alignment alignment;

  @override
  void paint(Canvas canvas, Size size) {
    final center = alignment.alongSize(size);
    final radius = size.shortestSide * 0.55;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            HETheme.pfGold.withValues(alpha: 0.13),
            HETheme.pfGold.withValues(alpha: 0.05),
            HETheme.pfGold.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_GoldAtmospherePainter old) =>
      old.alignment != alignment;
}

/// Outer falloff, so attention settles toward the middle of the screen.
class _VignettePainter extends CustomPainter {
  const _VignettePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.95,
          colors: [
            HETheme.pfBgVoid.withValues(alpha: 0),
            HETheme.pfBgVoid.withValues(alpha: 0.45),
          ],
          stops: const [0.62, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_VignettePainter old) => false;
}
