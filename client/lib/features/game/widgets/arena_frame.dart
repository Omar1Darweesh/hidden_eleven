import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_motion.dart';
import 'package:hidden_eleven/app/he_shape.dart';
import 'package:hidden_eleven/app/he_theme.dart';

/// The lit container the pitch sits inside.
///
/// Today's pitch is a `ClipRRect(14)` and nothing else — a bright green
/// rectangle sitting directly on the page, which is most of why it reads as
/// "a small image floating in empty darkness" rather than as the centrepiece
/// of a room. This wraps it in a rim-lit bezel so the pitch becomes an
/// *object*: recessed into a frame, edge-lit by the same violet floodlight
/// that lights the background, casting a real shadow.
///
/// Purely presentational. It adds a fixed [bezel] of padding around its
/// child and nothing else — it never changes the child's aspect ratio,
/// constraints or hit-testing, so `PitchView`'s internal geometry (and
/// therefore `pitchSlotCenter`, and therefore every chemistry line endpoint)
/// is bit-for-bit unaffected.
class ArenaFrame extends StatelessWidget {
  const ArenaFrame({super.key, required this.child, this.bezel = 14});

  final Widget child;

  /// Padding between the frame's outer edge and the pitch itself.
  ///
  /// **Do not budget for this directly** — use [totalInset], which also
  /// accounts for the border. See its doc comment for why.
  final double bezel;

  /// Stroke width of the rim-light border.
  static const double kBorderWidth = 1.5;

  /// The frame's FULL layout cost along one axis — the single source of
  /// truth callers must budget against.
  ///
  /// This exists because of a real bug: [Container] adds its decoration's
  /// `border.dimensions` to its explicit `padding`, so an `ArenaFrame` with
  /// `bezel: 14` and a 1.5px border consumes `14*2 + 1.5*2 = 31` per axis,
  /// not the 28 a caller would naively assume. The game screen's vertical
  /// chrome constant originally hard-coded `bezel * 2`, under-reporting by
  /// exactly 3px and producing a constant "BOTTOM OVERFLOWED BY 3.0 PIXELS"
  /// at every viewport height.
  ///
  /// Deriving the budget from here means the frame's cost and the layout's
  /// assumption about that cost can never drift apart again.
  /// `arena_frame_test.dart` locks the two together.
  static double totalInset(double bezel) => bezel * 2 + kBorderWidth * 2;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: HETheme.pfSurfaceDeep,
        borderRadius: HEShape.arena,
        boxShadow: [
          // Depth: the frame sits above the arena floor.
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.50),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
          // Edge light: a violet halo bleeding out of the frame, tying it to
          // the background's floodlights.
          BoxShadow(
            color: HETheme.pfAccentViolet.withValues(alpha: 0.22),
            blurRadius: 52,
            spreadRadius: -18,
          ),
        ],
      ),
      child: Container(
        padding: EdgeInsets.all(bezel),
        decoration: BoxDecoration(
          borderRadius: HEShape.arena,
          // A gradient border, not a flat one — the rim catches the light
          // more strongly at the top-left, where the arena's key light is.
          border: GradientBoxBorder(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                HETheme.pfAccentVioletGlow.withValues(alpha: 0.55),
                HETheme.arenaRim.withValues(alpha: 0.80),
                HETheme.pfAccentMagenta.withValues(alpha: 0.30),
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
            width: kBorderWidth,
          ),
        ),
        child: child,
      ),
    );
  }
}

/// A [BoxBorder] that strokes with a gradient instead of a solid colour.
///
/// Flutter has no built-in gradient border, and the usual workaround —
/// nesting a gradient-filled container behind an inset solid one — costs an
/// extra layer and gets the corner radii subtly wrong. Painting the stroke
/// directly is both cheaper and exact.
class GradientBoxBorder extends BoxBorder {
  const GradientBoxBorder({required this.gradient, this.width = 1.0});

  final Gradient gradient;
  final double width;

  @override
  BorderSide get top => BorderSide(width: width);

  @override
  BorderSide get bottom => BorderSide(width: width);

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(width);

  @override
  bool get isUniform => true;

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    BoxShape shape = BoxShape.rectangle,
    BorderRadius? borderRadius,
    TextDirection? textDirection,
  }) {
    final paint = Paint()
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..shader = gradient.createShader(rect);

    // Inset by half the stroke so the border sits inside the box rather than
    // straddling its edge — otherwise it visually overflows the clip.
    final inner = rect.deflate(width / 2);

    if (borderRadius != null) {
      canvas.drawRRect(borderRadius.toRRect(inner), paint);
    } else if (shape == BoxShape.circle) {
      canvas.drawCircle(inner.center, inner.shortestSide / 2, paint);
    } else {
      canvas.drawRect(inner, paint);
    }
  }

  @override
  ShapeBorder scale(double t) =>
      GradientBoxBorder(gradient: gradient, width: width * t);
}

/// A gentle scale + fade for the pitch on first build.
///
/// Self-contained and reduced-motion aware, like [HeroEntrance] on the entry
/// screens: no controller is constructed at all when motion is reduced, and
/// the child renders immediately at its settled size.
class ArenaEntrance extends StatefulWidget {
  const ArenaEntrance({super.key, required this.child, this.delay});

  final Widget child;

  /// Optional stagger, so the arena and the side panels can arrive in
  /// sequence rather than together.
  final Duration? delay;

  @override
  State<ArenaEntrance> createState() => _ArenaEntranceState();
}

class _ArenaEntranceState extends State<ArenaEntrance>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;
  bool _checked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    if (HEMotion.reduced(context)) return;

    final c = AnimationController(vsync: this, duration: HEMotion.entrance);
    _c = c;
    final delay = widget.delay;
    if (delay == null) {
      c.forward();
    } else {
      Future<void>.delayed(delay, () {
        if (mounted) c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return widget.child;

    final curved = CurvedAnimation(parent: c, curve: HEMotion.easeOut);
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
        child: widget.child,
      ),
    );
  }
}
