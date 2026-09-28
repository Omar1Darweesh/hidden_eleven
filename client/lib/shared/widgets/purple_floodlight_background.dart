import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';

/// "Purple Floodlights" — the visual foundation for the First Touch
/// Experience screens: a tactical football game played under violet and
/// magenta stadium floodlights at night.
///
/// Layered, bottom to top:
/// 1. Deep plum/near-black void base (a subtle vertical gradient, not flat).
/// 2. Two large soft-edged floodlight beams (violet + magenta) from
///    off-canvas top corners.
/// 3. A stadium halo — one more radial glow, positioned via [haloAlignment]
///    so callers can center it behind a logo, room code, or hero panel.
/// 4. Sparse perspective pitch/stadium-grid geometry (`CustomPainter`,
///    const, `shouldRepaint: false`).
/// 5. Vignette — darkens the edges so cards/text at the center stay the
///    obvious focal point.
///
/// Every layer above is static except the floodlight beams, which — only
/// when [animated] is true — slowly "breathe" in opacity via a single
/// `AnimationController`. No `AnimationController` is ever constructed when
/// [animated] is false, so static mode has zero ticker/animation cost, not
/// just a paused one. Callers should pass
/// `animated: !MediaQuery.of(context).disableAnimations` — this widget does
/// not read `MediaQuery` itself so it stays trivially testable without a
/// full widget tree.
///
/// `IgnorePointer`-wrapped throughout: this widget never intercepts taps,
/// and every alpha value below was chosen to stay legible behind
/// `HECard`/text/form-field surfaces painted on top of it.
class PurpleFloodlightBackground extends StatefulWidget {
  const PurpleFloodlightBackground({
    super.key,
    this.animated = true,
    this.haloAlignment,
  });

  /// Whether the floodlight-breathe animation runs. Pass
  /// `!MediaQuery.of(context).disableAnimations` from the call site.
  final bool animated;

  /// Where the stadium-halo glow centers, in the background's own
  /// coordinate space (e.g. `Alignment.topCenter` behind a logo,
  /// `Alignment.center` behind a room-code hero). Null omits the halo layer
  /// entirely — used when a screen doesn't have one obvious focal point.
  final Alignment? haloAlignment;

  @override
  State<PurpleFloodlightBackground> createState() =>
      _PurpleFloodlightBackgroundState();
}

class _PurpleFloodlightBackgroundState extends State<PurpleFloodlightBackground>
    with SingleTickerProviderStateMixin {
  AnimationController? _breatheController;

  @override
  void initState() {
    super.initState();
    if (widget.animated) _startBreathing();
  }

  @override
  void didUpdateWidget(covariant PurpleFloodlightBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animated && _breatheController == null) {
      _startBreathing();
    } else if (!widget.animated && _breatheController != null) {
      _breatheController!.dispose();
      _breatheController = null;
    }
  }

  void _startBreathing() {
    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _breatheController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Void base.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [HETheme.pfBgVoid, Color(0xFF0F0A1C)],
              ),
            ),
          ),

          // 2. Floodlight beams — the only animated layer, isolated behind
          // its own RepaintBoundary so breathing never repaints the static
          // layers around it.
          RepaintBoundary(
            child: _breatheController == null
                ? const _FloodlightBeams(breathe: 0)
                : AnimatedBuilder(
                    animation: _breatheController!,
                    builder: (context, _) =>
                        _FloodlightBeams(breathe: _breatheController!.value),
                  ),
          ),

          // 3. Stadium halo.
          if (widget.haloAlignment != null)
            Align(
              alignment: widget.haloAlignment!,
              child: const _StadiumHalo(),
            ),

          // 4. Sparse pitch/stadium geometry.
          const Positioned.fill(
            child: CustomPaint(painter: _StadiumGeometryPainter()),
          ),

          // 5. Vignette.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.1,
                colors: [Colors.transparent, Color(0x59000000)],
                stops: [0.55, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The two floodlight cones. [breathe] is 0..1 (the controller's raw value)
/// and drives only opacity — never position, blur, or hue — so the "light
/// is on and alive" read never becomes a distracting shift.
class _FloodlightBeams extends StatelessWidget {
  const _FloodlightBeams({required this.breathe});

  /// 0..1 animation progress; ignored (treated as 0) in static mode.
  final double breathe;

  @override
  Widget build(BuildContext context) {
    // ±4% opacity swing around each beam's base intensity.
    final swing = 1.0 + (breathe - 0.5) * 0.08;
    return Stack(
      children: [
        Positioned(
          top: -220,
          left: -160,
          child: _Beam(
            color: HETheme.pfAccentViolet,
            baseAlpha: 0.22,
            swing: swing,
          ),
        ),
        Positioned(
          top: -260,
          right: -180,
          child: _Beam(
            color: HETheme.pfAccentMagenta,
            baseAlpha: 0.14,
            swing: swing,
          ),
        ),
      ],
    );
  }
}

class _Beam extends StatelessWidget {
  const _Beam({
    required this.color,
    required this.baseAlpha,
    required this.swing,
  });

  final Color color;
  final double baseAlpha;
  final double swing;

  @override
  Widget build(BuildContext context) {
    final alpha = (baseAlpha * swing).clamp(0.0, 1.0);
    return Container(
      width: 700,
      height: 700,
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

/// A brighter, tighter glow behind whatever the screen's one focal point is
/// (logo, room code). Static — deliberately not tied to the breathe cycle,
/// so it reads as "the thing being lit," not part of the ambient sky.
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
            HETheme.pfAccentVioletGlow.withValues(alpha: 0.20),
            HETheme.pfAccentVioletGlow.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }
}

/// Sparse perspective pitch/stadium-bowl suggestion — a few converging
/// lines, felt rather than consciously seen. Same const/`shouldRepaint:
/// false` convention as the existing `PitchPainter`.
class _StadiumGeometryPainter extends CustomPainter {
  const _StadiumGeometryPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = HETheme.pfSecondaryViolet.withValues(alpha: 0.09)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;
    final horizon = h * 0.62;

    // A shallow halfway line + center circle, low in the frame.
    canvas.drawLine(Offset(0, horizon), Offset(w, horizon), line);
    canvas.drawCircle(Offset(w / 2, horizon), w * 0.20, line);

    // A few converging "stadium bowl" lines toward a vanishing point above
    // the frame, suggesting tiered stands without drawing them literally.
    final vanishing = Offset(w / 2, -h * 0.4);
    for (final dx in [-0.9, -0.45, 0.45, 0.9]) {
      canvas.drawLine(
        Offset(w / 2 + w * dx, h),
        vanishing,
        line..color = HETheme.pfSecondaryViolet.withValues(alpha: 0.05),
      );
    }
  }

  @override
  bool shouldRepaint(_StadiumGeometryPainter oldDelegate) => false;
}
