import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';

/// The reusable visual foundation for the First Touch Experience screens
/// (Home, Host Room, Join Room, Lobby) — "entering a football club's
/// scouting room under floodlights before matchday." Keeps the app's
/// existing cyan/gold/emerald palette; this is a stronger, more visibly
/// premium, and more visibly *alive* execution of the same colors, not a
/// new color system.
///
/// Layered: a lighter, more visible vertical gradient base, two floodlight
/// beams with a slow ambient "breathe," a brighter stadium halo behind
/// whatever sits at [haloAlignment], a handful of small gently-drifting
/// football/pitch-marker shapes for a "live game" feel, sparse pitch-line
/// geometry, and a light vignette that keeps focus centered without
/// darkening the scene back down.
///
/// Reads `MediaQuery.of(context).disableAnimations` itself — every existing
/// call site (`const MatchdayBackground()`) keeps working unchanged; no
/// `AnimationController` is constructed at all when motion is reduced, not
/// merely paused. Under reduced motion the floating shapes still render
/// (visual friendliness, not a "wow" animation) but hold still.
class MatchdayBackground extends StatefulWidget {
  const MatchdayBackground({
    super.key,
    this.showClassifiedGlow = false,
    this.haloAlignment = Alignment.topCenter,
    this.showShapes = true,
    this.dim = false,
  });

  /// A restrained gold radial hint, off by default. Only ever turn this on
  /// behind content with real "classified/hidden/reveal" meaning (e.g.
  /// Home's Hidden Picks chip) — never as decoration, per the semantic-color
  /// rule the rest of the app already follows for gold.
  final bool showClassifiedGlow;

  /// Where the brighter stadium-halo glow centers — behind a logo, a
  /// room-code hero, whatever this screen's one focal point is. Null omits
  /// the halo layer entirely.
  final Alignment? haloAlignment;

  /// Whether the drifting football/strategy shapes render at all. Off for
  /// screens with dense, attention-critical foreground content (live
  /// gameplay) where extra motion would compete with reading the pitch and
  /// the clock rather than just adding warmth.
  final bool showShapes;

  /// A calmer, lower-contrast pass for busy foreground screens — pulls the
  /// floodlight beams and vignette back so the background stays felt, not
  /// seen, behind dense UI.
  final bool dim;

  @override
  State<MatchdayBackground> createState() => _MatchdayBackgroundState();
}

