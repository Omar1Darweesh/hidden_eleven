import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hidden_eleven/app/routes.dart';
import 'package:hidden_eleven/app/he_motion.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/shared/widgets/rank_medallion.dart';
import 'package:hidden_eleven/features/game/game_provider.dart';
import 'package:hidden_eleven/features/game/models/chemistry_bonus.dart';
import 'package:hidden_eleven/features/game/models/chemistry_vars.dart';
import 'package:hidden_eleven/features/game/widgets/ability_log.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/services/chemistry_evaluator.dart';
import 'package:hidden_eleven/features/game/widgets/pitch_view.dart';
import 'package:hidden_eleven/features/game/widgets/player_card.dart';
import 'package:hidden_eleven/features/lobby/room_provider.dart';
import 'package:hidden_eleven/shared/audio/audio_service.dart';
import 'package:hidden_eleven/shared/widgets/event_atmosphere_background.dart';
import 'package:hidden_eleven/features/result/widgets/final_match_summary_card.dart';
import 'package:hidden_eleven/features/result/widgets/final_standings_card.dart';
import 'package:hidden_eleven/features/result/widgets/points_breakdown_card.dart';
import 'package:hidden_eleven/features/result/widgets/result_hero_summary.dart';
import 'package:hidden_eleven/features/result/widgets/score_breakdown_bar.dart';
import 'package:hidden_eleven/features/result/widgets/squad_details_section.dart';
import 'package:hidden_eleven/features/result/widgets/tournament_awards_summary.dart';
import 'package:hidden_eleven/features/result/widgets/your_result_card.dart';
import 'package:hidden_eleven/features/tournament/models/tournament_models.dart';
import 'package:hidden_eleven/features/tournament/providers/tournament_provider.dart';
import 'package:hidden_eleven/features/tournament/widgets/team_journey_section.dart';
import 'package:hidden_eleven/shared/ads/interstitial_gate.dart';
import 'package:hidden_eleven/shared/providers/local_presence_provider.dart';
import 'package:hidden_eleven/shared/widgets/he_button.dart';
import 'package:hidden_eleven/shared/widgets/context_help_button.dart';
import 'package:hidden_eleven/shared/widgets/help_dialog.dart';

/// Result page help — who won and why, standings, per-user points math,
/// shared ranks/awards, Top Contributions, and Final Score vs Final Points.
const _resultHelpSections = <HelpSection>[
  HelpSection('THE WINNER', [
    HelpEntry(
      'Who won and why',
      'The hero banner names whoever has the highest final total and gives '
          'the real reason — usually the tournament champion bonus, another '
          'tournament bonus, or simply the highest draft score.',
    ),
    HelpEntry(
      'Shared rank',
      'If two or more users end with the exact same final total, they '
          'share that rank (e.g. both shown as joint 1st) rather than one '
          'being arbitrarily placed above the other.',
    ),
  ]),
  HelpSection('FINAL STANDINGS & POINTS', [
    HelpEntry(
      'Final Score vs Final Points',
      'Final Score is your draft/chemistry score alone (line averages + '
          'chemistry). Final Points is that score PLUS any tournament '
          'bonuses (champion, runner-up, award bonuses) — it\'s what '
          'actually decides the winner.',
    ),
    HelpEntry(
      'Per-user breakdown',
      'Tap any row in Final Standings to see that user\'s full breakdown: '
          'base squad score, then each bonus they earned, adding up to '
          'their final total.',
    ),
  ]),
  HelpSection('TOURNAMENT AWARDS', [
    HelpEntry(
      'Top Contributions',
      'Goals + assists combined — a separate leaderboard from Top Scorer '
          'and Top Assists, showing all-round attacking impact.',
    ),
    HelpEntry(
      'Shared awards',
      'If players tie on a stat (and on minutes played, where that '
          'applies), the award is shared — every tied winner is shown, '
          'each earning an equal, rounded-up share of the bonus points.',
    ),
  ]),
];

// ── Position groupings for line-average calculations ─────────────────────────

const _kDefPos = {'GK', 'LB', 'CB', 'RB'};
const _kMidPos = {'CDM', 'CM', 'CAM', 'LM', 'RM'};
const _kAtkPos = {'LW', 'RW', 'CF', 'ST'};

// ── Per-team stat summary ─────────────────────────────────────────────────────

class _TeamStats {
  const _TeamStats({
    required this.total,
    required this.avg,
    required this.defAvg,
    required this.midAvg,
    required this.atkAvg,
    required this.bestSlot,
  });

  /// Raw sum of all 11 pitch cards' ratings — NOT the final draft/result
  /// score (that's `ScoreBreakdown.finalScore`, computed server-side from
  /// line AVERAGES + chemistry bonuses). Shown in the collapsed squad detail
  /// section as a squad-power stat only; must never be labelled "Total"
  /// or "Score" without qualification, or it reads as the final score.
  final int total;
  final double avg;
  final int defAvg;
  final int midAvg;
  final int atkAvg;
  final PitchSlot? bestSlot;

