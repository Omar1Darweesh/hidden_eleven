import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_motion.dart';
import 'package:hidden_eleven/app/he_shape.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/tournament/models/tournament_models.dart';
import 'package:hidden_eleven/shared/widgets/help_dialog.dart';
import 'package:hidden_eleven/shared/widgets/count_up_text.dart';
import 'package:hidden_eleven/shared/widgets/segmented_bar.dart';

/// Bar colors for bonus categories, cycled in the order categories appear —
/// deliberately distinct from the semantic vocabulary (pfSuccess/pfWarning/
/// pfDanger stay reserved for actual state meaning) so a category color never
/// reads as a status. The base segment always uses pfTextSecondary, matching
/// ScoreBreakdownBar's own "Base" segment color.
const _kCategoryBarColors = [
  HETheme.pfGold,
  HETheme.pfAccentVioletGlow,
  HETheme.pfLavenderText,
  HETheme.pfSecondaryViolet,
  HETheme.pfBronze,
];

/// Shows exactly how one user's final total was built: base squad/draft score
/// + each tournament bonus they earned (shared awards clearly labelled with
/// their actual rounded-up share) = final total. The math is never hidden.
class PointsBreakdownCard extends StatelessWidget {
  final PlayerResult result;
  final TournamentAwardsModel? awards;
  final bool isLocal;

  const PointsBreakdownCard({
    super.key,
    required this.result,
    this.awards,
    this.isLocal = false,
  });

