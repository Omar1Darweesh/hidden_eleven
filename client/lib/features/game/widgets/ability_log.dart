import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/models/ability.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/services/chemistry_evaluator.dart';

/// The card-chemistry a Red card removed from its victim: how much that one
/// disabled card was contributing (its own + the links it fed) — computed by
/// re-enabling only that slot and diffing the team's card-chem total.
int redCardImpact(GameState game, AbilityActivation a) {
  final uid = a.targetUserId;
  final slotIndex = a.targetSlotIndex;
  if (uid == null || slotIndex == null) return 0;
  final pitch = game.pitches[uid];
  if (pitch == null) return 0;
  final filled = pitch.slots.where((s) => s.isFilled).toList();

  int teamChem(bool reEnableThis) {
    bool active(PitchSlot s) =>
        s.index == slotIndex ? reEnableThis : !s.isRedCarded;
    final lineup = filled
        .where((s) => s.cardFitsSlot && active(s))
        .map(LineupCard.fromSlot)
        .toList();
    var t = 0;
    for (final s in filled) {
      if (!s.cardFitsSlot || !active(s)) continue;
      t += ChemistryEvaluator.earnedReward(
        s.cardChemistryBonuses,
        lineup,
        ownerClub: s.cardClub,
      );
    }
    return t;
  }

  return teamChem(true) - teamChem(false);
}

/// A styled list of every ability that was played this game (who played what, on
/// whom). Reused on the results page and in the in-game history dialog. When
/// [game] is provided, Red-card rows show the live chemistry they removed.
class AbilityLogCard extends StatelessWidget {
  const AbilityLogCard({
    super.key,
    required this.activations,
    this.game,
    this.title = 'ABILITIES PLAYED',
    this.emptyLabel = 'No abilities were played.',
  });

  final List<AbilityActivation> activations;
  final GameState? game;
  final String title;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: HETheme.pfSurfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HETheme.pfBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                color: HETheme.pfAccentViolet,
                size: 15,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  color: HETheme.pfTextSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (activations.isEmpty)
            Text(
              emptyLabel,
              style: const TextStyle(color: HETheme.pfTextMuted, fontSize: 12),
            )
          else
            for (final a in activations) ...[
              _AbilityLogRow(
                activation: a,
                redImpact: (game != null && a.type == AbilityType.red)
                    ? redCardImpact(game!, a)
                    : null,
              ),
              if (a != activations.last) const SizedBox(height: 6),
            ],
        ],
      ),
    );
  }
}

class _AbilityLogRow extends StatelessWidget {
  const _AbilityLogRow({required this.activation, this.redImpact});
  final AbilityActivation activation;

  /// For Red cards: card-chemistry removed from the victim (null = not shown).
  final int? redImpact;

  @override
  Widget build(BuildContext context) {
    final meta = AbilityMeta.of(activation.type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: meta.color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: meta.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(meta.icon, color: meta.color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${activation.byName}: ',
                        style: const TextStyle(
                          color: HETheme.pfTextPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(
                        text: activation.summary,
                        style: const TextStyle(
                          color: HETheme.pfTextSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (redImpact != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      redImpact! > 0
                          ? 'Removed −$redImpact chemistry (own + broken links)'
                          : 'That player had no chemistry to remove',
                      style: TextStyle(
                        color: meta.color,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the ability log as a centered dialog — used by the in-game history
/// button so players can review what's been played at any point.
void showAbilityLogDialog(
  BuildContext context,
  List<AbilityActivation> activations, {
  GameState? game,
}) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: AbilityLogCard(activations: activations, game: game),
        ),
      ),
    ),
  );
}
