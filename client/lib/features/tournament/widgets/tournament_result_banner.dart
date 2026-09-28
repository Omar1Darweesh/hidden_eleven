import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/shared/widgets/rank_medallion.dart';
import '../providers/tournament_provider.dart';

/// Shows a tournament summary at the top of the result screen.
/// Renders nothing when no tournament was played.
class TournamentResultBanner extends ConsumerWidget {
  const TournamentResultBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final awards = ref.watch(tournamentCompleteProvider);
    if (awards == null) return const SizedBox.shrink();

    final myId = ref.watch(myParticipantIdProvider);
    final myPoints = myId != null ? (awards.pointsAwarded[myId] ?? 0) : 0;
    final isChampion = myId == awards.champion.participantId;
    final isRunnerUp = myId == awards.runnerUp.participantId;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isChampion
              ? [HETheme.pfSurfaceDeep, HETheme.pfGold.withValues(alpha: 0.18)]
              : [HETheme.pfSurfaceDeep, HETheme.pfSurfaceRaised],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isChampion
              ? HETheme.pfGold
              : isRunnerUp
              ? HETheme.pfLavenderText
              : HETheme.pfBorder,
          width: isChampion ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              const Icon(
                Icons.emoji_events,
                color: HETheme.pfGold,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'TOURNAMENT RESULT',
                style: TextStyle(
                  color: HETheme.pfTextSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Champion row
          _resultRow(
            rank: 1,
            label: 'Champion',
            value: awards.champion.displayName,
            highlight: isChampion,
          ),

          // Runner-up row
          _resultRow(
            rank: 2,
            label: 'Runner-up',
            value: awards.runnerUp.displayName,
            highlight: isRunnerUp,
          ),

          // Top scorer (if available)
          if (awards.topScorerName != null)
            _resultRow(
              icon: '⚽',
              label: 'Top Scorer',
              value:
                  '${awards.topScorerName}'
                  '${awards.topScorerGoals != null ? " (${awards.topScorerGoals} goals)" : ""}',
              highlight: false,
            ),

          // Points earned by this player (only shown if they earned any)
          if (myPoints > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: HETheme.pfSuccess.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: HETheme.pfSuccess.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star, color: HETheme.pfSuccess, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'You earned +$myPoints points',
                    style: const TextStyle(
                      color: HETheme.pfSuccess,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Either `rank` (renders a [RankMedallion] — Champion/Runner-up) or
  /// `icon` (a plain category emoji, e.g. Top Scorer's ⚽ — not a placement
  /// marker, so it stays a simple glyph) must be supplied.
  Widget _resultRow({
    int? rank,
    String? icon,
    required String label,
    required String value,
    required bool highlight,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          if (rank != null)
            RankMedallion(rank: rank, size: 18)
          else
            Text(icon!, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(
              color: HETheme.pfTextSecondary,
              fontSize: 13,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: highlight ? HETheme.pfGold : HETheme.pfTextPrimary,
                fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