  @override
  Widget build(BuildContext context) {
    final breakdown = result.scoreBreakdown;
    final total = result.score ?? breakdown?.finalScore.round() ?? 0;
    final baseScore = breakdown?.finalScore.round() ?? total;
    final bonusLines = awards?.breakdownFor(result.playerId) ?? const [];
    // Empty `lines` covers both "no breakdown at all" and "a payload from
    // before this field existed" — either way, fall back to the original
    // single collapsed line rather than rendering nothing.
    final scoreLines = breakdown?.lines ?? const [];

    // Visual bar summary — additive above the existing label+value rows
    // below, never a replacement for them (safeguard: category meaning must
    // never depend on bar color alone, and SHARED/AI LED pills stay exactly
    // where the text rows already put them). Blocked categories contribute
    // no bonus, so they're excluded from the bar itself but remain fully
    // visible in the text rows with their "—" value and explanatory pill.
    final barSegments = [
      BarSegment(
        label: scoreLines.isNotEmpty ? 'Base' : 'Base squad score',
        color: HETheme.pfTextSecondary,
        value: baseScore,
      ),
      for (var i = 0; i < bonusLines.length; i++)
        if (!bonusLines[i].blocked)
          BarSegment(
            label: bonusLines[i].label,
            color: _kCategoryBarColors[i % _kCategoryBarColors.length],
            value: bonusLines[i].points,
          ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: HETheme.pfSurfaceRaised,
        borderRadius: HEShape.lg,
        border: Border.all(color: HETheme.pfBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                'POINTS BREAKDOWN',
                style: TextStyle(
                  color: HETheme.pfTextSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
              if (isLocal)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: HETheme.pfAccentViolet.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'YOU',
                    style: TextStyle(
                      color: HETheme.pfAccentViolet,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (barSegments.length > 1) ...[
            // R4: fills once on first appearance; the legend beneath it and
            // every value below render in full immediately.
            SegmentedBar(segments: barSegments, fillOnce: true),
            const SizedBox(height: 14),
          ],

          // Grouped into a score story — "where the squad score came from",
          // then "what the tournament added" — rather than one flat ledger.
          // Purely a grouping of the same lines: every label, value, SHARED /
          // AI LED pill and blocked state renders exactly as before.
          if (scoreLines.isNotEmpty) ...[
            const _GroupHeading('FROM YOUR SQUAD'),
            for (int i = 0; i < scoreLines.length; i++) ...[
              if (i > 0) const SizedBox(height: 6),
              _BreakdownLine(
                label: scoreLines[i].label,
                value: _formatLineAmount(scoreLines[i].amount),
                accent: scoreLines[i].amount > 0,
                negative: scoreLines[i].amount < 0,
                detail: scoreLines[i].detail,
              ),
            ],
          ] else
            _BreakdownLine(label: 'Base squad score', value: '$baseScore'),
          if (bonusLines.isNotEmpty) ...[
            const SizedBox(height: 12),
            const _GroupHeading('FROM THE TOURNAMENT'),
          ],
          for (final b in bonusLines) ...[
            const SizedBox(height: 6),
            _BreakdownLine(
              label: b.label,
              value: b.blocked ? '—' : '+${b.points}',
              accent: !b.blocked,
              shared: b.shared,
              blocked: b.blocked,
            ),
          ],

          const SizedBox(height: 12),
          const Divider(height: 1, color: HETheme.pfBorder),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Flexible: a fixed label+help pair vs. a fixed numeric total
              // in a spaceBetween Row — same shape already fixed in
              // result_screen.dart's identical "Final score" row.
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Flexible(
                      child: Text(
                        'Final total',
                        style: TextStyle(
                          color: HETheme.pfTextPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const InlineHelp(
                      'Base squad score plus every tournament bonus earned — '
                      'this is what decides the winner.',
                    ),
                  ],
                ),
              ),
              // R4: the headline total counts once. Under reduced motion it
              // is painted at its final value on the very first frame.
              CountUpText(
                value: total,
                duration: HEMotion.wake,
                style: const TextStyle(
                  color: HETheme.pfAccentViolet,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "+N" for a positive amount, "N" (already signed) for negative, "—" for
/// exactly zero (an informational line with no point value, e.g. red-card-applied).
String _formatLineAmount(int amount) {
  if (amount == 0) return '—';
  return amount > 0 ? '+$amount' : '$amount';
}

/// A quiet section heading inside the breakdown.
///
/// Structural, not decorative: it names where a group of lines actually comes
/// from (the squad you built, versus what the tournament awarded), which is a
/// real distinction in how those points were earned.
class _GroupHeading extends StatelessWidget {
  const _GroupHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: HETheme.pfTextMuted,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(height: 1, color: HETheme.pfBorder),
          ),
        ],
      ),
    );
  }
}

class _BreakdownLine extends StatelessWidget {
  final String label;
  final String value;
  final bool accent;
  final bool shared;
  final bool blocked;

  /// True for a penalty line (negative amount) — colors the value in an
  /// error tone instead of the positive/accent green.
  final bool negative;

  /// Optional muted subtext under the label — e.g. which card/challenge
  /// earned this line. Ignored when `blocked` is true (that case already
  /// has its own fixed explanatory text).
  final String? detail;

  const _BreakdownLine({
    required this.label,
    required this.value,
    this.accent = false,
    this.shared = false,
    this.blocked = false,
    this.negative = false,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: blocked
                            ? HETheme.pfTextSecondary
                            : accent
                            ? HETheme.pfTextPrimary
                            : HETheme.pfTextSecondary,
                        fontSize: 13,
                        fontWeight: accent && !blocked
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (blocked) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: HETheme.pfSecondaryViolet.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: HETheme.pfSecondaryViolet.withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Text(
                        'AI LED',
                        style: TextStyle(
                          color: HETheme.pfSecondaryViolet,
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ] else if (shared) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: HETheme.pfGold.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text(
                        'SHARED',
                        style: TextStyle(
                          color: HETheme.pfGold,
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (blocked)
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Text(
                    'You led this category, but an AI club shared it — no '
                    'bonus was paid out.',
                    style: TextStyle(
                      color: HETheme.pfTextMuted,
                      fontSize: 10.5,
                      height: 1.25,
                    ),
                  ),
                )
              else if (detail != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    detail!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: HETheme.pfTextMuted,
                      fontSize: 10.5,
                      height: 1.25,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: negative
                ? HETheme.pfDanger
                : blocked
                ? HETheme.pfTextMuted
                : accent
                ? HETheme.pfSuccess
                : HETheme.pfTextPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
