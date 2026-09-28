import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';

import 'package:hidden_eleven/features/game/models/chemistry_vars.dart';
import 'package:hidden_eleven/features/game/widgets/chemistry_chips.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/models/user_chemistry_challenge.dart';
import 'package:hidden_eleven/shared/widgets/detail_bottom_sheet.dart';


// ── Collapsed summary entry point ─────────────────────────────────────────────

/// Default visible state for the squad preview — a single-line bar with the
/// estimated score and chemistry total, so this doesn't sit inline as a
/// full dense panel on every turn. Tapping it opens the full breakdown
/// ([ScoringPanel]) in a bottom sheet; nothing here is duplicated from that
/// full view, it's purely the headline numbers.
class ScoringSummaryBar extends StatelessWidget {
  const ScoringSummaryBar({super.key, required this.preview});

  final ScoringPreview preview;

  @override
  Widget build(BuildContext context) {
    final chemTotal =
        preview.userChemTotal + preview.cardChemTotal + preview.lineLeaderBonus;
    // Formatted strings, not the raw double/int, so the AnimatedSwitcher keys
    // below are stable across rebuilds that don't actually change what's
    // displayed (e.g. a float value that rounds to the same 2dp string).
    final estText = 'Est. ${preview.estimatedScore.toStringAsFixed(2)}';
    final chemText = '+$chemTotal chem';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showDetailBottomSheet(
          context,
          child: ScoringPanel(preview: preview),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: HETheme.pfSurfaceRaised,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: HETheme.pfGold.withValues(alpha: 0.25)),
          ),
          child: _SummaryLayout(
            label: const _SummaryLabel(),
            values: _SummaryValues(estText: estText, chemText: chemText),
          ),
        ),
      ),
    );
  }
}

/// Breakpoint below which the summary bar stacks its numbers onto their own
/// line.
///
/// At the narrowest real layout width this bar renders in (270px, per the
/// reported overflow) the two values alone measure ~244px against ~240px of
/// available content width — so no amount of label truncation can fit them
/// beside the label, and shrinking the numbers would make the actual data
/// unreadable. Below this width the label and the values get a line each;
/// nothing is hidden and no text shrinks.
const double _kSummaryStackBelow = 340;

class _SummaryLayout extends StatelessWidget {
  const _SummaryLayout({required this.label, required this.values});

  final Widget label;
  final Widget values;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < _kSummaryStackBelow) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [label, const _SummaryChevron()]),
              const SizedBox(height: 6),
              values,
            ],
          );
        }
        return Row(
          children: [
            label,
            const SizedBox(width: 8),
            values,
            const SizedBox(width: 4),
            const _SummaryChevron(),
          ],
        );
      },
    );
  }
}

class _SummaryChevron extends StatelessWidget {
  const _SummaryChevron();

  @override
  Widget build(BuildContext context) => const Icon(
    Icons.expand_more_rounded,
    color: HETheme.pfTextSecondary,
    size: 18,
  );
}

class _SummaryLabel extends StatelessWidget {
  const _SummaryLabel();

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Icon(
            Icons.insights_rounded,
            color: HETheme.pfGold.withValues(alpha: 0.85),
            size: 15,
          ),
          const SizedBox(width: 10),
          // The label is the only element allowed to give up width — the
          // numbers beside it are the actual data and never truncate.
          Expanded(
            child: Text(
              'SQUAD PREVIEW',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: HETheme.pfTextSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryValues extends StatelessWidget {
  const _SummaryValues({required this.estText, required this.chemText});

  final String estText;
  final String chemText;

  @override
  Widget build(BuildContext context) {
    // Wrap, not Row: at the very narrowest widths (270px) even these two
    // values alone exceed the line. Wrapping the chemistry value onto a
    // second line keeps both at full, readable size rather than shrinking or
    // truncating real score data.
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
              // Post-confirm swap updates (fresh scoringPreview arriving via
              // game_state) animate in rather than silently jumping — pure
              // presentation, no new scoring logic. No pending/speculative
              // preview here by design: that would mean computing chemistry
              // client-side before the server confirms it, duplicating
              // gameplay logic and risking drift from the authoritative result.
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: animation, child: child),
                ),
                child: Text(
                  estText,
                  key: ValueKey(estText),
                  style: const TextStyle(
                    color: HETheme.pfGold,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: animation, child: child),
                ),
                child: Text(
                  chemText,
                  key: ValueKey(chemText),
                  style: const TextStyle(
                    color: HETheme.pfSuccess,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
      ],
    );
  }
}

/// The Squad Preview bar plus its chemistry chips.
///
/// Kept as a separate wrapper rather than folded into [ScoringSummaryBar] so
/// the bar itself — and its existing tests — are untouched. The chips render
/// only when the server actually sent challenges; see [ChemistryChips] for
/// why no category-level totals are shown.
class ScoringSummaryWithChips extends StatelessWidget {
  const ScoringSummaryWithChips({super.key, required this.preview});

