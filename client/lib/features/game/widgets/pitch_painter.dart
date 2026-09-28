import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';

/// Paints the football pitch under Night Tactics: a floodlit tactical field
/// rather than the flat two-tone diagram this used to draw.
///
/// What changed, and why:
///   * **Turf** is a vertical gradient with softly *feathered* stripe bands,
///     instead of eight hard-edged rectangles two shades apart. Hard edges
///     and a 2% luminance step are most of why the old pitch read as a
///     technical diagram.
///   * **Lines** are drawn in two passes — a wide, very low-alpha glow
///     underneath and a crisp 1px stroke on top — so chalk reads as chalk
///     lit by a stadium light.
///   * **A violet light wash** is composited over the turf from above. This
///     is the integration trick of the whole art direction: the pitch is lit
///     by the *same* floodlight as the arena behind it, so it belongs to the
///     room instead of sitting on top of it.
///   * **The centre circle catches a slow travelling highlight**, driven by
///     the shared [ArenaClock] rather than a controller of its own.
///
/// Field geometry — every inset, radius and box dimension below — is
/// unchanged from the original painter. Nothing here moves a line, and
/// nothing here knows anything about slots or cards.
class PitchPainter extends CustomPainter {
  const PitchPainter({this.lightT});

  /// The shared 0..1 ambient clock, or null under reduced motion (in which
  /// case the centre-circle highlight simply isn't drawn and everything else
  /// renders identically).
  final double? lightT;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    _paintTurf(canvas, w, h);
    _paintLines(canvas, w, h);
    _paintLightWash(canvas, w, h);
  }

  // ── Turf ──────────────────────────────────────────────────────────────────

  void _paintTurf(Canvas canvas, double w, double h) {
    final full = Rect.fromLTWH(0, 0, w, h);

    // Base gradient — brighter at the top, matching where the arena's key
    // light sits, so the pitch has depth before a single stripe is drawn.
    canvas.drawRect(
      full,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [HETheme.pitchTurfLit, HETheme.pitchTurfDeep],
        ).createShader(full),
    );

    // Mow stripes as feathered bands. Each band fades in and out across its
    // own height rather than butting hard against its neighbour — the same
    // eight stripes as before, just no longer looking like a bar chart.
    const stripes = 8;
    final stripeH = h / stripes;
    for (var i = 0; i < stripes; i++) {
      if (i.isEven) continue;
      final rect = Rect.fromLTWH(0, i * stripeH, w, stripeH);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              HETheme.pitchTurfLit.withValues(alpha: 0),
              HETheme.pitchTurfLit.withValues(alpha: 0.55),
              HETheme.pitchTurfLit.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(rect),
      );
    }
  }

  // ── Field markings ────────────────────────────────────────────────────────

  void _paintLines(Canvas canvas, double w, double h) {
    // Geometry constants — identical to the original painter.
    const hInset = 0.045;
    const vInset = 0.022;
    final px = w * hInset;
    final py = h * vInset;
    final fw = w * (1 - 2 * hInset);
    final fh = h * (1 - 2 * vInset);
    final midY = h / 2;
    final circleR = fw * 0.155;

    // Two-pass stroke: a wide soft glow, then the crisp line on top.
    void strokes(void Function(Paint p) draw) {
      draw(
        Paint()
          ..color = HETheme.pitchLine.withValues(alpha: 0.06)
          ..strokeWidth = 3.0
          ..style = PaintingStyle.stroke,
      );
      draw(
        Paint()
          ..color = HETheme.pitchLine.withValues(alpha: 0.30)
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke,
      );
    }

    final dot = Paint()
      ..color = HETheme.pitchLine.withValues(alpha: 0.38)
      ..style = PaintingStyle.fill;

    // Outline, halfway line, centre circle.
    strokes((p) => canvas.drawRect(Rect.fromLTWH(px, py, fw, fh), p));
    strokes((p) => canvas.drawLine(Offset(px, midY), Offset(px + fw, midY), p));
    strokes((p) => canvas.drawCircle(Offset(w / 2, midY), circleR, p));
    canvas.drawCircle(Offset(w / 2, midY), 2.5, dot);

    // Penalty areas.
    final penW = fw * 0.56;
    final penH = fh * 0.15;
    final penLeft = (w - penW) / 2;
    strokes(
      (p) => canvas.drawRect(
        Rect.fromLTWH(penLeft, py + fh - penH, penW, penH),
        p,
      ),
    );
    strokes((p) => canvas.drawRect(Rect.fromLTWH(penLeft, py, penW, penH), p));

    // 6-yard boxes.
    final boxW = fw * 0.265;
    final boxH = fh * 0.065;
    final boxLeft = (w - boxW) / 2;
    strokes(
      (p) => canvas.drawRect(
        Rect.fromLTWH(boxLeft, py + fh - boxH, boxW, boxH),
        p,
      ),
    );
    strokes((p) => canvas.drawRect(Rect.fromLTWH(boxLeft, py, boxW, boxH), p));

    // Penalty spots.
    canvas.drawCircle(Offset(w / 2, py + fh - penH * 0.38), 2.0, dot);
    canvas.drawCircle(Offset(w / 2, py + penH * 0.38), 2.0, dot);

    // Corner arcs.
    final cr = fw * 0.042;
    final corners = <(Offset, double)>[
      (Offset(px, py), 0),
      (Offset(px + fw, py), math.pi / 2),
      (Offset(px + fw, py + fh), math.pi),
      (Offset(px, py + fh), 3 * math.pi / 2),
    ];
    for (final (center, startAngle) in corners) {
      strokes(
        (p) => canvas.drawArc(
          Rect.fromCircle(center: center, radius: cr),
          startAngle,
          math.pi / 2,
          false,
          p,
        ),
      );
    }

    _paintCircleSweep(canvas, Offset(w / 2, midY), circleR);
  }

  /// A single bright highlight travelling the centre circle — the pitch's
  /// share of the arena's ambient life. Uses the same comet-tail sweep
  /// technique as the entry screens' background, so the two screens read as
  /// one visual system.
  void _paintCircleSweep(Canvas canvas, Offset center, double r) {
    final t = lightT;
    if (t == null) return;

    final rect = Rect.fromCircle(center: center, radius: r);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..shader = SweepGradient(
          transform: GradientRotation(t * 2 * math.pi),
          colors: [
            HETheme.pfAccentVioletGlow.withValues(alpha: 0),
            HETheme.pfAccentVioletGlow.withValues(alpha: 0),
            HETheme.pfAccentVioletGlow.withValues(alpha: 0.70),
            HETheme.pfAccentVioletGlow.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.76, 0.92, 1.0],
        ).createShader(rect),
    );
  }

  // ── Floodlight wash ───────────────────────────────────────────────────────

  /// The layer that makes the pitch belong to the arena: a violet radial
  /// falling from above, exactly as the background's floodlights do.
  void _paintLightWash(Canvas canvas, double w, double h) {
    final rect = Rect.fromLTWH(0, 0, w, h);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.75),
          radius: 1.15,
          colors: [
            HETheme.arenaLightWash.withValues(alpha: 0.22),
            HETheme.arenaLightWash.withValues(alpha: 0.10),
            HETheme.pfBgVoid.withValues(alpha: 0.18),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(PitchPainter old) => old.lightT != lightT;
}
