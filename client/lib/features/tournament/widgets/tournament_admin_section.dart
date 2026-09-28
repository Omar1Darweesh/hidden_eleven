import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hidden_eleven/app/theme.dart';
import '../providers/tournament_provider.dart';
import '../models/tournament_models.dart';

/// Read-only tournament status section for the admin panel.
/// Shows nothing when no tournament is in progress.
///
/// Styled to match the Server Monitor tab's cards (HEColors surface card,
/// HERadius.md, muted-label / primary-value rows).
class TournamentAdminSection extends ConsumerWidget {
  const TournamentAdminSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tournamentStateProvider);
    final awards = ref.watch(tournamentCompleteProvider);

    // Show nothing if no tournament has started.
    if (state == null) return const SizedBox.shrink();

    final currentMatches = state.rounds
        .where((r) => r.roundNumber == state.currentRound)
        .expand((r) => r.matches)
        .toList();

    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: HEColors.surface,
        borderRadius: BorderRadius.circular(HERadius.md),
        border: Border.all(color: HEColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.emoji_events_rounded,
                color: HEColors.accent,
                size: 20,
              ),
              const SizedBox(width: 10),
              const Text(
                'Tournament',
                style: TextStyle(
                  color: HEColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          _infoRow('Phase', _phaseLabel(state.phase)),
          _infoRow('Round', '${state.currentRound} of ${state.totalRounds}'),
          _infoRow(
            'Bracket size',
            state.rounds.isNotEmpty
                ? '${state.rounds.first.matches.length * 2}'
                : '—',
          ),
          _infoRow('Ready players', '${state.readyPlayerIds.length}'),

          if (state.phase == TournamentPhase.readyCheck &&
              state.readyDeadlineAt != null)
            _infoRow(
              'Ready deadline',
              _epochToTimeString(state.readyDeadlineAt!),
            ),

          if (awards != null) ...[
            _infoRow('Champion', awards.champion.displayName),
            _infoRow('Runner-up', awards.runnerUp.displayName),
            if (awards.topScorerName != null)
              _infoRow(
                'Top scorer',
                '${awards.topScorerName} (${awards.topScorerGoals ?? 0} goals)',
              ),
          ],

          if (currentMatches.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'CURRENT ROUND MATCHES',
              style: TextStyle(
                color: HEColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            ...currentMatches.map(_matchRow),
          ],
        ],
      ),
    );
  }

  String _phaseLabel(TournamentPhase phase) {
    switch (phase) {
      case TournamentPhase.bracketReveal:
        return 'Bracket Reveal';
      case TournamentPhase.readyCheck:
        return 'Ready Check';
      case TournamentPhase.simulating:
        return 'Simulating';
      case TournamentPhase.roundResult:
        return 'Round Result';
      case TournamentPhase.complete:
        return 'Complete';
    }
  }

  String _epochToTimeString(int epochMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epochMs);
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(color: HEColors.textMuted, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: HEColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _matchRow(MatchSnapshot match) {
    final statusColor = switch (match.status) {
      'complete' => Colors.blue,
      'simulating' => const Color(0xFF4CAF50),
      'ready_check' => Colors.amber,
      _ => HEColors.textMuted,
    };
    final score = match.result != null
        ? '${match.result!.scoreA}–${match.result!.scoreB}'
        : 'vs';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${match.participantA.displayName} $score '
              '${match.participantB.displayName}',
              style: const TextStyle(
                color: HEColors.textSecondary,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: statusColor.withValues(alpha: 0.5)),
            ),
            child: Text(
              match.status.toUpperCase().replaceAll('_', ' '),
              style: TextStyle(color: statusColor, fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }
}