  static _TeamStats compute(PlayerPitch? pitch) {
    if (pitch == null || pitch.filledCount == 0) {
      return const _TeamStats(
        total: 0,
        avg: 0,
        defAvg: 0,
        midAvg: 0,
        atkAvg: 0,
        bestSlot: null,
      );
    }
    final filled = pitch.slots.where((s) => s.isFilled).toList();
    // Out-of-position players score 0 (matches the server) — count them in the
    // denominator but contribute nothing.
    int rating(PitchSlot s) => s.cardFitsSlot ? (s.cardRating ?? 0) : 0;
    final total = filled.fold(0, (sum, s) => sum + rating(s));
    final avg = total / filled.length;

    int lineAvg(Set<String> pos) {
      final line = filled
          .where((s) => pos.contains(s.basePositionType))
          .toList();
      if (line.isEmpty) return 0;
      return (line.fold(0, (sum, s) => sum + rating(s)) / line.length).round();
    }

    // "Best" excludes out-of-position cards (they're not contributing).
    final inPosition = filled.where((s) => s.cardFitsSlot).toList();
    final best = inPosition.isEmpty
        ? null
        : inPosition.reduce(
            (a, b) => (a.cardRating ?? 0) >= (b.cardRating ?? 0) ? a : b,
          );

    return _TeamStats(
      total: total,
      avg: avg,
      defAvg: lineAvg(_kDefPos),
      midAvg: lineAvg(_kMidPos),
      atkAvg: lineAvg(_kAtkPos),
      bestSlot: best,
    );
  }
}

// ── Line leaders (best in-position card per line, across all players) ─────────

class _LineLeader {
  const _LineLeader({
    required this.line,
    required this.slot,
    required this.ownerName,
    required this.rating,
  });
  final String line; // DEF / MID / ATK
  final PitchSlot slot;
  final String ownerName;
  final int rating;
}

/// For each line, the highest-rated IN-POSITION card across every player's XI —
/// these are the line-leader winners (bonus amount is admin-configurable;
/// see lineLeader.bonusPerLine in scoring-config.ts, resolved for display
/// via ChemistryVars).
List<_LineLeader> _computeLineLeaders(GameState game) {
  final lineDefs = <String, Set<String>>{
    'DEF': _kDefPos,
    'MID': _kMidPos,
    'ATK': _kAtkPos,
  };
  final out = <_LineLeader>[];
  lineDefs.forEach((line, positions) {
    PitchSlot? best;
    String owner = '';
    int bestRating = -1;
    for (final p in game.players) {
      final pitch = game.pitches[p.id];
      if (pitch == null) continue;
      for (final s in pitch.slots) {
        if (!s.isFilled ||
            !positions.contains(s.basePositionType) ||
            !s.cardFitsSlot) {
          continue;
        }
        final r = s.cardRating ?? 0;
        if (r > bestRating) {
          bestRating = r;
          best = s;
          owner = p.displayName;
        }
      }
    }
    if (best != null) {
      out.add(
        _LineLeader(
          line: line,
          slot: best,
          ownerName: owner,
          rating: bestRating,
        ),
      );
    }
  });
  return out;
}

CandidateCard _candidateFromSlot(PitchSlot s) => CandidateCard(
  cardId: s.cardId ?? '',
  playerName: s.cardPlayerName ?? '',
  basePositionType: s.basePositionType,
  rating: s.cardRating ?? 0,
  imageUrl: s.cardImageUrl,
  club: s.cardClub,
  clubLogoUrl: s.cardClubLogoUrl,
  primaryColor: s.cardPrimaryColor,
  secondaryColor: s.cardSecondaryColor,
  tertiaryColor: s.cardTertiaryColor,
  kitPattern: s.cardKitPattern,
  kitNumber: s.cardKitNumber,
  nationality: s.cardNationality,
  altPositions: s.cardAltPositions,
  pace: s.cardPace,
  shooting: s.cardShooting,
  passing: s.cardPassing,
  dribbling: s.cardDribbling,
  defending: s.cardDefending,
  physical: s.cardPhysical,
);

class _LineLeadersBanner extends StatelessWidget {
  const _LineLeadersBanner({required this.game});
  final GameState game;

  @override
  Widget build(BuildContext context) {
    final leaders = _computeLineLeaders(game);
    if (leaders.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: HETheme.pfSurfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HETheme.pfSecondaryViolet),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.emoji_events_rounded,
                color: HETheme.pfAccentViolet,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                ChemistryVars.resolve(
                  'LINE LEADERS  ·  +{lineLeaderBonus} EACH',
                ),
                style: TextStyle(
                  color: HETheme.pfAccentViolet,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final l in leaders)
                Expanded(child: _LineLeaderCard(leader: l)),
            ],
          ),
        ],
      ),
    );
  }
}

