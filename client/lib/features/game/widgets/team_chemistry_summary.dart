import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_shape.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/widgets/chemistry_constellation.dart';
import 'package:hidden_eleven/shared/widgets/detail_bottom_sheet.dart';

/// Presentation-only banding of the chemistry total into a plain-language
/// status word.
///
/// **This is not scoring.** It never feeds a score, a reward, a server value
/// or a decision — it only picks which of three words to print next to a
/// number that was already computed and delivered by the server. The
/// thresholds are display bands chosen for readability; changing them changes
/// nothing except the word shown.
enum ChemistryStatus {
  needsWork,
  balanced,
  strong;

  static ChemistryStatus forTotal(int total) {
    if (total >= 24) return ChemistryStatus.strong;
    if (total >= 10) return ChemistryStatus.balanced;
    return ChemistryStatus.needsWork;
  }

  String get label => switch (this) {
    ChemistryStatus.strong => 'Strong',
    ChemistryStatus.balanced => 'Balanced',
    ChemistryStatus.needsWork => 'Needs Work',
  };

  Color get color => switch (this) {
    ChemistryStatus.strong => HETheme.pfSuccess,
    ChemistryStatus.balanced => HETheme.pfGold,
    ChemistryStatus.needsWork => HETheme.pfTextSecondary,
  };

  IconData get icon => switch (this) {
    ChemistryStatus.strong => Icons.check_circle_rounded,
    ChemistryStatus.balanced => Icons.adjust_rounded,
    ChemistryStatus.needsWork => Icons.trending_up_rounded,
  };
}

/// A compact, readable chemistry readout that replaces the pitch aura overlay.
///
/// Shows the chemistry total the server already sent, a plain status word, and
/// one count chip per link type — each carrying its C / L / N letter marker so
/// the meaning never depends on colour. "Why?" opens the per-group member
/// lists, which is the information the old overlay encoded geometrically.
///
/// Reads existing data only: [total] comes from the caller's
/// `ScoringPreview`, and the groups come from the unchanged
/// [computeChemistryGroups]. Nothing here evaluates chemistry.
class TeamChemistrySummary extends StatelessWidget {
  const TeamChemistrySummary({
    super.key,
    required this.slots,
    required this.total,
  });

  /// The local player's pitch slots — grouping input only.
  final List<PitchSlot> slots;

  /// Chemistry total as already computed server-side and delivered in the
  /// scoring preview (user + card chemistry + line-leader bonus).
  final int total;

  @override
  Widget build(BuildContext context) {
    final groups = computeChemistryGroups(slots);
    final status = ChemistryStatus.forTotal(total);

    final counts = <ChemistryGroupType, int>{};
    for (final g in groups) {
      counts[g.type] = (counts[g.type] ?? 0) + g.size;
    }

    return Semantics(
      label:
          'Team chemistry $total points, ${status.label}. '
          '${_chipSemantics(counts)}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: HETheme.pfSurfaceRaised,
          borderRadius: HEShape.md,
          border: Border.all(
            color: HETheme.pfAccentViolet.withValues(alpha: 0.20),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'TEAM CHEMISTRY',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: HETheme.pfTextSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                Text(
                  '$total',
                  style: const TextStyle(
                    color: HETheme.pfTextPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Status: icon + word, never colour alone.
            Row(
              children: [
                Icon(status.icon, size: 14, color: status.color),
                const SizedBox(width: 6),
                Text(
                  status.label,
                  style: TextStyle(
                    color: status.color,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final type in ChemistryGroupType.values)
                  _LinkChip(type: type, count: counts[type] ?? 0),
              ],
            ),
            if (groups.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => showDetailBottomSheet(
                    context,
                    child: _ChemistryDetails(groups: groups, total: total),
                  ),
                  icon: const Icon(Icons.help_outline_rounded, size: 15),
                  label: const Text('Why?'),
                  style: TextButton.styleFrom(
                    foregroundColor: HETheme.pfAccentViolet,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: const Size(44, 44),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _chipSemantics(Map<ChemistryGroupType, int> counts) => [
    for (final t in ChemistryGroupType.values)
      '${t.label} ${counts[t] ?? 0} linked',
  ].join(', ');
}

/// One link-type chip: letter marker + label + count.
///
/// The letter (C / L / N) is always present, so the three types stay
/// distinguishable in greyscale and for colour-blind players.
class _LinkChip extends StatelessWidget {
  const _LinkChip({required this.type, required this.count});

  final ChemistryGroupType type;
  final int count;

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    final color = active ? type.color : HETheme.pfTextMuted;

    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: active ? 0.10 : 0.05),
        borderRadius: HEShape.pill,
        border: Border.all(color: color.withValues(alpha: active ? 0.40 : 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Letter marker — the non-colour signal.
          Container(
            width: 16,
            height: 16,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: active ? 0.20 : 0.10),
              shape: BoxShape.circle,
            ),
            child: Text(
              type.letter,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${type.label} ×$count',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// The readable replacement for the old aura geometry: who is linked to whom,
/// as text.
class _ChemistryDetails extends StatelessWidget {
  const _ChemistryDetails({required this.groups, required this.total});

  final List<ChemistryGroup> groups;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Team Chemistry',
          style: TextStyle(
            color: HETheme.pfTextPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Players sharing a club, league or nation link up. '
          'Your squad has ${groups.length} '
          '${groups.length == 1 ? 'link' : 'links'} for $total points.',
          style: const TextStyle(
            color: HETheme.pfTextSecondary,
            fontSize: 13,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 14),
        for (final g in groups) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _LinkChip(type: g.type, count: g.size),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        g.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: HETheme.pfTextPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  g.slots
                      .map((s) => s.cardPlayerName ?? s.label)
                      .join('  ·  '),
                  style: const TextStyle(
                    color: HETheme.pfTextSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
