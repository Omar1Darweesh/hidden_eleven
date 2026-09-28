import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/tournament/models/tournament_models.dart';
import 'package:hidden_eleven/features/tournament/providers/tournament_provider.dart';
import 'package:hidden_eleven/features/tournament/widgets/tournament_widgets.dart';
import 'package:hidden_eleven/shared/widgets/rank_medallion.dart';

// ── Mock data fixtures ─────────────────────────────────────────────────────────

// A real participant snapshot.
ParticipantSnapshot _makeParticipant(String id, String name) =>
    ParticipantSnapshot(
      participantId: id,
      kind: TournamentParticipantKind.real,
      displayName: name,
      overallRating: 75.0,
    );

// A match snapshot with two real participants.
MatchSnapshot _makeMatch({
  required String matchId,
  required String status,
  String participantAId = 'p1',
  String participantBId = 'p2',
  CompletedMatchSnapshot? result,
  String? winnerId,
}) => MatchSnapshot(
  matchId: matchId,
  roundNumber: 1,
  participantA: _makeParticipant(participantAId, 'Player One'),
  participantB: _makeParticipant(participantBId, 'Player Two'),
  status: status,
  result: result,
  winnerId: winnerId,
);

// A round snapshot.
RoundSnapshot _makeRound(List<MatchSnapshot> matches) => RoundSnapshot(
  roundNumber: 1,
  label: 'Semi-finals',
  status: 'in_progress',
  matches: matches,
);

// A minimal TournamentStateModel.
// ignore: unused_element
TournamentStateModel _makeState({
  required TournamentPhase phase,
  List<String> readyPlayerIds = const [],
  int currentRound = 1,
  List<RoundSnapshot>? rounds,
}) => TournamentStateModel(
  phase: phase,
  currentRound: currentRound,
  totalRounds: 2,
  readyPlayerIds: readyPlayerIds,
  readyDeadlineAt: phase == TournamentPhase.readyCheck
      ? DateTime.now().millisecondsSinceEpoch + 60000
      : null,
  bracketRevealAt: phase == TournamentPhase.bracketReveal
      ? DateTime.now().millisecondsSinceEpoch + 8000
      : null,
  rounds:
      rounds ??
      [
        _makeRound([_makeMatch(matchId: 'r1_m1', status: 'ready_check')]),
      ],
);

// A minimal TournamentAwardsModel.
TournamentAwardsModel _makeAwards() => TournamentAwardsModel(
  champion: _makeParticipant('p1', 'Champion Player'),
  runnerUp: _makeParticipant('p2', 'Runner Up Player'),
  topScorer: const [
    TopScorerEntry(
      playerName: 'Salah',
      participantId: 'p1',
      goals: 4,
      minutesPlayed: 360,
    ),
  ],
  pointsAwarded: {'p1': 50, 'p2': 20},
);