class _LineLeaderCard extends StatelessWidget {
  const _LineLeaderCard({required this.leader});
  final _LineLeader leader;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          Text(
            leader.line,
            style: const TextStyle(
              color: HETheme.pfTextSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 92),
            child: PlayerCard(card: _candidateFromSlot(leader.slot)),
          ),
          const SizedBox(height: 6),
          Text(
            leader.ownerName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: HETheme.pfTextPrimary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            'owner',
            style: TextStyle(color: HETheme.pfTextMuted, fontSize: 9.5),
          ),
        ],
      ),
    );
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({super.key, required this.roomCode});
  final String roomCode;

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  int _tabIndex = 0;
  // Team journey cards default collapsed; one tap per team reveals its path.
  final Set<String> _expandedJourneyTeams = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final game = ref.read(gameProvider);
      if (game == null) {
        context.goNamed(Routes.home);
        return;
      }
      // Match is genuinely over and the result screen is on-screen — the one
      // natural break in a session where a full-screen ad interrupts nothing.
      // The gate applies the grace period and frequency cap; it may well
      // decide not to show anything, which is the intended common case.
      InterstitialGate.onMatchFinished();

      final localPlayerId = ref.read(localPlayerIdProvider);
      PlayerResult? myResult;
      for (final pr in game.result?.players ?? const <PlayerResult>[]) {
        if (pr.playerId == localPlayerId) {
          myResult = pr;
          break;
        }
      }
      if (myResult != null) {
        ref
            .read(audioServiceProvider)
            .playSfx(myResult.rank == 1 ? Sfx.victory : Sfx.defeat);
      }
    });
  }

  void _goHome() {
    ref.read(localPresenceProvider.notifier).clear();
    ref.read(gameProvider.notifier).reset();
    ref.read(roomProvider.notifier).clearAfterGameEnd();
    context.goNamed(Routes.home);
  }

  List<String> _orderedIds(GameState game, String? localId) {
    final others = game.players
        .where((p) => p.id != localId)
        .map((p) => p.id)
        .toList();
    return [?localId, ...others];
  }

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameProvider);
    final localPlayerId = ref.watch(localPlayerIdProvider);
    final awards = ref.watch(tournamentCompleteProvider);
    final tournamentState = ref.watch(tournamentStateProvider);
    final liveEvents = ref.watch(liveMatchEventsProvider);
    final completedMatchResults = ref.watch(completedMatchResultsProvider);

    if (game == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final orderedIds = _orderedIds(game, localPlayerId);
    final safeTab = _tabIndex
        .clamp(0, math.max(0, orderedIds.length - 1))
        .toInt();
    final viewedId = orderedIds.isNotEmpty ? orderedIds[safeTab] : null;
    final viewedPitch = viewedId != null ? game.pitches[viewedId] : null;
    final stats = _TeamStats.compute(viewedPitch);

    // Build a rank lookup: playerId → rank + score from server result
    final rankMap = <String, PlayerResult>{};
    for (final pr in game.result?.players ?? <PlayerResult>[]) {
      rankMap[pr.playerId] = pr;
    }

    final viewedResult = viewedId != null ? rankMap[viewedId] : null;

    return Scaffold(
      backgroundColor: HETheme.pfBgVoid,
      appBar: _buildAppBar(game),
      body: Stack(
        children: [
          // Post-match atmosphere. This screen previously had no background
          // layer at all — just a flat void colour. The gold radial sits high
          // and centred, behind the winner hero, so the reserved colour marks
          // the achievement rather than tinting the whole recap.
          const Positioned.fill(
            child: EventAtmosphereBackground(
              variant: EventAtmosphereVariant.results,
              goldFocus: true,
              goldAlignment: Alignment(0, -0.72),
            ),
          ),
          SafeArea(
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            final isWide = constraints.maxWidth >= 720;
            if (isWide) {
              return _WideLayout(
                game: game,
                orderedIds: orderedIds,
                localPlayerId: localPlayerId,
                viewedPitch: viewedPitch,
                stats: stats,
                rankMap: rankMap,
                viewedResult: viewedResult,
                awards: awards,
                tournamentState: tournamentState,
                liveEvents: liveEvents,
                completedMatchResults: completedMatchResults,
                expandedJourneyTeams: _expandedJourneyTeams,
                onToggleJourneyTeam: (id) => setState(() {
                  if (!_expandedJourneyTeams.remove(id)) {
                    _expandedJourneyTeams.add(id);
                  }
                }),
                tabIndex: safeTab,
                onTabChanged: (i) => setState(() => _tabIndex = i),
                onHome: _goHome,
              );
            }
            return _NarrowLayout(
              game: game,
              orderedIds: orderedIds,
              localPlayerId: localPlayerId,
              viewedPitch: viewedPitch,
              stats: stats,
              rankMap: rankMap,
              viewedResult: viewedResult,
              awards: awards,
              tournamentState: tournamentState,
              liveEvents: liveEvents,
              completedMatchResults: completedMatchResults,
              expandedJourneyTeams: _expandedJourneyTeams,
              onToggleJourneyTeam: (id) => setState(() {
                if (!_expandedJourneyTeams.remove(id)) {
                  _expandedJourneyTeams.add(id);
                }
              }),
              tabIndex: safeTab,
              onTabChanged: (i) => setState(() => _tabIndex = i),
              onHome: _goHome,
            );
          },
        ),
          ),
        ],
      ),
    );
  }

  AppBar _buildAppBar(GameState game) {
    return AppBar(
      backgroundColor: HETheme.pfSurfaceRaised,
      elevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: 20,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: HETheme.pfAccentViolet.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: HETheme.pfSecondaryViolet),
            ),
            child: Text(
              game.roomCode,
              style: const TextStyle(
                color: HETheme.pfAccentViolet,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'Draft Complete',
            style: TextStyle(
              color: HETheme.pfTextSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      actions: const [
        ContextHelpButton(
          contextKey: 'result_page',
          title: 'Result Page',
          fallbackSections: _resultHelpSections,
        ),
      ],
    );
  }
}