  final ScoringPreview preview;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ScoringSummaryBar(preview: preview),
        if (preview.userChallenges.isNotEmpty) ...[
          const SizedBox(height: 8),
          ChemistryChips(challenges: preview.userChallenges),
        ],
      ],
    );
  }
}

class ScoringPanel extends StatelessWidget {
  const ScoringPanel({super.key, required this.preview});

  final ScoringPreview preview;

  @override
  Widget build(BuildContext context) {
    final chemTotal =
        preview.userChemTotal + preview.cardChemTotal + preview.lineLeaderBonus;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: HETheme.pfSurfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HETheme.pfGold.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.insights_rounded,
                color: HETheme.pfGold.withValues(alpha: 0.85),
                size: 13,
              ),
              const SizedBox(width: 6),
              const Text(
                'SQUAD PREVIEW',
                style: TextStyle(
                  color: HETheme.pfTextSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Line averages
          Row(
            children: [
              _LineAvgChip(label: 'DEF', value: preview.defAvg),
              const SizedBox(width: 6),
              _LineAvgChip(label: 'MID', value: preview.midAvg),
              const SizedBox(width: 6),
              _LineAvgChip(label: 'ATK', value: preview.atkAvg),
              const SizedBox(width: 6),
              _LineAvgChip(
                label: 'TOTAL',
                value: preview.linesTotal,
                gold: true,
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Chemistry header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'CHEMISTRY',
                style: TextStyle(
                  color: HETheme.pfTextSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              Text(
                '+$chemTotal pts',
                style: const TextStyle(
                  color: HETheme.pfSuccess,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 5 user challenge rows with progress
          ...preview.userChallenges.map(
            (ch) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _ChallengeRow(challenge: ch),
            ),
          ),

          // Card chem row
          const SizedBox(height: 2),
          _CardChemRow(cardChemTotal: preview.cardChemTotal),

          // Line-leader bonus is competitive (best DEF/MID/ATK card across all
          // players) — it's decided at the final whistle, not shown live.
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.emoji_events_outlined,
                color: HETheme.pfTextSecondary,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ChemistryVars.resolve(
                    'Line leaders: +{lineLeaderBonus} per line for the best '
                    'DEF/MID/ATK card in the game — decided at full time',
                  ),
                  style: TextStyle(color: HETheme.pfTextSecondary, fontSize: 11),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          const Divider(height: 1, color: HETheme.pfBorder),
          const SizedBox(height: 12),

          // Estimated score
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Estimated score',
                  style: TextStyle(color: HETheme.pfTextSecondary, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                preview.estimatedScore.toStringAsFixed(2),
                style: const TextStyle(
                  color: HETheme.pfGold,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Challenge row with progress bar ──────────────────────────────────────────

class _ChallengeRow extends StatelessWidget {
  const _ChallengeRow({required this.challenge});

  final UserChemistryChallenge challenge;

  @override
  Widget build(BuildContext context) {
    final satisfied = challenge.satisfied;
    final circleColor = satisfied ? HETheme.pfSuccess : HETheme.pfTextSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // First line: circle + label + reward
        Row(
          children: [
            Icon(
              satisfied
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked,
              color: circleColor,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                challenge.label,
                style: TextStyle(
                  color: satisfied
                      ? HETheme.pfTextPrimary
                      : HETheme.pfTextSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            Text(
              '+${challenge.reward}',
              style: TextStyle(
                color: circleColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),

        // Second line: progress bar(s) indented to align with label
        Padding(
          padding: const EdgeInsets.only(left: 24),
          child: challenge.conditions.isNotEmpty
              ? _ComboProgressBars(conditions: challenge.conditions)
              : _SingleProgressBar(
                  current: challenge.current,
                  required: challenge.required,
                  satisfied: satisfied,
                ),
        ),
      ],
    );
  }
}

// ── Single progress bar (for non-combo challenges) ────────────────────────────

class _SingleProgressBar extends StatelessWidget {
  const _SingleProgressBar({
    required this.current,
    required this.required,
    required this.satisfied,
  });

  final int current;
  final int required;
  final bool satisfied;

  @override
  Widget build(BuildContext context) {
    final fraction = required > 0 ? (current / required).clamp(0.0, 1.0) : 0.0;
    final fillColor = satisfied ? HETheme.pfSuccess : HETheme.pfTextMuted;
    final countColor = satisfied ? HETheme.pfSuccess : HETheme.pfTextSecondary;

    return Row(
      children: [
        Expanded(
          child: _AnimatedBar(fraction: fraction, fillColor: fillColor),
        ),
        const SizedBox(width: 8),
        Text(
          '$current / $required',
          style: TextStyle(
            color: countColor,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ── Combo progress bars (for TWO_* challenges) ────────────────────────────────

class _ComboProgressBars extends StatelessWidget {
  const _ComboProgressBars({required this.conditions});

  final List<ChallengeConditionProgress> conditions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: conditions.map((cond) {
        final fraction = cond.required > 0
            ? (cond.current / cond.required).clamp(0.0, 1.0)
            : 0.0;
        final fillColor = cond.satisfied ? HETheme.pfSuccess : HETheme.pfTextMuted;
        final countColor = cond.satisfied ? HETheme.pfSuccess : HETheme.pfTextSecondary;

        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              // Condition label capped to avoid overflow
              SizedBox(
                width: 80,
                child: Text(
                  cond.label,
                  style: const TextStyle(
                    color: HETheme.pfTextSecondary,
                    fontSize: 10,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _AnimatedBar(fraction: fraction, fillColor: fillColor),
              ),
              const SizedBox(width: 6),
              Text(
                '${cond.current}/${cond.required}',
                style: TextStyle(
                  color: countColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ── Animated fill bar ─────────────────────────────────────────────────────────

class _AnimatedBar extends StatelessWidget {
  const _AnimatedBar({required this.fraction, required this.fillColor});

  final double fraction;
  final Color fillColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          height: 5,
          child: Stack(
            children: [
              // Track
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              // Fill
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: fraction),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                builder: (context, value, _) => FractionallySizedBox(
                  widthFactor: value,
                  alignment: Alignment.centerLeft,
                  child: Container(
                    decoration: BoxDecoration(
                      color: fillColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Card chem row (no progress bar — count is already in the label) ───────────

class _CardChemRow extends StatelessWidget {
  const _CardChemRow({required this.cardChemTotal});

  final int cardChemTotal;

  @override
  Widget build(BuildContext context) {
    final active = cardChemTotal > 0;
    final color = active ? HETheme.pfSuccess : HETheme.pfTextSecondary;

    return Row(
      children: [
        Icon(
          active ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
          color: color,
          size: 16,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Card chemistry (tiered bonuses)',
            style: TextStyle(
              color: active ? HETheme.pfTextPrimary : HETheme.pfTextSecondary,
              fontSize: 12,
            ),
          ),
        ),
        Text(
          '+$cardChemTotal',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ── Line average chip ─────────────────────────────────────────────────────────

class _LineAvgChip extends StatelessWidget {
  const _LineAvgChip({
    required this.label,
    required this.value,
    this.gold = false,
  });

  final String label;
  final Object value;

  /// Marks the squad-wide TOTAL chip as the premium headline figure.
  final bool gold;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: gold
              ? HETheme.pfGold.withValues(alpha: 0.10)
              : HETheme.pfSurfaceRaised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: gold ? HETheme.pfGold.withValues(alpha: 0.4) : HETheme.pfBorder,
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: HETheme.pfTextSecondary,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '$value',
              style: TextStyle(
                color: gold ? HETheme.pfGold : HETheme.pfTextPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
