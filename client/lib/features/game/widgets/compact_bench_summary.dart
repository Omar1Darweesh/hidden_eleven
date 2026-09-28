import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/services/chemistry_evaluator.dart';
import 'package:hidden_eleven/features/game/widgets/card_details_modal.dart';

/// Compact read-only bench strip for continuity after bench_selection ends.
///
/// Used during `ability_activation` so the three locked bench picks do not
/// feel like they vanished when the sidebar swaps from [SubsPanel] to the
/// ability panel. Chips stay small and non-editable; tapping one opens the
/// shared [showCardDetailsModal] for inspection only — never spin/re-pick/
/// swap (those stay lineup_edit-only).
class CompactBenchSummary extends StatelessWidget {
  const CompactBenchSummary({
    super.key,
    required this.subs,
    this.lineup = const [],
    this.title = 'YOUR BENCH',
  });

  final UserSubstitutions? subs;

  /// Local starting XI — used only so the details modal can score the
  /// locked bench card's chemistry challenges (same as SubsPanel).
  final List<LineupCard> lineup;

  final String title;

  @override
  Widget build(BuildContext context) {
    final chips = <(String, SubSlot?, Color)>[
      ('ATK', subs?.att, HETheme.pfPositionAttack),
      ('MID', subs?.mid, HETheme.pfPositionMid),
      ('DEF', subs?.def, HETheme.pfPositionDef),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: HETheme.pfSurfaceRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: HETheme.pfBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lock_rounded,
                color: HETheme.pfTextMuted,
                size: 13,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  color: HETheme.pfTextMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              const Text(
                'Locked',
                style: TextStyle(
                  color: HETheme.pfAccentViolet,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (label, slot, color) in chips)
                _BenchChip(
                  group: label,
                  name: _name(slot),
                  color: color,
                  onTap: () => _openDetails(context, slot),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _openDetails(BuildContext context, SubSlot? slot) {
    final card = slot?.benchCard;
    if (card == null) return;
    showCardDetailsModal(
      context,
      playerName: card.playerName,
      rating: card.rating,
      position: card.primaryPosition,
      imageSeed: card.cardId,
      club: card.club,
      clubLogoUrl: card.clubLogoUrl,
      primaryColor: card.primaryColor,
      secondaryColor: card.secondaryColor,
      tertiaryColor: card.tertiaryColor,
      kitPattern: card.kitPattern,
      cardStyle: card.cardStyle,
      kitNumber: card.kitNumber,
      nationality: card.nationality,
      altPositions: card.naturalAltPositions,
      pace: card.pace,
      shooting: card.shooting,
      passing: card.passing,
      dribbling: card.dribbling,
      defending: card.defending,
      physical: card.physical,
      chemistryBonuses: card.chemistryBonuses,
      lineup: lineup,
      // No onPick — informational only during ability_activation.
    );
  }

  static String _name(SubSlot? slot) {
    final n = slot?.chosenPlayerName ?? slot?.benchedPlayerName;
    if (n == null || n.isEmpty) return '—';
    return n;
  }
}

class _BenchChip extends StatelessWidget {
  const _BenchChip({
    required this.group,
    required this.name,
    required this.color,
    this.onTap,
  });

  final String group;
  final String name;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tappable = onTap != null && name != '—';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: tappable ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                group,
                style: TextStyle(
                  color: color,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 88),
                child: Text(
                  name,
                  style: const TextStyle(
                    color: HETheme.pfTextPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (tappable) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.info_outline_rounded,
                  size: 11,
                  color: color.withValues(alpha: 0.85),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