// ── Shared squad/chemistry detail content (collapsed by default) ─────────────

/// The demoted, secondary content: pick a user to inspect, their line stats,
/// the score breakdown chemistry math, per-card chemistry, and the pitch.
/// Wrapped in [SquadDetailsSection] by both layouts so it never dominates.
class _SquadDetailsContent extends StatelessWidget {
  const _SquadDetailsContent({
    required this.game,
    required this.orderedIds,
    required this.localPlayerId,
    required this.rankMap,
    required this.viewedPitch,
    required this.stats,
    required this.tabIndex,
    required this.onTabChanged,
  });

  final GameState game;
  final List<String> orderedIds;
  final String? localPlayerId;
  final Map<String, PlayerResult> rankMap;
  final PlayerPitch? viewedPitch;
  final _TeamStats stats;
  final int tabIndex;
  final ValueChanged<int> onTabChanged;

  @override
  Widget build(BuildContext context) {
    final viewedBreakdown = orderedIds.isNotEmpty
        ? rankMap[orderedIds[tabIndex]]?.scoreBreakdown
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LineLeadersBanner(game: game),
        const SizedBox(height: 14),
        _ResultTabBar(
          game: game,
          orderedIds: orderedIds,
          localPlayerId: localPlayerId,
          rankMap: rankMap,
          selectedIndex: tabIndex,
          onTabChanged: onTabChanged,
        ),
        const SizedBox(height: 14),
        _LineupStats(stats: stats),
        if (viewedBreakdown != null) ...[
          const SizedBox(height: 12),
          _ScoringBreakdownCard(
            breakdown: viewedBreakdown,
            outOfPosition:
                viewedPitch?.slots
                    .where((s) => s.isFilled && !s.cardFitsSlot)
                    .toList() ??
                const [],
          ),
          const SizedBox(height: 12),
          _CardChemDetailCard(slots: viewedPitch?.slots ?? const []),
        ],
        if (game.abilityActivations.isNotEmpty) ...[
          const SizedBox(height: 12),
          AbilityLogCard(activations: game.abilityActivations, game: game),
        ],
        const SizedBox(height: 14),
        PitchView(
          slots: viewedPitch?.slots ?? [],
          roundSlotIndex: null,
          isInteractiveOwner: false,
          turnPhase: 'selecting_position',
          onSlotTap: null,
          highlightOutOfPosition: true,
        ),
      ],
    );
  }
}

/// The highest score across the standings, or null if there are no results
/// yet — used only to phrase `YourResultCard`'s "N behind the leader" line.
/// Purely derived from already-displayed data (the same score every
/// `FinalStandingsCard` row already shows); never a new metric.
int? _leaderScore(Map<String, PlayerResult> rankMap) {
  int? best;
  for (final r in rankMap.values) {
    final score = r.score ?? r.scoreBreakdown?.finalScore.round() ?? 0;
    if (best == null || score > best) best = score;
  }
  return best;
}

String _squadSubtitle(GameState game, List<String> orderedIds, int tabIndex) {
  if (orderedIds.isEmpty) {
    return 'Tap to view line stats, chemistry, and the pitch';
  }
  final id = orderedIds[tabIndex];
  final name =
      game.players.where((p) => p.id == id).firstOrNull?.displayName ?? '—';
  return 'Viewing $name — line stats, chemistry, and the pitch';
}

// ── Wide layout (≥ 720 px) ────────────────────────────────────────────────────

class _WideLayout extends StatelessWidget {
  const _WideLayout({
    required this.game,
    required this.orderedIds,
    required this.localPlayerId,
    required this.viewedPitch,
    required this.stats,
    required this.rankMap,
    required this.viewedResult,
    required this.awards,
    required this.tournamentState,
    required this.liveEvents,
    required this.completedMatchResults,
    required this.expandedJourneyTeams,
    required this.onToggleJourneyTeam,
    required this.tabIndex,
    required this.onTabChanged,
    required this.onHome,
  });

