import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';

/// A "N of M ready" progress indicator — a circular progress ring (built on
/// the same hexagon-numeral motif [RankMedallion] establishes elsewhere in
/// the app) wrapping a plain "current/total" count. Static: no
/// [AnimationController], the ring simply paints at whatever [current]/[total]
/// is passed in — the caller (e.g. `EventPhaseBanner`'s ready-check body)
/// re-renders it as the shared ready-count changes.
///
/// Replaces a flat `LinearProgressIndicator` for the tournament ready-check
/// so "how many managers are ready" reads as one compact glance instead of a
/// thin bar plus a separate text line.
class HexProgressRing extends StatelessWidget {
  const HexProgressRing({
    super.key,
    required this.current,
    required this.total,
    required this.color,
    this.size = 40,
  });

  final int current;
  final int total;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fraction = total <= 0 ? 0.0 : (current / total).clamp(0.0, 1.0);
    return Semantics(
      label: '$current of $total ready',
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(size, size),
              painter: _RingPainter(fraction: fraction, color: color),
            ),
            Text(
              '$current/$total',
              style: HETheme.mono(
                size: size * 0.26,
                weight: FontWeight.w800,
                color: HETheme.pfTextPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - _strokeWidth) / 2;
    final track = Paint()
      ..color = HETheme.pfSurfaceRaised
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;
    canvas.drawCircle(center, radius, track);

    if (fraction <= 0) return;
    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5708, // -90deg — start at the top
      6.2832 * fraction, // 2*pi * fraction
      false,
      arc,
    );
  }

  static const _strokeWidth = 3.5;

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.color != color;
}
