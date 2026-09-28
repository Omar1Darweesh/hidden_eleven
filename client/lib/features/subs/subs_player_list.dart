import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/services/chemistry_evaluator.dart';
import 'package:hidden_eleven/features/game/widgets/card_details_modal.dart';
import 'package:hidden_eleven/features/lobby/models/server_event.dart';

/// Text-first replacement for a grid of full `PlayerCard`s after a sub spin.
///
/// A subs spin can return several eligible players at once, and the old grid
/// rendered a full `PlayerCard` per player — each with up to three separate
/// `Image.network` calls (photo, club badge, flag). That's a real, evidenced
/// contributor to native rendering instability on constrained GPU/driver
/// configs (see club_roulette_drum.dart's doc comment for the sibling
/// Impeller/OpenGLES history this app has already hit twice). This widget
/// renders NO images at all — every row is plain text in a lazily-built
/// `ListView.builder`, so building N rows costs N text layouts, not N
/// concurrent image decodes. Tapping a row opens the existing
/// `showCardDetailsModal` (which still shows the full card/image — that's
/// one image, on demand, not N images up front) for the actual pick
/// decision; picking there closes the modal and calls [onPick] exactly as
/// the old grid's tap-to-view-then-pick flow did. No new server events, no
/// change to `pick_sub` — this is presentation-only.
class SubsPlayerListPicker extends StatelessWidget {
  const SubsPlayerListPicker({
    super.key,
    required this.result,
    required this.color,
    required this.lineup,
    required this.onPick,
  });

  final SubSpinResult result;
  final Color color;
  final List<LineupCard> lineup;
  final void Function(CandidateCard) onPick;

  @override
  Widget build(BuildContext context) {
    // This widget sizes to its content (mainAxisSize.min) and does NOT scroll
    // itself — it is always hosted inside an ancestor scroll view (the mobile
    // GameActionSheet's SingleChildScrollView, or the wide sidebar's). Owning a
    // second scrollable on the same axis is exactly what broke mobile scrolling
    // before: the inner ListView and the outer sheet scroll contested the drag
    // gesture, so the candidate list couldn't be scrolled. Handing all
    // scrolling to that single ancestor gives one clear scroll region.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Club result banner — identical content/shape to the old grid's.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: color, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result.clubName,
                  style: TextStyle(
                    color: color,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Text(
                'Pick one player',
                style: TextStyle(color: HETheme.pfTextMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (result.players.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Text(
              'No eligible players for this club.',
              style: TextStyle(color: HETheme.pfTextSecondary, fontSize: 13),
            ),
          )
        else
          ListView.builder(
            // Inline, non-scrolling: shrinkWrap sizes it to its rows and
            // NeverScrollableScrollPhysics hands every drag to the ancestor
            // scroll view (see the class-build comment above). The rows are
            // lightweight text-only widgets and a spin returns at most a
            // dozen-odd players, so eager layout here is cheap.
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            itemCount: result.players.length,
            itemBuilder: (ctx, i) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SubCandidateRow(
                card: result.players[i],
                color: color,
                lineup: lineup,
                onPick: onPick,
              ),
            ),
          ),
      ],
    );
  }
}

class _SubCandidateRow extends StatelessWidget {
  const _SubCandidateRow({
    required this.card,
    required this.color,
    required this.lineup,
    required this.onPick,
  });

  final CandidateCard card;
  final Color color;
  final List<LineupCard> lineup;
  final void Function(CandidateCard) onPick;

  void _openDetails(BuildContext context) {
    showCardDetailsModal(
      context,
      playerName: card.playerName,
      rating: card.rating,
      position: card.basePositionType,
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
      altPositions: card.altPositions,
      pace: card.pace,
      shooting: card.shooting,
      passing: card.passing,
      dribbling: card.dribbling,
      defending: card.defending,
      physical: card.physical,
      chemistryBonuses: card.chemistryBonuses,
      lineup: lineup,
      onPick: () => onPick(card),
    );
  }

  @override
  Widget build(BuildContext context) {
    // A real tap target (not just the text baseline) — the whole row,
    // padded to a comfortable minimum height, is the hit area.
    return Material(
      color: HETheme.pfSurfaceRaised,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openDetails(context),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              _RatingChip(rating: card.rating, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      card.playerName,
                      style: const TextStyle(
                        color: HETheme.pfTextPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Club and nation each on their own line (no leading
                    // position — positions live in the dedicated right-side
                    // area now). Only rendered when present.
                    if (card.club != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        card.club!,
                        style: const TextStyle(
                          color: HETheme.pfTextSecondary,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (card.nationality != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        card.nationality!,
                        style: const TextStyle(
                          color: HETheme.pfTextMuted,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Dedicated fit/role area: every position the player can play
              // (primary + alternates), from the card's real position fields
              // (primaryPosition/naturalAltPositions, not derived text),
              // deduplicated. Width-capped and right-aligned; allowed up to two
              // lines (the club/nation stack on the left gives the row height)
              // before truncating with an ellipsis, so it never squeezes the
              // name column or wraps awkwardly on small phones.
              SizedBox(
                width: 76,
                child: Text(
                  _positionsLabel(card),
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: HETheme.pfTextSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: HETheme.pfTextMuted,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Primary position first, then alt positions, deduplicated, as a compact
/// "RW · RM · LW" string. Sourced from the card's real position fields
/// ([CandidateCard.primaryPosition] / [CandidateCard.naturalAltPositions]),
/// not derived from any other text.
String _positionsLabel(CandidateCard card) {
  final seen = <String>{};
  final positions = <String>[
    card.primaryPosition,
    ...card.naturalAltPositions,
  ].where((p) => seen.add(p));
  return positions.join(' · ');
}

class _RatingChip extends StatelessWidget {
  const _RatingChip({required this.rating, required this.color});
  final int rating;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        '$rating',
        style: TextStyle(
          color: color,
          fontSize: 12.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