  final GameState game;
  final List<String> orderedIds;
  final String? localPlayerId;
  final PlayerPitch? viewedPitch;
  final _TeamStats stats;
  final Map<String, PlayerResult> rankMap;
  final PlayerResult? viewedResult;
  final TournamentAwardsModel? awards;
  final TournamentStateModel? tournamentState;
  final Map<String, List<LiveMatchEvent>> liveEvents;
  final Map<String, TournamentMatchResult> completedMatchResults;
  final Set<String> expandedJourneyTeams;
  final ValueChanged<String> onToggleJourneyTeam;
  final int tabIndex;
  final ValueChanged<int> onTabChanged;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final myResult = localPlayerId != null ? rankMap[localPlayerId] : null;
    final leaderScore = _leaderScore(rankMap);
    final iAmWinner = myResult != null && myResult.rank == 1;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ResultHeroSummary(
            game: game,
            localPlayerId: localPlayerId,
            awards: awards,
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Left: standings + home ────────────────────────────────────
              SizedBox(
                width: 320,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FinalStandingsCard(
                      game: game,
                      orderedIds: orderedIds,
                      localPlayerId: localPlayerId,
                      rankMap: rankMap,
                      awards: awards,
                      selectedPlayerId: orderedIds.isNotEmpty
                          ? orderedIds[tabIndex]
                          : null,
                      onTap: onTabChanged,
                    ),
                    const SizedBox(height: 24),
                    // Reachable but visually secondary — no gold/champion
                    // styling, never competing with the hero, Your Result,
                    // or standings above it.
                    HEButton(
                      label: 'Back to Home',
                      icon: Icons.home_rounded,
                      onPressed: onHome,
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 20),

              // ── Right: your result + points breakdown + awards + squad ───
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (myResult != null) ...[
                      YourResultCard(
                        result: myResult,
                        isWinner: iAmWinner,
                        leaderScore: leaderScore,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (viewedResult != null)
                      PointsBreakdownCard(
                        result: viewedResult!,
                        awards: awards,
                        isLocal:
                            orderedIds.isNotEmpty &&
                            orderedIds[tabIndex] == localPlayerId,
                      ),
                    if (FinalMatchSummaryCard.hasData(
                      tournamentState,
                      completedMatchResults,
                    )) ...[
                      const SizedBox(height: 16),
                      FinalMatchSummaryCard(
                        tournamentState: tournamentState,
                        completedMatchResults: completedMatchResults,
                        liveMatchEvents: liveEvents,
                      ),
                    ],
                    if (awards != null) ...[
                      const SizedBox(height: 16),
                      TournamentAwardsSummary(awards: awards!),
                    ],
                    if (tournamentState != null &&
                        tournamentState!.rounds.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      TeamJourneySection(
                        state: tournamentState!,
                        liveEvents: liveEvents,
                        expandedTeamIds: expandedJourneyTeams,
                        onToggle: onToggleJourneyTeam,
                      ),
                    ],
                    const SizedBox(height: 16),
                    SquadDetailsSection(
                      subtitle: _squadSubtitle(game, orderedIds, tabIndex),
                      child: _SquadDetailsContent(
                        game: game,
                        orderedIds: orderedIds,
                        localPlayerId: localPlayerId,
                        rankMap: rankMap,
                        viewedPitch: viewedPitch,
                        stats: stats,
                        tabIndex: tabIndex,
                        onTabChanged: onTabChanged,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Narrow layout (< 720 px) ──────────────────────────────────────────────────

class _NarrowLayout extends StatelessWidget {
  const _NarrowLayout({
    required this.game,
    required this.orderedIds,
    required this.localPlayerId,
    required this.viewedPitch,
    required this.stats,
    required this.rankMap,
    required this.viewedResult,
    required this.awards,
    required this.tournamentState,
    required this.liveEvents,
    required this.completedMatchResults,
    required this.expandedJourneyTeams,
    required this.onToggleJourneyTeam,
    required this.tabIndex,
    required this.onTabChanged,
    required this.onHome,
  });

  final GameState game;
  final List<String> orderedIds;
  final String? localPlayerId;
  final PlayerPitch? viewedPitch;
  final _TeamStats stats;
  final Map<String, PlayerResult> rankMap;
  final PlayerResult? viewedResult;
  final TournamentAwardsModel? awards;
  final TournamentStateModel? tournamentState;
  final Map<String, List<LiveMatchEvent>> liveEvents;
  final Map<String, TournamentMatchResult> completedMatchResults;
  final Set<String> expandedJourneyTeams;
  final ValueChanged<String> onToggleJourneyTeam;
  final int tabIndex;
  final ValueChanged<int> onTabChanged;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final myResult = localPlayerId != null ? rankMap[localPlayerId] : null;
    final leaderScore = _leaderScore(rankMap);
    final iAmWinner = myResult != null && myResult.rank == 1;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ResultHeroSummary(
            game: game,
            localPlayerId: localPlayerId,
            awards: awards,
          ),
          if (myResult != null) ...[
            const SizedBox(height: 16),
            YourResultCard(
              result: myResult,
              isWinner: iAmWinner,
              leaderScore: leaderScore,
            ),
          ],
          const SizedBox(height: 16),
          FinalStandingsCard(
            game: game,
            orderedIds: orderedIds,
            localPlayerId: localPlayerId,
            rankMap: rankMap,
            awards: awards,
            selectedPlayerId: orderedIds.isNotEmpty
                ? orderedIds[tabIndex]
                : null,
            onTap: onTabChanged,
          ),
          const SizedBox(height: 16),
          // Moved up from the bottom of the page (Phase B): reachable
          // without scrolling past every secondary section below — still
          // visually secondary, no gold/champion styling, same action.
          HEButton(
            label: 'Back to Home',
            icon: Icons.home_rounded,
            onPressed: onHome,
          ),
          if (viewedResult != null) ...[
            const SizedBox(height: 16),
            PointsBreakdownCard(
              result: viewedResult!,
              awards: awards,
              isLocal:
                  orderedIds.isNotEmpty &&
                  orderedIds[tabIndex] == localPlayerId,
            ),
          ],
          if (FinalMatchSummaryCard.hasData(
            tournamentState,
            completedMatchResults,
          )) ...[
            const SizedBox(height: 16),
            FinalMatchSummaryCard(
              tournamentState: tournamentState,
              completedMatchResults: completedMatchResults,
              liveMatchEvents: liveEvents,
            ),
          ],
          if (awards != null) ...[
            const SizedBox(height: 16),
            TournamentAwardsSummary(awards: awards!),
          ],
          if (tournamentState != null &&
              tournamentState!.rounds.isNotEmpty) ...[
            const SizedBox(height: 16),
            TeamJourneySection(
              state: tournamentState!,
              liveEvents: liveEvents,
              expandedTeamIds: expandedJourneyTeams,
              onToggle: onToggleJourneyTeam,
            ),
          ],
          const SizedBox(height: 16),
          SquadDetailsSection(
            subtitle: _squadSubtitle(game, orderedIds, tabIndex),
            child: _SquadDetailsContent(
              game: game,
              orderedIds: orderedIds,
              localPlayerId: localPlayerId,
              rankMap: rankMap,
              viewedPitch: viewedPitch,
              stats: stats,
              tabIndex: tabIndex,
              onTabChanged: onTabChanged,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Result tab bar ────────────────────────────────────────────────────────────

class _ResultTabBar extends StatelessWidget {
  const _ResultTabBar({
    required this.game,
    required this.orderedIds,
    required this.localPlayerId,
    required this.rankMap,
    required this.selectedIndex,
    required this.onTabChanged,
  });

  final GameState game;
  final List<String> orderedIds;
  final String? localPlayerId;
  final Map<String, PlayerResult> rankMap;
  final int selectedIndex;
  final ValueChanged<int> onTabChanged;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = HEMotion.reduced(context);
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: orderedIds.length,
        separatorBuilder: (_, idx) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final pid = orderedIds[i];
          final player = game.players.where((p) => p.id == pid).firstOrNull;
          final isActive = i == selectedIndex;
          final isLocal = pid == localPlayerId;
          final rank = rankMap[pid]?.rank;

          return GestureDetector(
            onTap: () => onTabChanged(i),
            child: AnimatedContainer(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isActive
                    ? HETheme.pfAccentViolet.withValues(alpha: 0.13)
                    : HETheme.pfSurfaceRaised,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isActive ? HETheme.pfAccentViolet : HETheme.pfBorder,
                  width: isActive ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  if (rank != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: RankMedallion(rank: rank, size: 20),
                    ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 88),
                    child: Text(
                      isLocal ? 'You' : (player?.displayName ?? '—'),
                      style: TextStyle(
                        color: isActive
                            ? HETheme.pfAccentViolet
                            : HETheme.pfTextSecondary,
                        fontSize: 13,
                        fontWeight: isActive
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Lineup stats row ──────────────────────────────────────────────────────────

class _LineupStats extends StatelessWidget {
  const _LineupStats({required this.stats});

  final _TeamStats stats;

  @override
  Widget build(BuildContext context) {
    if (stats.total == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Total + avg row
        Row(
          children: [
            Expanded(
              child: _StatChip(
                label: 'RAW SUM',
                value: '${stats.total}',
                accent: true,
                helpText:
                    'Plain total of all 11 card ratings — not your final score.',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatChip(
                label: 'AVG',
                value: stats.avg.toStringAsFixed(1),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatChip(label: 'DEF', value: '${stats.defAvg}'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatChip(label: 'MID', value: '${stats.midAvg}'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatChip(label: 'ATK', value: '${stats.atkAvg}'),
            ),
          ],
        ),

        // Best pick card
        if (stats.bestSlot != null) ...[
          const SizedBox(height: 10),
          _BestPickCard(slot: stats.bestSlot!),
        ],
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    this.accent = false,
    this.helpText,
  });

  final String label;
  final String value;
  final bool accent;
  final String? helpText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: accent
            ? HETheme.pfAccentViolet.withValues(alpha: 0.12)
            : HETheme.pfSurfaceRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: accent ? HETheme.pfSecondaryViolet : HETheme.pfBorder,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Flexible so a longer label shrinks/ellipsizes instead of
              // pushing the trailing help icon past this chip's width —
              // reproduced overflow: 6.6px when several chips share a Row
              // on a narrow screen. Same fix as tournament_hub_screen.dart's
              // "READY CHECK" title Row.
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: HETheme.pfTextSecondary,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (helpText != null) ...[
                const SizedBox(width: 2),
                InlineHelp(helpText!, size: 11),
              ],
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              color: accent ? HETheme.pfAccentViolet : HETheme.pfTextPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Scoring breakdown card (result screen) ────────────────────────────────────

class _ScoringBreakdownCard extends StatelessWidget {
  const _ScoringBreakdownCard({
    required this.breakdown,
    this.outOfPosition = const [],
  });

  final ScoreBreakdown breakdown;

  /// Filled slots whose card doesn't fit its position — these scored 0.
  final List<PitchSlot> outOfPosition;

  @override
  Widget build(BuildContext context) {
    final userChemTotal = breakdown.userChemTotal;
    final cardChemTotal = breakdown.cardChemTotal;
    final lineLeaderBonus = breakdown.lineLeaderBonus;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: HETheme.pfSurfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HETheme.pfBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'SCORE BREAKDOWN',
            style: TextStyle(
              color: HETheme.pfTextSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 12),

          // Shape-before-numbers summary — see ScoreBreakdownBar's own doc
          // comment for why this can never drift from the detail rows below.
          ScoreBreakdownBar(breakdown: breakdown),
          const SizedBox(height: 16),

          // Line averages
          Row(
            children: [
              _SChip(label: 'DEF', value: '${breakdown.defAvg}'),
              const SizedBox(width: 6),
              _SChip(label: 'MID', value: '${breakdown.midAvg}'),
              const SizedBox(width: 6),
              _SChip(label: 'ATK', value: '${breakdown.atkAvg}'),
              const SizedBox(width: 6),
              _SChip(
                label: 'TOTAL',
                value: '${breakdown.linesTotal}',
                accent: true,
              ),
            ],
          ),

          // Out-of-position callout — these players scored 0.
          if (outOfPosition.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: HETheme.pfDanger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: HETheme.pfDanger.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.report_problem_rounded,
                    color: HETheme.pfDanger,
                    size: 15,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Out of position — scored 0',
                          style: TextStyle(
                            color: HETheme.pfDanger,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          outOfPosition
                              .map(
                                (s) =>
                                    '${s.cardPlayerName ?? '?'} (${s.effectiveNaturalPositions.isNotEmpty ? s.effectiveNaturalPositions.first : '?'} in ${s.label})',
                              )
                              .join(', '),
                          style: const TextStyle(
                            color: HETheme.pfTextSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (userChemTotal > 0 ||
              cardChemTotal > 0 ||
              lineLeaderBonus > 0) ...[
            const SizedBox(height: 14),
            const Text(
              'CHEMISTRY',
              style: TextStyle(
                color: HETheme.pfTextSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            _SBreakdownRow(
              checked: userChemTotal > 0,
              label: 'User challenges',
              bonus: '+$userChemTotal',
            ),
            const SizedBox(height: 5),
            _SBreakdownRow(
              checked: cardChemTotal > 0,
              label: 'Card chemistry',
              bonus: '+$cardChemTotal',
            ),
            const SizedBox(height: 5),
            _SBreakdownRow(
              checked: lineLeaderBonus > 0,
              label: 'Line leaders (best DEF/MID/ATK in game)',
              bonus: '+$lineLeaderBonus',
            ),
          ],

          // Ability-card effects (Captain / Red / Yellow).
          if (breakdown.captainBonus > 0 ||
              breakdown.yellowPenalty > 0 ||
              breakdown.redApplied) ...[
            const SizedBox(height: 14),
            const Text(
              'ABILITIES',
              style: TextStyle(
                color: HETheme.pfTextSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            if (breakdown.captainBonus > 0)
              _SAbilityRow(
                color: HETheme.pfWarning,
                icon: Icons.shield_rounded,
                label: ChemistryVars.resolve(
                  'Captain — ×{captainMultiplier} a player’s chemistry',
                ),
                value: '+${breakdown.captainBonus}',
              ),
            if (breakdown.redApplied)
              _SAbilityRow(
                color: HETheme.pfDanger,
                icon: Icons.do_not_disturb_on_rounded,
                label: 'Red card — a player’s chemistry disabled',
                value: '—',
              ),
            if (breakdown.yellowPenalty > 0)
              _SAbilityRow(
                color: HETheme.pfWarning,
                icon: Icons.style_rounded,
                label: 'Yellow card — points docked',
                value: '−${breakdown.yellowPenalty}',
              ),
          ],

          const SizedBox(height: 14),
          const Divider(height: 1, color: HETheme.pfBorder),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Flexible: same spaceBetween-in-a-card shape as the card-
              // chemistry header above — a fixed label+help pair competing
              // against a fixed numeric value. "Final score" is short
              // enough to rarely tip over, but this costs nothing and
              // keeps every instance of the pattern consistently guarded.
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Flexible(
                      child: Text(
                        'Final score',
                        style: TextStyle(
                          color: HETheme.pfTextPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const InlineHelp(
                      'Your draft/chemistry score alone. Tournament bonuses '
                      '(if any) are added separately — see Final Points.',
                    ),
                  ],
                ),
              ),
              Text(
                breakdown.finalScore.toStringAsFixed(2),
                style: const TextStyle(
                  color: HETheme.pfAccentViolet,
                  fontSize: 20,
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

// ── Card chemistry detail (per-card breakdown) ────────────────────────────────

class _CardChemEntry {
  const _CardChemEntry({
    required this.name,
    required this.earned,
    required this.outOfPosition,
    required this.satisfied,
    this.redCarded = false,
    this.captain = false,
  });
  final String name;
  final int earned;
  final bool outOfPosition;
  final List<ChemistryBonus> satisfied;
  final bool redCarded;
  final bool captain;
}

/// Per-card breakdown of card chemistry on the result page — shows exactly which
/// cards earned which tiers, summing to the card-chemistry total.
class _CardChemDetailCard extends StatelessWidget {
  const _CardChemDetailCard({required this.slots});
  final List<PitchSlot> slots;

  @override
  Widget build(BuildContext context) {
    final filled = slots.where((s) => s.isFilled).toList();
    // Chemistry counts only in-position cards, and excludes red-carded cards
    // (matches the server scoring). Captained cards count ×captainMultiplier
    // (admin-configurable; see abilityEffects.captainMultiplier in
    // scoring-config.ts).
    final lineup = filled
        .where((s) => s.cardFitsSlot && !s.isRedCarded)
        .map(LineupCard.fromSlot)
        .toList();

    final entries = <_CardChemEntry>[];
    var total = 0;
    for (final s in filled) {
      final bonuses = s.cardChemistryBonuses;
      if (bonuses.isEmpty) continue;
      final counts = s.cardFitsSlot && !s.isRedCarded;
      final base = counts
          ? ChemistryEvaluator.earnedReward(bonuses, lineup)
          : 0;
      final earned = s.isCaptain ? base * 2 : base;
      total += earned;
      final satisfied = counts
          ? bonuses
                .where((b) => ChemistryEvaluator.isSatisfied(b, lineup))
                .toList()
          : <ChemistryBonus>[];
      entries.add(
        _CardChemEntry(
          name: s.cardPlayerName ?? '?',
          earned: earned,
          outOfPosition: !s.cardFitsSlot,
          satisfied: satisfied,
          redCarded: s.isRedCarded,
          captain: s.isCaptain,
        ),
      );
    }
    if (entries.isEmpty) return const SizedBox.shrink();
    entries.sort((a, b) => b.earned.compareTo(a.earned));

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: HETheme.pfSurfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HETheme.pfBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Flexible: a 26-char uppercase/letter-spaced label competing
              // against a fixed "+N" value in a spaceBetween Row is exactly
              // the shape that overflows on narrow screens — must shrink
              // rather than push the value off the edge.
              const Flexible(
                child: Text(
                  'CARD CHEMISTRY — PER CARD',
                  style: TextStyle(
                    color: HETheme.pfTextSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '+$total',
                style: const TextStyle(
                  color: HETheme.pfSuccess,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final e in entries) _CardChemRowDetail(entry: e),
        ],
      ),
    );
  }
}

class _CardChemRowDetail extends StatelessWidget {
  const _CardChemRowDetail({required this.entry});
  final _CardChemEntry entry;

  @override
  Widget build(BuildContext context) {
    final earned = entry.earned > 0;
    final detail = entry.redCarded
        ? 'Red-carded — chemistry nullified (rating only)'
        : entry.outOfPosition
        ? 'Out of position — earns no chemistry'
        : entry.satisfied.isEmpty
        ? 'No challenges met'
        : entry.satisfied.map((b) => '${b.label} (+${b.reward})').join('  ·  ');
    final nameColor = entry.redCarded || entry.outOfPosition
        ? HETheme.pfDanger
        : entry.captain
        ? HETheme.pfWarning
        : HETheme.pfTextPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entry.captain)
            const Padding(
              padding: EdgeInsets.only(right: 5, top: 1),
              child: Icon(
                Icons.shield_rounded,
                color: HETheme.pfWarning,
                size: 13,
              ),
            ),
          if (entry.redCarded)
            const Padding(
              padding: EdgeInsets.only(right: 5, top: 1),
              child: Icon(
                Icons.do_not_disturb_on_rounded,
                color: HETheme.pfDanger,
                size: 13,
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.captain ? '${entry.name}  (C ×2)' : entry.name,
                  style: TextStyle(
                    color: nameColor,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  detail,
                  style: const TextStyle(
                    color: HETheme.pfTextSecondary,
                    fontSize: 10.5,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '+${entry.earned}',
            style: TextStyle(
              color: earned ? HETheme.pfSuccess : HETheme.pfTextMuted,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _SChip extends StatelessWidget {
  const _SChip({required this.label, required this.value, this.accent = false});

  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: accent
              ? HETheme.pfAccentViolet.withValues(alpha: 0.10)
              : HETheme.pfSurfaceRaised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: accent ? HETheme.pfSecondaryViolet : HETheme.pfBorder,
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
              value,
              style: TextStyle(
                color: accent ? HETheme.pfAccentViolet : HETheme.pfTextPrimary,
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

class _SBreakdownRow extends StatelessWidget {
  const _SBreakdownRow({
    required this.checked,
    required this.label,
    required this.bonus,
  });

  final bool checked;
  final String label;
  final String bonus;

  @override
  Widget build(BuildContext context) {
    final color = checked ? HETheme.pfAccentViolet : HETheme.pfTextSecondary;
    return Row(
      children: [
        Icon(
          checked ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
          color: color,
          size: 16,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: checked ? HETheme.pfTextPrimary : HETheme.pfTextSecondary,
              fontSize: 12,
            ),
          ),
        ),
        Text(
          bonus,
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

class _SAbilityRow extends StatelessWidget {
  const _SAbilityRow({
    required this.color,
    required this.icon,
    required this.label,
    required this.value,
  });

  final Color color;
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: HETheme.pfTextPrimary, fontSize: 12),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _BestPickCard extends StatelessWidget {
  const _BestPickCard({required this.slot});

  final PitchSlot slot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: HETheme.pfSurfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: HETheme.pfGold.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: HETheme.pfGold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: HETheme.pfGold.withValues(alpha: 0.45),
              ),
            ),
            child: const Center(
              child: Text('⭐', style: TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'BEST PICK',
                  style: TextStyle(
                    color: HETheme.pfTextSecondary,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  slot.cardPlayerName ?? '—',
                  style: const TextStyle(
                    color: HETheme.pfTextPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Rating badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: HETheme.pfGold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: HETheme.pfGold.withValues(alpha: 0.45),
              ),
            ),
            child: Text(
              '${slot.cardRating ?? "—"}',
              style: const TextStyle(
                color: HETheme.pfGold,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