class _MatchdayBackgroundState extends State<MatchdayBackground>
    with TickerProviderStateMixin {
  AnimationController? _breathe;
  AnimationController? _drift;
  AnimationController? _lineGlow;
  bool _checked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    if (!MediaQuery.of(context).disableAnimations) {
      _breathe = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 9),
      )..repeat(reverse: true);
      // A separate, slower, non-reversing cycle for the floating shapes so
      // they drift on their own rhythm rather than in lockstep with the
      // floodlight pulse — reads as organic, not mechanically synced.
      _drift = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 22),
      )..repeat();
      // The pitch halfway-line's periodic glow sweep — see
      // `_MatchdayPitchLinesPainter`'s doc comment for the envelope this
      // drives (a bright pulse travels the line, then it rests).
      _lineGlow = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 7),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _breathe?.dispose();
    _drift?.dispose();
    _lineGlow?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Base — noticeably lighter at the top (where the light source
          // reads as coming from) settling to the app's normal dark surface
          // toward the bottom, so the screen doesn't read as flat black.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF16233C), HETheme.pfBgVoid],
                stops: [0.0, 0.75],
              ),
            ),
          ),

          // Floodlight beams — brighter than before, isolated in their own
          // RepaintBoundary so the breathe never repaints anything else.
          RepaintBoundary(
            child: _breathe == null
                ? _FloodlightBeams(breathe: 0.5, dim: widget.dim)
                : AnimatedBuilder(
                    animation: _breathe!,
                    builder: (context, _) => _FloodlightBeams(
                      breathe: _breathe!.value,
                      dim: widget.dim,
                    ),
                  ),
          ),

          if (widget.haloAlignment != null)
            Align(
              alignment: widget.haloAlignment!,
              child: const _StadiumHalo(),
            ),

          if (widget.showClassifiedGlow)
            const Positioned(
              bottom: -140,
              right: -100,
              child: _Beam(color: HETheme.pfGold, baseAlpha: 0.12),
            ),

          // Friendly floating shapes — a handful of small ball/pitch-marker
          // outlines that gently bob and drift, giving the screen a "live
          // game" feel. Held still (no bobbing) under reduced motion, but
          // still present — this is about warmth, not a motion effect.
          if (widget.showShapes)
            RepaintBoundary(
              child: _drift == null
                  ? const _FloatingShapes(t: 0)
                  : AnimatedBuilder(
                      animation: _drift!,
                      builder: (context, _) =>
                          _FloatingShapes(t: _drift!.value),
                    ),
            ),

          // Sparse pitch-line geometry — a suggestion, not a diagram. The
          // line periodically catches a bright traveling glow, then rests.
          Positioned.fill(
            child: RepaintBoundary(
              child: _lineGlow == null
                  ? const CustomPaint(
                      painter: _MatchdayPitchLinesPainter(glowT: null),
                    )
                  : AnimatedBuilder(
                      animation: _lineGlow!,
                      builder: (context, _) => CustomPaint(
                        painter: _MatchdayPitchLinesPainter(
                          glowT: _lineGlow!.value,
                        ),
                      ),
                    ),
            ),
          ),

          // Vignette — much lighter than before: just enough to keep the
          // very corners grounded without darkening the scene back down.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.25,
                colors: [
                  Colors.transparent,
                  Color(widget.dim ? 0x59000000 : 0x33000000),
                ],
                stops: const [0.7, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FloodlightBeams extends StatelessWidget {
  const _FloodlightBeams({required this.breathe, this.dim = false});

  /// 0..1 animation progress (0.5 = static/no controller).
  final double breathe;

  /// Pulls both beams back to roughly half brightness for busy foreground
  /// screens (see `MatchdayBackground.dim`).
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final swing = 1.0 + (breathe - 0.5) * 0.12;
    final falloff = dim ? 0.55 : 1.0;
    return Stack(
      children: [
        Positioned(
          top: -160,
          left: -120,
          child: _Beam(
            color: HETheme.pfAccentViolet,
            baseAlpha: 0.30 * falloff,
            swing: swing,
          ),
        ),
        Positioned(
          top: -200,
          right: -150,
          child: _Beam(
            color: HETheme.pfAccentViolet,
            baseAlpha: 0.22 * falloff,
            swing: swing,
          ),
        ),
      ],
    );
  }
}

class _Beam extends StatelessWidget {
  const _Beam({required this.color, required this.baseAlpha, this.swing = 1.0});

  final Color color;
  final double baseAlpha;
  final double swing;

