import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/tournament/models/tournament_models.dart';
import 'package:hidden_eleven/shared/widgets/he_card.dart';

/// The championship match, summarised for the results page — scoreline,
/// penalties, core stats, and who scored/assisted when. Uses only data the
/// client already has from the tournament run (`completedMatchResultsProvider`
/// / `liveMatchEventsProvider`, keyed by the final round's match id derived
/// from `tournamentStateProvider`); it does not parse a dedicated
/// `tournament_complete.finalMatch` payload.
///
/// Renders nothing if the final match hasn't resolved yet (e.g. the result
/// screen is reached before `tournament_match_result` arrives for it) — never
/// a broken or placeholder card.
class FinalMatchSummaryCard extends StatelessWidget {
  const FinalMatchSummaryCard({
    super.key,
    required this.tournamentState,
    required this.completedMatchResults,
    required this.liveMatchEvents,
  });

  final TournamentStateModel? tournamentState;
  final Map<String, TournamentMatchResult> completedMatchResults;
  final Map<String, List<LiveMatchEvent>> liveMatchEvents;

  /// Whether this card would render actual content — lets callers skip
  /// their own spacing (SizedBox) around it when the final hasn't resolved
  /// yet, instead of leaving a stray gap above an empty card.
  static bool hasData(
    TournamentStateModel? tournamentState,
    Map<String, TournamentMatchResult> completedMatchResults,
  ) {
    final state = tournamentState;
    if (state == null || state.rounds.isEmpty) return false;
    final finalRound = state.rounds.last;
    if (finalRound.matches.isEmpty) return false;
    final match = finalRound.matches.first;
    return completedMatchResults.containsKey(match.matchId);
  }

  @override
  Widget build(BuildContext context) {
    final state = tournamentState;
    if (state == null || state.rounds.isEmpty) return const SizedBox.shrink();

    final finalRound = state.rounds.last;
    if (finalRound.matches.isEmpty) return const SizedBox.shrink();
    final match = finalRound.matches.first;

    final result = completedMatchResults[match.matchId];
    if (result == null) return const SizedBox.shrink();

    final events =
        (liveMatchEvents[match.matchId] ?? const <LiveMatchEvent>[])
            .where((e) => e.type == 'goal')
            .toList()
          ..sort((a, b) => a.minute.compareTo(b.minute));

    final aWon = result.winnerId == match.participantA.participantId;
    final bWon = result.winnerId == match.participantB.participantId;
    final stats = result.stats;

    return HECard(
      variant: HECardVariant.gold,
      // Matches the 16/14/16/16 rhythm PointsBreakdownCard and
      // TournamentAwardsSummary already use on this page — HECard's own
      // default (20 all-around) would read as a size jump between cards.
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '🏆 FINAL',
            style: TextStyle(
              color: HETheme.pfGold,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  match.participantA.displayName,
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: aWon ? HETheme.pfTextPrimary : HETheme.pfTextSecondary,
                    fontSize: 14,
                    fontWeight: aWon ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  '${result.scoreA} – ${result.scoreB}',
                  style: const TextStyle(
                    color: HETheme.pfTextPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  match.participantB.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: bWon ? HETheme.pfTextPrimary : HETheme.pfTextSecondary,
                    fontSize: 14,
                    fontWeight: bWon ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (result.wasDecidedByPenalties) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Decided on penalties · '
                '${result.penaltyScoreA} – ${result.penaltyScoreB}',
                style: const TextStyle(
                  color: HETheme.pfGold,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            result.explanation,
            textAlign: TextAlign.center,
            style: const TextStyle(color: HETheme.pfTextSecondary, fontSize: 12),
          ),
          if (stats != null) ...[
            const SizedBox(height: 16),
            _FinalStatBar(
              label: 'POSSESSION',
              leftVal: stats.possessionA,
              rightVal: 100 - stats.possessionA,
              leftSuffix: '%',
              rightSuffix: '%',
            ),
            const SizedBox(height: 10),
            _FinalStatBar(
              label: 'SHOTS',
              leftVal: stats.shotsA,
              rightVal: stats.shotsB,
            ),
            const SizedBox(height: 10),
            _FinalStatBar(
              label: 'ON TARGET',
              leftVal: stats.shotsOnTargetA,
              rightVal: stats.shotsOnTargetB,
            ),
          ],
          if (events.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(color: HETheme.pfBorder, height: 1),
            const SizedBox(height: 10),
            for (final e in events)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    const Text('⚽', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e.assistPlayerName != null
                            ? '${e.playerName} (assist: ${e.assistPlayerName})'
                            : e.playerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: HETheme.pfTextPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      "${e.minute}'",
                      style: const TextStyle(
                        color: HETheme.pfTextMuted,
                        fontSize: 11,
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
}

/// Proportional dual-value stat row (centre-meeting bars), scoped to this
/// card. Mirrors `_DualStatBar` in `match_details_panel.dart`, which is
/// private to that file and left untouched here since it's a live,
/// in-tournament-critical widget outside this phase's scope.
class _FinalStatBar extends StatelessWidget {
  const _FinalStatBar({
    required this.label,
    required this.leftVal,
    required this.rightVal,
    this.leftSuffix = '',
    this.rightSuffix = '',
  });

  final String label;
  final int leftVal;
  final int rightVal;
  final String leftSuffix;
  final String rightSuffix;

  @override
  Widget build(BuildContext context) {
    final total = leftVal + rightVal;
    final leftRatio = total > 0 ? leftVal / total : 0.5;
    final rightRatio = total > 0 ? rightVal / total : 0.5;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: HETheme.pfTextMuted,
            fontSize: 10,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(
                '$leftVal$leftSuffix',
                style: const TextStyle(
                  color: HETheme.pfTextPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: leftRatio,
                    minHeight: 5,
                    backgroundColor: HETheme.pfBorder,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      HETheme.pfTextMuted,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: rightRatio,
                  minHeight: 5,
                  backgroundColor: HETheme.pfBorder,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    HETheme.pfTextMuted,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 34,
              child: Text(
                '$rightVal$rightSuffix',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: HETheme.pfTextPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
