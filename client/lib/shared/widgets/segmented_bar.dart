import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_motion.dart';
import 'package:hidden_eleven/app/he_theme.dart';

/// One labeled, colored contribution to a [SegmentedBar].
///
/// A segment with [value] <= 0 draws no width in the bar itself (a negative
/// or zero contribution can't size a proportional segment) but still appears
/// in the legend with its true value — nothing is hidden, it just contributes
/// zero width. This mirrors the rule `ScoreBreakdownBar` already established
/// before this widget was extracted from it.
class BarSegment {
  const BarSegment({
    required this.label,
    required this.color,
    required this.value,
  });

  final String label;
  final Color color;
  final int value;
}

/// A horizontal stacked bar with labeled, colored segments sized
/// proportionally to their value, plus a legend row underneath (colored dot +
/// label + signed value per segment) — so segment meaning is never carried by
/// color alone.
///
/// Generic — extracted from `ScoreBreakdownBar` (which now builds its fixed
/// four segments and hands them here) so a second, differently-shaped
/// breakdown (the tournament Points Breakdown) can reuse the exact same bar
/// drawing and legend logic instead of duplicating it.
class SegmentedBar extends StatefulWidget {
  const SegmentedBar({
    super.key,
    required this.segments,
    this.height = 22,
    this.fillOnce = false,
  });

  final List<BarSegment> segments;
  final double height;

  /// R4: when true, the drawn bar wipes in from the left once on first
  /// appearance.
  ///
  /// Defaults to **false** so every existing caller — `ScoreBreakdownBar`
  /// above all — keeps its exact current behaviour and test coverage. Only
  /// the Points Breakdown opts in.
  ///
  /// The legend below the bar is never animated: labels and values are the
  /// information, and they render in full on the first frame regardless.
  final bool fillOnce;

  @override
  State<SegmentedBar> createState() => _SegmentedBarState();
}

class _SegmentedBarState extends State<SegmentedBar>
    with SingleTickerProviderStateMixin {
  AnimationController? _fill;
  bool _played = false;

  List<BarSegment> get segments => widget.segments;
  double get height => widget.height;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.fillOnce || _played) return;
    // Runs once for the life of this bar: a rebuild from a provider update or
    // a tab switch re-renders it already full.
    _played = true;
    if (HEMotion.reduced(context)) return;
    _fill = AnimationController(vsync: this, duration: HEMotion.entrance)
      ..forward();
  }

  @override
  void dispose() {
    _fill?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Negative/zero contributions can't size a bar segment — only positive
    // contributions are drawn in the bar itself; the true value (including
    // negative) is still shown in the legend so nothing is hidden.
    final positiveValues = segments.map((s) => s.value < 0 ? 0 : s.value).toList();
    final total = positiveValues.fold<int>(0, (a, b) => a + b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(HETheme.radiusSm),
          child: SizedBox(
            height: height,
            child: total <= 0
                // No positive contribution to show a shape for — an empty
                // track still communicates "nothing yet" rather than
                // rendering a zero-height, invisible bar.
                ? Container(color: HETheme.pfSurfaceRaised)
                : _maybeFilled(
                    Row(
                      children: [
                        for (var i = 0; i < segments.length; i++)
                          if (positiveValues[i] > 0)
                            Expanded(
                              flex: positiveValues[i],
                              child: ColoredBox(color: segments[i].color),
                            ),
                      ],
                    ),
                  ),
          ),
        ),
        const SizedBox(height: HETheme.spaceSm),
        Wrap(
          spacing: HETheme.spaceMd,
          runSpacing: 4,
          children: [
            for (final s in segments)
              _LegendEntry(color: s.color, label: s.label, value: s.value),
          ],
        ),
      ],
    );
  }

  /// Wraps the drawn bar in R4's one-shot left-to-right wipe, or returns it
  /// untouched when there is nothing to animate (opt-out callers, reduced
  /// motion, or an already-completed fill).
  Widget _maybeFilled(Widget bar) {
    final controller = _fill;
    if (controller == null) return bar;

    // Clips the *painting*, not the layout: the Row keeps its full width and
    // its Expanded children keep bounded constraints throughout. Sizing the
    // bar down instead (Align's widthFactor, FractionallySizedBox) would hand
    // the Row unbounded width and throw.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) => ClipRect(
          clipper: _WipeClipper(
            HEMotion.easeOut.transform(controller.value).clamp(0.0, 1.0),
          ),
          child: child,
        ),
        child: bar,
      ),
    );
  }
}

/// Reveals the bar from the left as [fraction] goes 0 → 1.
class _WipeClipper extends CustomClipper<Rect> {
  const _WipeClipper(this.fraction);

  final double fraction;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_WipeClipper old) => old.fraction != fraction;
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final sign = value > 0 ? '+' : '';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: HETheme.body(size: 11.5, color: HETheme.pfTextSecondary),
        ),
        const SizedBox(width: 4),
        Text(
          '$sign$value',
          style: HETheme.mono(
            size: 11.5,
            weight: FontWeight.w700,
            color: HETheme.pfTextPrimary,
          ),
        ),
      ],
    );
  }
}