void main() {
  // Wraps a widget in ProviderScope + MaterialApp with overrides.
  // `Override` is not a named public type in this Riverpod version (override
  // instances come from `provider.overrideWith(...)`), so the param is typed
  // loosely and `.cast()` recovers the concrete element type from context.
  Widget buildWithProviders(
    Widget widget, {
    List<Object> overrides = const [],
  }) {
    return ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: widget),
      ),
    );
  }

  group('MatchCardWidget — Ready button visibility', () {
    testWidgets('shows Ready button when it is my match and I am not ready', (
      tester,
    ) async {
      final match = _makeMatch(
        matchId: 'r1_m1',
        status: 'ready_check',
        participantAId: 'p1',
        participantBId: 'p2',
      );

      await tester.pumpWidget(
        buildWithProviders(
          MatchCardWidget(
            match: match,
            myParticipantId: 'p1',
            readyParticipantIds: const [],
            liveEvents: const [],
            completedResult: null,
          ),
        ),
      );

      expect(find.text('Ready ✓'), findsOneWidget);
      expect(find.text('Waiting for opponent...'), findsNothing);
    });

    testWidgets(
      'hides Ready button and shows waiting text when already ready',
      (tester) async {
        final match = _makeMatch(
          matchId: 'r1_m1',
          status: 'ready_check',
          participantAId: 'p1',
          participantBId: 'p2',
        );

        await tester.pumpWidget(
          buildWithProviders(
            MatchCardWidget(
              match: match,
              myParticipantId: 'p1',
              readyParticipantIds: const ['p1'],
              liveEvents: const [],
              completedResult: null,
            ),
          ),
        );

        expect(find.text('Ready ✓'), findsNothing);
        expect(find.text('Waiting for opponent...'), findsOneWidget);
      },
    );

    testWidgets('hides Ready button for a player not in this match', (
      tester,
    ) async {
      final match = _makeMatch(
        matchId: 'r1_m1',
        status: 'ready_check',
        participantAId: 'p1',
        participantBId: 'p2',
      );

      await tester.pumpWidget(
        buildWithProviders(
          MatchCardWidget(
            match: match,
            myParticipantId: 'p3', // eliminated player — not in this match
            readyParticipantIds: const [],
            liveEvents: const [],
            completedResult: null,
          ),
        ),
      );

      expect(find.text('Ready ✓'), findsNothing);
      expect(find.text('Waiting for opponent...'), findsNothing);
    });

    testWidgets('Ready button disabled after press (local state)', (
      tester,
    ) async {
      bool readyCalled = false;
      final match = _makeMatch(
        matchId: 'r1_m1',
        status: 'ready_check',
        participantAId: 'p1',
        participantBId: 'p2',
      );

      await tester.pumpWidget(
        buildWithProviders(
          MatchCardWidget(
            match: match,
            myParticipantId: 'p1',
            readyParticipantIds: const [],
            liveEvents: const [],
            completedResult: null,
            onReady: () => readyCalled = true,
          ),
        ),
      );

      await tester.tap(find.text('Ready ✓'));
      await tester.pump();

      expect(readyCalled, isTrue);
      // After pressing, button should be gone (local _readyPressed = true).
      expect(find.text('Ready ✓'), findsNothing);
    });
  });

  group('MatchCardWidget — Live score display', () {
    testWidgets('shows live score from liveEvents during simulating', (
      tester,
    ) async {
      final match = _makeMatch(matchId: 'r1_m1', status: 'simulating');
      final event = LiveMatchEvent(
        matchId: 'r1_m1',
        roundNumber: 1,
        minute: 67,
        type: 'goal',
        teamParticipantId: 'p1',
        playerName: 'Salah',
        playerRating: 8.5,
        currentScoreA: 2,
        currentScoreB: 1,
      );

      await tester.pumpWidget(
        buildWithProviders(
          MatchCardWidget(
            match: match,
            myParticipantId: null,
            readyParticipantIds: const [],
            liveEvents: [event],
            completedResult: null,
          ),
        ),
      );

      // The redesigned broadcast-style card renders the score with an em dash.
      expect(find.text('2  —  1'), findsOneWidget);
    });

    testWidgets(
      'penalty shootout strip appears once kicks start and updates its tally '
      'kick-by-kick — the card must never look stuck on the same text',
      (tester) async {
        final match = _makeMatch(
          matchId: 'r1_m1',
          status: 'simulating',
          participantAId: 'p1',
          participantBId: 'p2',
        );

        Widget cardWith(List<LiveMatchEvent> events) => buildWithProviders(
          MatchCardWidget(
            match: match,
            myParticipantId: null,
            readyParticipantIds: const [],
            liveEvents: events,
            completedResult: null,
          ),
        );

        // Regulation ends level — no shootout strip yet.
        await tester.pumpWidget(
          cardWith([
            LiveMatchEvent(
              matchId: 'r1_m1',
              roundNumber: 1,
              minute: 80,
              type: 'goal',
              teamParticipantId: 'p1',
              playerName: 'Salah',
              playerRating: 8.0,
              currentScoreA: 1,
              currentScoreB: 1,
            ),
          ]),
        );
        expect(find.textContaining('PENS'), findsNothing);

        // First penalty kick arrives — the strip appears with a 1-0 tally.
        await tester.pumpWidget(
          cardWith([
            LiveMatchEvent(
              matchId: 'r1_m1',
              roundNumber: 1,
              minute: 80,
              type: 'goal',
              teamParticipantId: 'p1',
              playerName: 'Salah',
              playerRating: 8.0,
              currentScoreA: 1,
              currentScoreB: 1,
            ),
            LiveMatchEvent(
              matchId: 'r1_m1',
              roundNumber: 1,
              minute: 121,
              type: 'penalty_scored',
              teamParticipantId: 'p1',
              playerName: 'Kicker A1',
              playerRating: 7.5,
              currentScoreA: 1,
              currentScoreB: 1,
            ),
          ]),
        );
        expect(find.text('PENS 1–0'), findsOneWidget);

        // A second kick (the opponent scores too) — the tally visibly moves
        // to 1-1, proving the card updates instead of freezing on "1-0".
        await tester.pumpWidget(
          cardWith([
            LiveMatchEvent(
              matchId: 'r1_m1',
              roundNumber: 1,
              minute: 80,
              type: 'goal',
              teamParticipantId: 'p1',
              playerName: 'Salah',
              playerRating: 8.0,
              currentScoreA: 1,
              currentScoreB: 1,
            ),
            LiveMatchEvent(
              matchId: 'r1_m1',
              roundNumber: 1,
              minute: 121,
              type: 'penalty_scored',
              teamParticipantId: 'p1',
              playerName: 'Kicker A1',
              playerRating: 7.5,
              currentScoreA: 1,
              currentScoreB: 1,
            ),
            LiveMatchEvent(
              matchId: 'r1_m1',
              roundNumber: 1,
              minute: 122,
              type: 'penalty_scored',
              teamParticipantId: 'p2',
              playerName: 'Kicker B1',
              playerRating: 7.0,
              currentScoreA: 1,
              currentScoreB: 1,
            ),
          ]),
        );
        expect(find.text('PENS 1–0'), findsNothing);
        expect(find.text('PENS 1–1'), findsOneWidget);
      },
    );
  });

  group('CountdownTimerWidget', () {
    testWidgets(
      'displays countdown and collapses once the deadline has passed',
      (tester) async {
        // A future deadline shows a live countdown.
        // NOTE: the widget reads the real wall clock (DateTime.now()), which
        // tester.pump(Duration) does NOT advance — it only drives the Timer
        // scheduler. So the "reached zero" state is verified via a deadline that
        // is already in the past (which hits the widget's own clamp-to-zero →
        // SizedBox.shrink path), rather than by pumping fake time forward.
        final future = DateTime.now().millisecondsSinceEpoch + 5000;
        await tester.pumpWidget(
          buildWithProviders(
            CountdownTimerWidget(deadlineEpochMs: future, label: 'Starts in'),
          ),
        );
        expect(find.textContaining('Starts in'), findsOneWidget);

        // A deadline in the past → the timer has effectively hit zero and the
        // widget renders nothing.
        final past = DateTime.now().millisecondsSinceEpoch - 1000;
        await tester.pumpWidget(
          buildWithProviders(
            CountdownTimerWidget(deadlineEpochMs: past, label: 'Starts in'),
          ),
        );
        await tester.pump();
        expect(find.textContaining('Starts in'), findsNothing);
      },
    );

    testWidgets('renders nothing when deadlineEpochMs is null', (tester) async {
      await tester.pumpWidget(
        buildWithProviders(
          const CountdownTimerWidget(deadlineEpochMs: null, label: 'Starts in'),
        ),
      );

      expect(find.textContaining('Starts in'), findsNothing);
    });
  });

  group('TournamentResultBanner', () {
    testWidgets('renders nothing when tournamentCompleteProvider is null', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildWithProviders(
          const TournamentResultBanner(),
          overrides: [
            tournamentCompleteProvider.overrideWith((ref) => null),
            myParticipantIdProvider.overrideWith((ref) => null),
          ],
        ),
      );

      expect(find.text('TOURNAMENT RESULT'), findsNothing);
      expect(find.byType(TournamentResultBanner), findsOneWidget);
      // Verify it has no height (collapsed).
      final size = tester.getSize(find.byType(TournamentResultBanner));
      expect(size.height, equals(0.0));
    });

    testWidgets('shows champion and runner-up names when awards present', (
      tester,
    ) async {
      final awards = _makeAwards();

      await tester.pumpWidget(
        buildWithProviders(
          const TournamentResultBanner(),
          overrides: [
            tournamentCompleteProvider.overrideWith((ref) => awards),
            myParticipantIdProvider.overrideWith((ref) => null),
          ],
        ),
      );

      expect(find.textContaining('Champion Player'), findsAtLeastNWidgets(1));
      expect(find.textContaining('Runner Up Player'), findsAtLeastNWidgets(1));
      expect(find.text('TOURNAMENT RESULT'), findsOneWidget);
      // Phase 4: Champion/Runner-up placement uses RankMedallion, not
      // medal emoji.
      expect(find.byType(RankMedallion), findsNWidgets(2));
      expect(find.textContaining('🥇'), findsNothing);
      expect(find.textContaining('🥈'), findsNothing);
    });

    testWidgets('shows points earned when current player is champion', (
      tester,
    ) async {
      final awards = _makeAwards(); // p1 is champion with 50 points

      await tester.pumpWidget(
        buildWithProviders(
          const TournamentResultBanner(),
          overrides: [
            tournamentCompleteProvider.overrideWith((ref) => awards),
            myParticipantIdProvider.overrideWith((ref) => 'p1'),
          ],
        ),
      );

      expect(find.textContaining('+50'), findsOneWidget);
      expect(find.textContaining('points'), findsOneWidget);
    });

    testWidgets('hides points section when current player earned none', (
      tester,
    ) async {
      final awards = _makeAwards(); // points only for p1 and p2

      await tester.pumpWidget(
        buildWithProviders(
          const TournamentResultBanner(),
          overrides: [
            tournamentCompleteProvider.overrideWith((ref) => awards),
            myParticipantIdProvider.overrideWith(
              (ref) => 'p3',
            ), // spectator, no points
          ],
        ),
      );

      expect(find.textContaining('earned'), findsNothing);
      expect(find.textContaining('+50'), findsNothing);
    });
  });

  // Phase A: migrated the six un-migrated Tournament files from legacy
  // HEColors/raw hex onto HETheme.pf* tokens. Rather than scanning source
  // text for color literals (brittle, breaks on reformatting, doesn't test
  // behavior), these tests pump the real widgets and assert the *rendered*
  // color for each of the five meaningful event-state categories resolves
  // to the correct token.
  group('Phase A — event-state semantic color mapping', () {
    testWidgets('goal / success maps to pfSuccess (winner-advances banner)', (
      tester,
    ) async {
      final match = _makeMatch(
        matchId: 'r1_m1',
        status: 'complete',
        participantAId: 'p1',
        participantBId: 'p2',
        winnerId: 'p1',
      );

      await tester.pumpWidget(
        buildWithProviders(
          MatchCardWidget(
            match: match,
            myParticipantId: null,
            readyParticipantIds: const [],
            liveEvents: const [],
            completedResult: null,
          ),
        ),
      );

      final banner = tester.widget<Text>(find.textContaining('advances'));
      expect(banner.style?.color, HETheme.pfSuccess);
    });

    testWidgets('yellow card / warning maps to pfWarning', (tester) async {
      const event = LiveMatchEvent(
        matchId: 'm1',
        roundNumber: 1,
        minute: 45,
        type: 'yellow_card',
        teamParticipantId: 'p1',
        playerName: 'Defender',
        playerRating: 7.0,
        currentScoreA: 0,
        currentScoreB: 0,
      );

      await tester.pumpWidget(
        buildWithProviders(
          const TournamentEventFeedItem(event: event, isTeamA: true),
        ),
      );

      final minuteLabel = tester.widget<Text>(find.text("45'"));
      expect(minuteLabel.style?.color, HETheme.pfWarning);
    });

    testWidgets(
      'red card / danger maps to pfDanger, matching missed penalty',
      (tester) async {
        const redCard = LiveMatchEvent(
          matchId: 'm1',
          roundNumber: 1,
          minute: 60,
          type: 'red_card',
          teamParticipantId: 'p1',
          playerName: 'Defender',
          playerRating: 6.0,
          currentScoreA: 0,
          currentScoreB: 0,
        );

        await tester.pumpWidget(
          buildWithProviders(
            const TournamentEventFeedItem(event: redCard, isTeamA: true),
          ),
        );

        final minuteLabel = tester.widget<Text>(find.text("60'"));
        expect(minuteLabel.style?.color, HETheme.pfDanger);
      },
    );

    testWidgets(
      'informational / in-progress ("complete" status badge) maps to '
      'pfAccentViolet',
      (tester) async {
        final match = _makeMatch(matchId: 'r1_m1', status: 'complete');

        await tester.pumpWidget(
          buildWithProviders(
            MatchCardWidget(
              match: match,
              myParticipantId: null,
              readyParticipantIds: const [],
              liveEvents: const [],
              completedResult: null,
            ),
          ),
        );

        final badge = tester.widget<Text>(find.text('FT'));
        expect(badge.style?.color, HETheme.pfAccentViolet);
      },
    );

    testWidgets(
      'pending / muted (TBD bracket slot) uses the pfSurfaceRaised surface',
      (tester) async {
        final state = _makeState(
          phase: TournamentPhase.readyCheck,
          rounds: [
            _makeRound([
              _makeMatch(
                matchId: 'r1_m1',
                status: 'ready_check',
                participantAId: '',
                participantBId: '',
              ),
            ]),
            _makeRound([
              _makeMatch(
                matchId: 'r2_m1',
                status: 'ready_check',
                participantAId: '',
                participantBId: '',
              ),
            ]),
          ],
        );

        await tester.pumpWidget(
          buildWithProviders(
            SizedBox(
              width: 400,
              child: TournamentBracketWidget(state: state),
            ),
          ),
        );

        final tbdChip = tester
            .widgetList<Container>(find.byType(Container))
            .firstWhere(
              (c) =>
                  c.decoration is BoxDecoration &&
                  (c.decoration as BoxDecoration).color ==
                      HETheme.pfSurfaceRaised,
            );
        expect(
          (tbdChip.decoration as BoxDecoration).color,
          HETheme.pfSurfaceRaised,
        );
      },
    );
  });

  // Phase B: the bracket switches to a horizontally-scrolling mobile strip
  // below HETheme.breakpointMobile (700px) and keeps the existing
  // side-by-side halves at/above it — and every slot's Scheduled/Live/
  // Eliminated treatment is shared between both layouts (see
  // _BracketSlotCard, reused by both).
  group('Phase B — bracket responsive layout and state tags', () {
    TournamentStateModel twoRoundState({required String semiStatus}) =>
        _makeState(
          phase: TournamentPhase.readyCheck,
          rounds: [
            _makeRound([
              _makeMatch(matchId: 'r1_m1', status: semiStatus),
            ]),
            _makeRound([
              _makeMatch(
                matchId: 'r2_m1',
                status: 'ready_check',
                participantAId: '',
                participantBId: '',
              ),
            ]),
          ],
        );

    testWidgets(
      'at >= 700px width, both bracket halves render simultaneously '
      '(the desktop side-by-side layout)',
      (tester) async {
        await tester.pumpWidget(
          buildWithProviders(
            SizedBox(
              width: 900,
              child: TournamentBracketWidget(
                state: twoRoundState(semiStatus: 'ready_check'),
              ),
            ),
          ),
        );

        // The desktop layout renders a ListView nowhere — its absence is the
        // signal that the mobile strip did not activate at this width.
        expect(find.byType(ListView), findsNothing);
      },
    );

    testWidgets(
      'below 700px width, the bracket becomes a horizontally-scrolling '
      'ListView (never a PageView, which would fight vertical page scroll)',
      (tester) async {
        await tester.pumpWidget(
          buildWithProviders(
            SizedBox(
              width: 400,
              child: TournamentBracketWidget(
                state: twoRoundState(semiStatus: 'ready_check'),
              ),
            ),
          ),
        );

        final list = tester.widget<ListView>(find.byType(ListView));
        expect(list.scrollDirection, Axis.horizontal);
        expect(find.byType(PageView), findsNothing);
      },
    );

    testWidgets(
      'a known, not-yet-started participant gets a static "NEXT" tag — '
      'full identity shown, not a grey TBD box',
      (tester) async {
        await tester.pumpWidget(
          buildWithProviders(
            SizedBox(
              width: 400,
              child: TournamentBracketWidget(
                state: twoRoundState(semiStatus: 'ready_check'),
              ),
            ),
          ),
        );

        expect(find.text('NEXT'), findsWidgets);
        expect(find.text('Player One'), findsOneWidget);
      },
    );

    testWidgets('a live match gets a static "LIVE" tag', (tester) async {
      await tester.pumpWidget(
        buildWithProviders(
          SizedBox(
            width: 400,
            child: TournamentBracketWidget(
              state: twoRoundState(semiStatus: 'simulating'),
            ),
          ),
        ),
      );

      expect(find.text('LIVE'), findsWidgets);
    });

    testWidgets(
      'an eliminated participant is both dimmed (Opacity) and carries an '
      'explicit "OUT" tag — state is never conveyed by dimming alone',
      (tester) async {
        final state = _makeState(
          phase: TournamentPhase.roundResult,
          rounds: [
            _makeRound([
              _makeMatch(
                matchId: 'r1_m1',
                status: 'complete',
                winnerId: 'p1',
              ),
            ]),
            _makeRound([
              _makeMatch(
                matchId: 'r2_m1',
                status: 'ready_check',
                participantAId: '',
                participantBId: '',
              ),
            ]),
          ],
        );

        await tester.pumpWidget(
          buildWithProviders(
            SizedBox(width: 900, child: TournamentBracketWidget(state: state)),
          ),
        );

        expect(find.text('OUT'), findsWidgets);
        final opacity = tester.widget<Opacity>(
          find
              .ancestor(of: find.text('OUT'), matching: find.byType(Opacity))
              .first,
        );
        expect(opacity.opacity, lessThan(1.0));
      },
    );

    testWidgets(
      'the final column/centre reads "FINAL — LIVE" while the final match '
      'is simulating, distinct from the pre-live and complete labels',
      (tester) async {
        final state = _makeState(
          phase: TournamentPhase.simulating,
          rounds: [
            _makeRound([_makeMatch(matchId: 'r1_m1', status: 'complete', winnerId: 'p1')]),
            _makeRound([
              _makeMatch(
                matchId: 'r2_m1',
                status: 'simulating',
                participantAId: 'p1',
                participantBId: 'p2',
              ),
            ]),
          ],
        );

        await tester.pumpWidget(
          buildWithProviders(
            SizedBox(width: 900, child: TournamentBracketWidget(state: state)),
          ),
        );

        expect(find.textContaining('LIVE'), findsWidgets);
      },
    );
  });
}
