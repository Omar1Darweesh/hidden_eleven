import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_motion.dart';
import 'package:hidden_eleven/app/he_shape.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import '../models/tournament_models.dart';
import 'fixture_capsule.dart';

/// A round-by-round "story" of each real team's path through the cup: an
/// expandable card per team with a connected timeline of every round they've
/// played (opponent, score, result), from round 1 up to wherever they
/// currently stand. Purely derived from the shared [state]/[liveEvents] —
/// stateless, no controllers/timers; expand state is owned by the parent so
/// this widget can never leak anything on rebuild.
class TeamJourneySection extends StatelessWidget {
  final TournamentStateModel state;
  final Map<String, List<LiveMatchEvent>> liveEvents;
  final Set<String> expandedTeamIds;
  final ValueChanged<String> onToggle;

  const TeamJourneySection({
    super.key,
    required this.state,
    required this.liveEvents,
    required this.expandedTeamIds,
    required this.onToggle,
  });

  /// The full original field (round 1 always holds every real team).
  List<ParticipantSnapshot> get _realTeams {
    if (state.rounds.isEmpty) return const [];
    final out = <ParticipantSnapshot>[];
    for (final m in state.rounds.first.matches) {
      for (final p in [m.participantA, m.participantB]) {
        if (p.kind == TournamentParticipantKind.real &&
            p.participantId.isNotEmpty) {
          out.add(p);
        }
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final teams = _realTeams;
    if (teams.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('TOURNAMENT JOURNEY'),
        const SizedBox(height: 12),
        for (final team in teams)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _TeamJourneyCard(
              team: team,
              state: state,
              liveEvents: liveEvents,
              expanded: expandedTeamIds.contains(team.participantId),
              onToggle: () => onToggle(team.participantId),
            ),
          ),
      ],
    );
  }

  Widget _sectionHeader(String t) => Row(
    children: [
      const Expanded(child: Divider(color: Colors.white12)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          t,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 11,
            letterSpacing: 2,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      const Expanded(child: Divider(color: Colors.white12)),
    ],
  );
}

// ---------------------------------------------------------------------------
// One team's step through a single round.
// ---------------------------------------------------------------------------

class _JourneyStep {
  final RoundSnapshot round;
  final MatchSnapshot match;
  final bool isTeamA;
  final ParticipantSnapshot opponent;

  const _JourneyStep({
    required this.round,
    required this.match,
    required this.isTeamA,
    required this.opponent,
  });
}

// ---------------------------------------------------------------------------
// _TeamJourneyCard — collapsible per-team card.
// ---------------------------------------------------------------------------

class _TeamJourneyCard extends StatelessWidget {
  final ParticipantSnapshot team;
  final TournamentStateModel state;
  final Map<String, List<LiveMatchEvent>> liveEvents;
  final bool expanded;
  final VoidCallback onToggle;

  const _TeamJourneyCard({
    required this.team,
    required this.state,
    required this.liveEvents,
    required this.expanded,
    required this.onToggle,
  });

  /// Every round this team has a placed slot in, in order — naturally stops
  /// the instant a team is eliminated (their slot never appears in the next
  /// round) or, for the current leader, includes the round they're now in
  /// even if the opponent side is still TBD.
  List<_JourneyStep> _computeSteps() {
    final steps = <_JourneyStep>[];
    for (final round in state.rounds) {
      MatchSnapshot? match;
      for (final m in round.matches) {
        if (m.participantA.participantId == team.participantId ||
            m.participantB.participantId == team.participantId) {
          match = m;
          break;
        }
      }
      if (match == null) break;
      final isTeamA = match.participantA.participantId == team.participantId;
      final opponent = isTeamA ? match.participantB : match.participantA;
      steps.add(
        _JourneyStep(
          round: round,
          match: match,
          isTeamA: isTeamA,
          opponent: opponent,
        ),
      );
    }
    return steps;
  }

