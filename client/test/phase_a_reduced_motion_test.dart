import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/result/widgets/result_hero_summary.dart';
import 'package:hidden_eleven/features/tournament/models/tournament_models.dart';
import 'package:hidden_eleven/features/tournament/providers/tournament_provider.dart';
import 'package:hidden_eleven/features/tournament/screens/tournament_complete_screen.dart';
import 'package:hidden_eleven/features/tournament/widgets/tournament_widgets.dart';

/// Phase A adds `HEMotion.reduced(context)` gating to every pre-existing
/// Tournament/Results animation (see the Phase A plan's "reduced-motion
/// protection" table) — these were all previously ungated. Each test below
/// pumps the affected widget under `MediaQueryData(disableAnimations: true)`
/// and asserts the FINAL content is visible immediately, without needing
/// `pumpAndSettle` on a still-running animation, and that nothing previously
/// visible becomes hidden.
void main() {
  Widget reducedMotionApp(Widget child) => MediaQuery(
    data: const MediaQueryData(disableAnimations: true),
    child: MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: child)),
  );

  group('Reduced motion — MatchCardWidget live pulsing badge', () {
    testWidgets(
      'a simulating match renders its live status immediately, statically '
      '— no mid-pulse frame, nothing hidden',
      (tester) async {
        final match = MatchSnapshot(
          matchId: 'm1',
          roundNumber: 1,
          participantA: const ParticipantSnapshot(
            participantId: 'p1',
            kind: TournamentParticipantKind.real,
            displayName: 'Player One',
            overallRating: 75.0,
          ),
          participantB: const ParticipantSnapshot(
            participantId: 'p2',
            kind: TournamentParticipantKind.real,
            displayName: 'Player Two',
            overallRating: 75.0,
          ),
          status: 'simulating',
        );

        await tester.pumpWidget(
          reducedMotionApp(
            MatchCardWidget(
              match: match,
              myParticipantId: null,
              readyParticipantIds: const [],
              liveEvents: const [],
              completedResult: null,
            ),
          ),
        );

        // No pumpAndSettle needed — a genuinely running repeat(reverse: true)
        // controller would never settle, so a single pump proves there is
        // no ticking animation left outstanding: pumpAndSettle would time
        // out if _PulsingBadge still constructed and repeated its own
        // AnimationController under reduced motion.
        await tester.pumpAndSettle();
        expect(find.text('0  —  0'), findsOneWidget);
      },
    );
  });

  group('Reduced motion — ResultHeroSummary entrance', () {
    testWidgets(
      // Phase B moved the "Your Result" bar out of the hero and into its own
      // YourResultCard (rendered by result_screen.dart, not the hero) — this
      // test now covers only what the hero itself renders.
      'winner content and trophy render immediately with no pump needed to '
      'let the entrance animation finish',
      (tester) async {
        const game = GameState(
          sessionId: 's1',
          roomCode: 'RM1',
          formationName: '4-3-3',
          players: [
            GamePlayer(id: 'p1', displayName: 'Alice', isHost: true),
            GamePlayer(id: 'p2', displayName: 'Bob', isHost: false),
          ],
          pitches: {},
          baseTurnOrder: ['p1', 'p2'],
          currentRound: 12,
          totalRounds: 11,
          currentTurnOrder: ['p1', 'p2'],
          currentTurnIndex: 0,
          currentRoundSlotIndex: null,
          turn: GameTurn(turnId: 't1', phase: 'result', activePlayerId: ''),
          status: 'finished',
          isFinished: true,
          result: GameResult(
            reason: 'completed',
            players: [
              PlayerResult(playerId: 'p1', displayName: 'Alice', rank: 1, score: 250),
              PlayerResult(playerId: 'p2', displayName: 'Bob', rank: 2, score: 190),
            ],
          ),
        );

        await tester.pumpWidget(
          reducedMotionApp(
            const ResultHeroSummary(game: game, localPlayerId: 'p1'),
          ),
        );

        // A single pump (widget build), no pumpAndSettle — the 1100ms
        // AnimationController would otherwise still be mid-flight here.
        expect(find.text('You Win!'), findsOneWidget);
      },
    );
  });

  group('Reduced motion — TournamentCompleteScreen', () {
    testWidgets(
      'champion, runner-up, and points sections are all visible on the '
      'first frame — no staggered delay to wait out',
      (tester) async {
        const awards = TournamentAwardsModel(
          champion: ParticipantSnapshot(
            participantId: 'p1',
            kind: TournamentParticipantKind.real,
            displayName: 'Champion Player',
            overallRating: 80.0,
          ),
          runnerUp: ParticipantSnapshot(
            participantId: 'p2',
            kind: TournamentParticipantKind.real,
            displayName: 'Runner Up Player',
            overallRating: 78.0,
          ),
          pointsAwarded: {'p1': 50, 'p2': 20},
        );

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: ProviderScope(
              overrides: [
                tournamentCompleteProvider.overrideWith((ref) => awards),
                myParticipantIdProvider.overrideWith((ref) => 'p1'),
              ],
              child: const MaterialApp(home: TournamentCompleteScreen()),
            ),
          ),
        );

        // Single pump only — the real controller (600ms trophy pop, then
        // +100ms/+500ms staggered Future.delayed reveals) would otherwise
        // leave champion/points still hidden at this point.
        await tester.pump();

        expect(find.textContaining('Champion Player'), findsWidgets);
        expect(find.textContaining('+50 pts'), findsOneWidget);
      },
    );
  });
}