  @override
  Widget build(BuildContext context) {
    final alpha = (baseAlpha * swing).clamp(0.0, 1.0);
    return Container(
      width: 620,
      height: 620,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

/// A brighter, tighter static glow behind whatever the screen's one focal
/// point is (logo, room code, hero header). Not tied to the breathe cycle —
/// reads as "the thing being lit," not part of the ambient sky.
class _StadiumHalo extends StatelessWidget {
  const _StadiumHalo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 460,
      height: 460,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            HETheme.pfAccentViolet.withValues(alpha: 0.22),
            HETheme.pfAccentViolet.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }
}

/// One drifting shape's fixed orbit data — a center point and radii (all as
/// fractions of the available size) that define an elliptical path, plus a
/// phase offset and speed multiplier so shapes travel their own paths
/// rather than bobbing in place or moving in lockstep. `icon`/`color` pick
/// its football/strategy identity.
class _ShapeSpec {
  const _ShapeSpec({
    required this.cx,
    required this.cy,
    required this.rx,
    required this.ry,
    required this.phase,
    required this.speed,
    required this.icon,
    required this.color,
    required this.size,
  });

  final double cx;
  final double cy;
  final double rx;
  final double ry;
  final double phase;

  /// Relative speed multiplier — each shape completes its own loop of the
  /// shared drift cycle at a different rate, so paths don't stay in sync.
  final double speed;
  final IconData icon;
  final Color color;
  final double size;
}

// Icons chosen for football/tactics identity rather than generic dots:
// a ball, a trophy, a tactical target/marker, a corner flag, and a
// stopwatch for the match clock — each on its own slow elliptical orbit.
const _shapeSpecs = [
  _ShapeSpec(
    cx: 0.14,
    cy: 0.20,
    rx: 0.05,
    ry: 0.05,
    phase: 0.0,
    speed: 1.0,
    icon: Icons.sports_soccer_rounded,
    color: HETheme.pfAccentViolet,
    size: 22,
  ),
  _ShapeSpec(
    cx: 0.87,
    cy: 0.18,
    rx: 0.04,
    ry: 0.06,
    phase: 0.35,
    speed: 0.7,
    icon: Icons.emoji_events_rounded,
    color: HETheme.pfGold,
    size: 18,
  ),
  _ShapeSpec(
    cx: 0.18,
    cy: 0.66,
    rx: 0.06,
    ry: 0.04,
    phase: 0.6,
    speed: 0.85,
    icon: Icons.gps_fixed_rounded,
    color: HETheme.pfSuccess,
    size: 16,
  ),
  _ShapeSpec(
    cx: 0.80,
    cy: 0.72,
    rx: 0.05,
    ry: 0.05,
    phase: 0.15,
    speed: 1.15,
    icon: Icons.flag_rounded,
    color: HETheme.pfAccentViolet,
    size: 18,
  ),
  _ShapeSpec(
    cx: 0.50,
    cy: 0.08,
    rx: 0.07,
    ry: 0.03,
    phase: 0.5,
    speed: 0.6,
    icon: Icons.timer_outlined,
    color: HETheme.pfAccentViolet,
    size: 16,
  ),
  _ShapeSpec(
    cx: 0.60,
    cy: 0.50,
    rx: 0.06,
    ry: 0.06,
    phase: 0.8,
    speed: 0.9,
    icon: Icons.shield_outlined,
    color: HETheme.pfGold,
    size: 16,
  ),
];

/// A handful of small, low-opacity football/tactics icons that each travel
/// their own slow elliptical path — a "friendly, alive" ambient touch,
/// deliberately not a particle system (fixed count, fixed paths, no
/// spawning/despawning).
class _FloatingShapes extends StatelessWidget {
  const _FloatingShapes({required this.t});

  /// 0..1 drift-cycle progress (0 = static positions, no motion).
  final double t;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth.isFinite ? box.maxWidth : 400.0;
        final h = box.maxHeight.isFinite ? box.maxHeight : 800.0;
        return Stack(
          children: [
            for (final spec in _shapeSpecs)
              Builder(
                builder: (context) {
                  final angle = (t * spec.speed + spec.phase) * 2 * math.pi;
                  final left =
                      (spec.cx + spec.rx * math.cos(angle)) * w - spec.size / 2;
                  final top =
                      (spec.cy + spec.ry * math.sin(angle)) * h - spec.size / 2;
                  return Positioned(
                    left: left,
                    top: top,
                    child: Icon(
                      spec.icon,
                      size: spec.size,
                      color: spec.color.withValues(alpha: 0.20),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

/// Sparse halfway-line + center-circle motif, low in the frame — a
/// suggestion of a pitch, not a literal diagram.
///
/// [glowT] drives a bright comet-tail arc that continuously travels around
/// the center circle's circumference (a `SweepGradient` rotated by [glowT],
/// which loops 0→1 forever) — "the circle drawn in the background" catching
/// a traveling glow, rather than a pulse on the straight halfway line.
/// `glowT: null` (reduced motion, or no controller) paints the circle at
/// its constant resting brightness with no traveling glow at all.
class _MatchdayPitchLinesPainter extends CustomPainter {
  const _MatchdayPitchLinesPainter({required this.glowT});

  final double? glowT;

  @override
  void paint(Canvas canvas, Size size) {
    final restingLine = Paint()
      ..color = HETheme.pfAccentViolet.withValues(alpha: 0.10)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final y = size.height * 0.84;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), restingLine);

    final center = Offset(size.width / 2, y);
    final r = size.width * 0.24;
    canvas.drawCircle(center, r, restingLine);

    final dot = Paint()
      ..color = HETheme.pfAccentViolet.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 2.0, dot);

    final t = glowT;
    if (t == null) return;

    // A short bright comet-tail that continuously orbits the circle —
    // sharp at its leading edge, fading out along the trailing arc, rather
    // than an even glow around the whole ring.
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..shader = SweepGradient(
        transform: GradientRotation(t * 2 * math.pi),
        colors: [
          HETheme.pfAccentViolet.withValues(alpha: 0.0),
          HETheme.pfAccentViolet.withValues(alpha: 0.0),
          HETheme.pfAccentViolet.withValues(alpha: 0.65),
          HETheme.pfAccentViolet.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.78, 0.92, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: r));

    canvas.drawCircle(center, r, glowPaint);
  }

  @override
  bool shouldRepaint(_MatchdayPitchLinesPainter oldDelegate) =>
      oldDelegate.glowT != glowT;
}