  @override
  Widget build(BuildContext context) {
    final steps = _computeSteps();
    final isChampion =
        state.phase == TournamentPhase.complete &&
        state.awards?.champion.participantId == team.participantId;

    // The champion's journey is one of the reserved focus surfaces; every
    // other team's stays at standard weight so the winner's path is the one
    // that stands out.
    return FixtureCapsule(
      emphasis: isChampion ? FixtureEmphasis.focus : FixtureEmphasis.standard,
      accent: isChampion ? HETheme.pfGold : HETheme.pfBorder,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: HEShape.md,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  if (isChampion)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Text('🏆', style: TextStyle(fontSize: 14)),
                    ),
                  Expanded(
                    child: Text(
                      team.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${steps.length} round${steps.length == 1 ? '' : 's'} played',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: Colors.white38,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: HEMotion.reduced(context)
                ? Duration.zero
                : const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (int i = 0; i < steps.length; i++)
                          _JourneyStepRow(
                            step: steps[i],
                            team: team,
                            liveEvents: liveEvents,
                            isLast: i == steps.length - 1,
                          ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _JourneyStepRow — one round of the timeline (dot + connector + details).
// ---------------------------------------------------------------------------

class _JourneyStepRow extends StatelessWidget {
  final _JourneyStep step;
  final ParticipantSnapshot team;
  final Map<String, List<LiveMatchEvent>> liveEvents;
  final bool isLast;

  const _JourneyStepRow({
    required this.step,
    required this.team,
    required this.liveEvents,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final match = step.match;
    final isTbdOpponent = step.opponent.participantId.isEmpty;
    final status = match.status;

    // Every stop carries a colour, a word AND an icon — the icon is what
    // keeps the journey readable in greyscale and for colour-blind players.
    final Color dotColor;
    final String statusLabel;
    final IconData dotIcon;
    if (status == 'complete') {
      final won = match.winnerId == team.participantId;
      dotColor = won ? HETheme.pfSuccess : HETheme.pfDanger;
      statusLabel = won ? 'WON — ADVANCED' : 'LOST';
      dotIcon = won ? Icons.check_rounded : Icons.close_rounded;
    } else if (status == 'simulating') {
      // Live is red across the whole tournament vocabulary (bracket tags,
      // match cards, phase banner). This stop used to be green, which read as
      // "won" at a glance — the one place the journey disagreed with the rest
      // of the system.
      dotColor = HETheme.pfDanger;
      statusLabel = 'LIVE';
      dotIcon = Icons.podcasts_rounded;
    } else {
      dotColor = HETheme.pfTextMuted;
      statusLabel = isTbdOpponent ? 'UPCOMING' : 'READY';
      dotIcon = isTbdOpponent
          ? Icons.help_outline_rounded
          : Icons.schedule_rounded;
    }

    String? scoreText;
    final result = match.result;
    if (result != null) {
      final myScore = step.isTeamA ? result.scoreA : result.scoreB;
      final oppScore = step.isTeamA ? result.scoreB : result.scoreA;
      scoreText = '$myScore–$oppScore';
      if (result.wasDecidedByPenalties) {
        final myPens = step.isTeamA
            ? result.penaltyScoreA
            : result.penaltyScoreB;
        final oppPens = step.isTeamA
            ? result.penaltyScoreB
            : result.penaltyScoreA;
        scoreText = '$scoreText ($myPens–$oppPens pens)';
      }
    }

    final myGoals = (liveEvents[match.matchId] ?? [])
        .where(
          (e) => e.type == 'goal' && e.teamParticipantId == team.participantId,
        )
        .toList();

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                // The journey node: a ringed marker carrying the state icon,
                // so each stop reads as a station on a path rather than an
                // anonymous coloured dot.
                Container(
                  width: 18,
                  height: 18,
                  margin: const EdgeInsets.only(top: 1),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor.withValues(alpha: 0.18),
                    border: Border.all(
                      color: dotColor.withValues(alpha: 0.85),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(dotIcon, size: 10, color: dotColor),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: dotColor.withValues(alpha: 0.25),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Flexible: the round label shrinks first — statusLabel
                      // (e.g. "WON — ADVANCED") is the more important half
                      // to keep fully readable, and this row already lives
                      // inside a narrow, twice-nested Expanded column.
                      Flexible(
                        child: Text(
                          step.round.label.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                            letterSpacing: 1,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          color: dotColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          isTbdOpponent
                              ? 'vs TBD'
                              : 'vs ${step.opponent.displayName}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (scoreText != null)
                        Text(
                          scoreText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                  if (myGoals.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: myGoals
                            .map(
                              (e) => Text(
                                "⚽ ${e.playerName} ${e.minute}'",
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 10,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
