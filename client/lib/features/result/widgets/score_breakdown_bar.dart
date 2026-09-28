import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/shared/widgets/segmented_bar.dart';

/// The dossier's "shape before numbers" score visualization — a horizontal
/// stacked bar with four labeled segments (Base / Tactical Fit / Line
/// Leaders / Abilities), sized proportionally to each contribution.
///
/// **Data integrity note:** every value here reads directly from the exact
/// same [ScoreBreakdown] fields the existing detail rows
/// (`_ScoringBreakdownCard` in `result_screen.dart`) already display —
/// `linesTotal`, `userChemTotal`/`cardChemTotal`, `lineLeaderBonus`,
/// `captainBonus`/`yellowPenalty`. No score is recomputed here; this widget
/// only *groups* already-server-authoritative numbers for the bar's shape,
/// so the bar and the detail rows can never drift out of sync with each
/// other. `ScoreBreakdown.lines` (a labeled-line list) exists on the model
/// but is never actually populated by the current server payload parsing —
/// confirmed by inspection — so it isn't used as a data source here.
///
/// Purely additive: does not replace `_ScoringBreakdownCard`, which still
/// owns the full numeric detail (out-of-position callouts, per-challenge
/// chemistry rows, ability effects). This is the summary that sits above it.
///
/// Draws via the generic [SegmentedBar] — this class now only owns *which*
/// four segments/colors/values it is and the exact accessibility summary,
/// not the bar-drawing logic itself.
class ScoreBreakdownBar extends StatelessWidget {
  const ScoreBreakdownBar({super.key, required this.breakdown});

  final ScoreBreakdown breakdown;

  static const _segments = [
    (label: 'Base', color: HETheme.pfTextSecondary),
    (label: 'Tactical Fit', color: HETheme.pfSuccess),
    (label: 'Line Leaders', color: HETheme.pfGold),
    (label: 'Abilities', color: HETheme.pfSecondaryViolet),
  ];

  List<int> get _values {
    final base = breakdown.linesTotal;
    final tacticalFit = breakdown.userChemTotal + breakdown.cardChemTotal;
    final lineLeaders = breakdown.lineLeaderBonus;
    final abilities = breakdown.captainBonus - breakdown.yellowPenalty;
    return [base, tacticalFit, lineLeaders, abilities];
  }

  @override
  Widget build(BuildContext context) {
    final values = _values;

    return Semantics(
      label:
          'Score breakdown: ${List.generate(_segments.length, (i) => '${_segments[i].label} ${values[i]} points').join(', ')}. '
          'Final score ${breakdown.finalScore.toStringAsFixed(2)}.',
      child: SegmentedBar(
        segments: [
          for (var i = 0; i < _segments.length; i++)
            BarSegment(
              label: _segments[i].label,
              color: _segments[i].color,
              value: values[i],
            ),
        ],
      ),
    );
  }
}
