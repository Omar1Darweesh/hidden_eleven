import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';

/// Pure-rendering ring + tabular-mono numeral for a countdown, extracted
/// from [TurnTimerWidget]'s formerly-inline `_ArcPainter` — the ticking
/// timer, urgency-callback firing, and pulse-on-urgent behavior all stay in
/// [TurnTimerWidget] exactly as they were (already tested, already wired to
/// the pick-timeout sound). This widget only knows how to draw a given
/// `remaining` fraction; it owns no `Timer` of its own.
///
/// Color ramp matches the dossier (§7/§8): emerald while safe, gold in the
/// caution band, danger red under the last quarter — the same three-tier
/// urgency logic the app already used, retargeted to the Matchday
/// Intelligence hexes instead of the old green/orange/red.
class TimerRing extends StatelessWidget {
  const TimerRing({
    super.key,
    required this.remaining,
    required this.secondsLeft,
    this.muted = false,
    this.size,
    this.roundProgress,
  });

  /// Optional OUTER ring showing round progress (0..1), concentric with the
  /// turn timer.
  ///
  /// Under Night Tactics the mission card merges what used to be two
  /// separate readouts — a thin `LinearProgressIndicator` for the round and
  /// this ring for the turn — into one dial. Null keeps the original
  /// single-ring rendering exactly, so every existing call site (the result
  /// screen, the compact observer timer) is unaffected.
  final double? roundProgress;

  /// 0.0 (expired) .. 1.0 (full time remaining).
  final double remaining;

  /// Pre-computed whole-seconds-left for display — passed in rather than
  /// derived here, so this widget never needs to know the total duration.
  final int secondsLeft;

  /// Observer (not-your-turn) rendering: smaller, desaturated, no numeral.
  final bool muted;

  /// Overrides the default muted/active size if set.
  final double? size;

  Color get _fillColor {
    if (muted) return Colors.white.withValues(alpha: 0.25);
    if (remaining < 0.25) return HETheme.danger;
    if (remaining < 0.5) return HETheme.accentGold;
    return HETheme.accentEmerald;
  }

  Color get _trackColor {
    if (muted) return Colors.white.withValues(alpha: 0.06);
    return _fillColor.withValues(alpha: 0.20);
  }

  @override
  Widget build(BuildContext context) {
    final resolvedSize = size ?? (muted ? 28.0 : 44.0);
    final strokeWidth = muted ? 2.5 : 3.5;

    // With an outer round ring present the whole dial grows, and the timer
    // ring insets to sit concentrically inside it.
    final hasOuter = roundProgress != null;
    final outerSize = hasOuter ? resolvedSize + 14 : resolvedSize;

    return SizedBox(
      width: outerSize,
      height: outerSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (hasOuter)
            CustomPaint(
              size: Size(outerSize, outerSize),
              painter: _RingPainter(
                progress: roundProgress!.clamp(0.0, 1.0),
                trackColor: HETheme.pfSecondaryViolet.withValues(alpha: 0.28),
                fillColor: HETheme.pfAccentViolet,
                strokeWidth: 3.0,
              ),
            ),
          CustomPaint(
            size: Size(resolvedSize, resolvedSize),
            painter: _RingPainter(
              progress: remaining,
              trackColor: _trackColor,
              fillColor: _fillColor,
              strokeWidth: strokeWidth,
            ),
          ),
          if (!muted)
            Text(
              '$secondsLeft',
              style: HETheme.mono(
                size: resolvedSize * 0.3,
                weight: FontWeight.w800,
                color: _fillColor,
              ).copyWith(height: 1.0),
            ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.trackColor,
    required this.fillColor,
    required this.strokeWidth,
  });

  final double progress;
  final Color trackColor;
  final Color fillColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const startAngle = -math.pi / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, startAngle, math.pi * 2, false, trackPaint);
    canvas.drawArc(rect, startAngle, math.pi * 2 * progress, false, fillPaint);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.fillColor != fillColor;
}
