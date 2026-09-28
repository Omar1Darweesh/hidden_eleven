import 'package:flutter/material.dart';

import 'package:hidden_eleven/app/he_theme.dart';

/// One controlled hexagonal rank marker used everywhere a placement (1st,
/// 2nd, 3rd, 4th+) needs to be shown — Results standings, the winner hero,
/// and Tournament brackets/complete screens. Always shows the numeral, never
/// a medal emoji, so the meaning doesn't depend on the platform's emoji font.
///
/// Visual language borrowed from the private `_RankMedallion`/`_HexPainter`
/// pair in `tactical_order_sheet.dart` (a flat-top hex with a centered
/// digit) — extracted here as a public, rank-tier-aware widget since that
/// pair is single-color and scoped to reorder animation, not reusable
/// as-is.
class RankMedallion extends StatelessWidget {
  const RankMedallion({super.key, required this.rank, this.size = 28});

  final int rank;
  final double size;

  Color get _fill => switch (rank) {
    1 => HETheme.pfGold,
    2 => HETheme.pfLavenderText,
    3 => HETheme.pfBronze,
    _ => HETheme.pfSecondaryViolet,
  };

  Color get _digitColor => switch (rank) {
    1 => HETheme.pfGold,
    2 => HETheme.pfLavenderText,
    3 => HETheme.pfBronze,
    _ => HETheme.pfTextSecondary,
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Rank $rank',
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _HexPainter(fill: _fill),
          child: Center(
            child: Text(
              '$rank',
              style: HETheme.mono(
                size: size * 0.42,
                weight: FontWeight.w800,
                color: _digitColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HexPainter extends CustomPainter {
  const _HexPainter({required this.fill});

  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.25, h * 0.06)
      ..lineTo(w * 0.75, h * 0.06)
      ..lineTo(w * 0.98, h * 0.5)
      ..lineTo(w * 0.75, h * 0.94)
      ..lineTo(w * 0.25, h * 0.94)
      ..lineTo(w * 0.02, h * 0.5)
      ..close();

    canvas.drawPath(path, Paint()..color = fill.withValues(alpha: 0.18));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = fill.withValues(alpha: 0.65),
    );
  }

  @override
  bool shouldRepaint(_HexPainter oldDelegate) => oldDelegate.fill != fill;
}
