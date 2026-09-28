import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_shape.dart';
import 'package:hidden_eleven/app/he_theme.dart';

/// One stop on the tournament's journey.
@immutable
class TournamentStage {
  const TournamentStage({required this.label, required this.done});

  final String label;

  /// Whether this stage is already behind the tournament.
  final bool done;
}

/// The tournament journey as a horizontal rail: Draw → Semis → Final Set →
/// Champion.
///
/// Turns "which round is it" into a story with a beginning and an end, so the
/// event reads as progressing rather than as a series of unrelated screens.
///
/// **Presentation only.** The stages and which one is current are computed by
/// the caller from tournament state that already exists; this widget draws
/// what it is handed and never derives, advances or infers progress. When the
/// caller cannot say which stage is current it passes `currentIndex: -1` and
/// the rail simply shows no current marker rather than inventing one.
class StageRail extends StatelessWidget {
  const StageRail({
    super.key,
    required this.stages,
    required this.currentIndex,
    this.compact = false,
  });

  final List<TournamentStage> stages;

  /// Index into [stages], or -1 when genuinely unknown.
  final int currentIndex;

  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (stages.isEmpty) return const SizedBox.shrink();

    final rail = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < stages.length; i++) ...[
          if (i > 0)
            _Connector(done: stages[i].done || i <= currentIndex),
          _StageNode(
            stage: stages[i],
            isCurrent: i == currentIndex,
            compact: compact,
          ),
        ],
      ],
    );

    return Semantics(
      label: _semantics,
      excludeSemantics: true,
      child: SingleChildScrollView(
        // At narrow widths the rail scrolls rather than compressing its
        // labels into unreadable stubs.
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: rail,
      ),
    );
  }

  String get _semantics {
    final current = (currentIndex >= 0 && currentIndex < stages.length)
        ? stages[currentIndex].label
        : null;
    final done = stages.where((s) => s.done).map((s) => s.label).join(', ');
    return [
      'Tournament progress',
      if (current != null) 'currently $current',
      if (done.isNotEmpty) 'completed: $done',
    ].join('. ');
  }
}

class _StageNode extends StatelessWidget {
  const _StageNode({
    required this.stage,
    required this.isCurrent,
    required this.compact,
  });

  final TournamentStage stage;
  final bool isCurrent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // Three visual ranks: current (violet, filled), done (quiet gold tick),
    // upcoming (muted outline). Never colour alone — done carries a tick and
    // current carries a filled marker.
    final Color color = isCurrent
        ? HETheme.pfAccentViolet
        : stage.done
        ? HETheme.pfGold
        : HETheme.pfTextMuted;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: isCurrent
            ? color.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: HEShape.pill,
        border: Border.all(
          color: color.withValues(alpha: isCurrent ? 0.55 : 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            stage.done
                ? Icons.check_rounded
                : isCurrent
                ? Icons.play_arrow_rounded
                : Icons.circle_outlined,
            size: compact ? 10 : 12,
            color: color,
          ),
          SizedBox(width: compact ? 4 : 5),
          Text(
            stage.label,
            style: TextStyle(
              color: isCurrent ? HETheme.pfTextPrimary : color,
              fontSize: compact ? 9.5 : 10.5,
              fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _Connector extends StatelessWidget {
  const _Connector({required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) => Container(
    width: 14,
    height: 1.5,
    margin: const EdgeInsets.symmetric(horizontal: 3),
    color: (done ? HETheme.pfGold : HETheme.pfBorder).withValues(alpha: 0.45),
  );
}
