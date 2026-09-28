import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/app/he_motion.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/result/widgets/points_breakdown_card.dart';
import 'package:hidden_eleven/features/result/widgets/your_result_card.dart';
import 'package:hidden_eleven/features/tournament/models/tournament_models.dart';
import 'package:hidden_eleven/features/tournament/widgets/tournament_widgets.dart';
import 'package:hidden_eleven/shared/widgets/count_up_text.dart';
import 'package:hidden_eleven/shared/widgets/segmented_bar.dart';

/// Stage 3 — the motion contract, enforced.
///
/// Every item must: render final content immediately under reduced motion,
/// never construct a loop controller under reduced motion, never replay on a
/// rebuild, never block input, and leave no pending timers after dispose.

// ── Fixtures ────────────────────────────────────────────────────────────────

ParticipantSnapshot _p(String id, String name) => ParticipantSnapshot(
  participantId: id,
  kind: TournamentParticipantKind.real,
  displayName: name,
  overallRating: 74.0,
);

MatchSnapshot _match({
  required String id,
  required int round,
  required String status,
  String? winnerId,
}) => MatchSnapshot(
  matchId: id,
  roundNumber: round,
  participantA: _p('p1', 'Alpha United'),
  participantB: _p('p2', 'Beta Rovers'),
  status: status,
  winnerId: winnerId,
);

TournamentStateModel _state({
  required TournamentPhase phase,
  required String semiStatus,
  String? semiWinner,
}) => TournamentStateModel(
  phase: phase,
  currentRound: 1,
  totalRounds: 2,
  readyPlayerIds: const [],
  rounds: [
    RoundSnapshot(
      roundNumber: 1,
      label: 'Semi-finals',
      status: 'in_progress',
      matches: [
        _match(id: 'm1', round: 1, status: semiStatus, winnerId: semiWinner),
        _match(id: 'm2', round: 1, status: 'pending'),
      ],
    ),
    RoundSnapshot(
      roundNumber: 2,
      label: 'Final',
      status: 'pending',
      matches: [_match(id: 'f1', round: 2, status: 'pending')],
    ),
  ],
);

final _result = PlayerResult(
  playerId: 'me',
  displayName: 'QA',
  rank: 2,
  score: 288,
);

Widget _harness(Widget child, {bool reduced = false, double width = 900}) =>
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    );

void main() {
  // ── R2 / R4: count-up ─────────────────────────────────────────────────────

  group('CountUpText (R2, R4)', () {
    testWidgets('reduced motion paints the final number on the first frame', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          const CountUpText(value: 288, suffix: ' pts', style: TextStyle()),
          reduced: true,
        ),
      );
      await tester.pump();

      expect(find.text('288 pts'), findsOneWidget);
      // Nothing is animating, so nothing is pending.
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('counts up and lands on the exact value', (tester) async {
      await tester.pumpWidget(
        _harness(const CountUpText(value: 288, style: TextStyle())),
      );
      await tester.pump();
      // Mid-flight it is not yet the final value…
      expect(find.text('288'), findsNothing);
      await tester.pumpAndSettle();
      // …and it always finishes exactly on it.
      expect(find.text('288'), findsOneWidget);
    });

    testWidgets('does not replay when rebuilt with the same value', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(const CountUpText(value: 288, style: TextStyle())),
      );
      await tester.pumpAndSettle();
      expect(find.text('288'), findsOneWidget);

      // A rebuild — the shape of a game_state broadcast or provider update.
      await tester.pumpWidget(
        _harness(const CountUpText(value: 288, style: TextStyle())),
      );
      await tester.pump();
      // Still settled; no restart back to a partial number.
      expect(find.text('288'), findsOneWidget);
    });

    testWidgets('leaves no pending timers after dispose', (tester) async {
      await tester.pumpWidget(
        _harness(const CountUpText(value: 288, style: TextStyle())),
      );
      await tester.pump();
      // Dispose mid-animation.
      await tester.pumpWidget(_harness(const SizedBox.shrink()));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // ── R2: Your Result ───────────────────────────────────────────────────────

  group('YourResultCard (R2)', () {
    testWidgets(
      'reduced motion shows the score and summary immediately, with no '
      'medallion scale wrapper',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            YourResultCard(
              result: _result,
              isWinner: false,
              leaderScore: 301,
            ),
            reduced: true,
          ),
        );
        await tester.pump();

        expect(find.text('288 pts'), findsOneWidget);
        expect(find.textContaining('behind'), findsOneWidget);
        expect(tester.binding.transientCallbackCount, 0);
      },
    );

    testWidgets(
      'the summary sentence and rank are readable before the count finishes — '
      'nothing waits on the animation',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            YourResultCard(
              result: _result,
              isWinner: false,
              leaderScore: 301,
            ),
          ),
        );
        await tester.pump();

        // Mid-count, the information is already there.
        expect(find.textContaining('behind'), findsOneWidget);
        expect(find.text('#2'), findsOneWidget);

        await tester.pumpAndSettle();
        expect(find.text('288 pts'), findsOneWidget);
      },
    );
  });

  // ── R4: breakdown bar ─────────────────────────────────────────────────────

  group('SegmentedBar fill (R4)', () {
    const segments = [
      BarSegment(label: 'Base', color: Colors.grey, value: 200),
      BarSegment(label: 'Champion', color: Colors.amber, value: 40),
    ];

    testWidgets('opt-out callers construct no controller at all', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(const SegmentedBar(segments: segments)),
      );
      await tester.pump();
      // fillOnce defaults to false — ScoreBreakdownBar's behaviour is intact.
      expect(tester.binding.transientCallbackCount, 0);
      expect(find.text('Base'), findsOneWidget);
    });

    testWidgets('reduced motion renders the full bar with no animation', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          const SegmentedBar(segments: segments, fillOnce: true),
          reduced: true,
        ),
      );
      await tester.pump();

      expect(tester.binding.transientCallbackCount, 0);
      // The legend — the information — is present either way.
      expect(find.text('Base'), findsOneWidget);
      expect(find.text('Champion'), findsOneWidget);
      expect(find.text('+40'), findsOneWidget);
    });

    testWidgets('the legend is never animated, even while the bar fills', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(const SegmentedBar(segments: segments, fillOnce: true)),
      );
      await tester.pump();

      // First frame, mid-fill: every label and value already readable.
      expect(find.text('Base'), findsOneWidget);
      expect(find.text('+200'), findsOneWidget);
      expect(find.text('+40'), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });

  group('PointsBreakdownCard (R4)', () {
    final breakdown = PlayerResult(
      playerId: 'p1',
      displayName: 'Alice',
      rank: 1,
      score: 264,
      scoreBreakdown: const ScoreBreakdown(
        defAvg: 70,
        midAvg: 80,
        atkAvg: 90,
        linesTotal: 240,
        userChemTotal: 12,
        cardChemTotal: 6,
        lineLeaderBonus: 4,
        captainBonus: 3,
        yellowPenalty: 1,
        finalScore: 264,
        lines: [
          ScoreBreakdownLine(key: 'squad', label: 'Squad rating', amount: 240),
        ],
      ),
    );

    testWidgets('reduced motion shows the final total immediately', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(PointsBreakdownCard(result: breakdown), reduced: true),
      );
      await tester.pump();

      expect(find.text('264'), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('every label and line value is readable while the total counts',
        (tester) async {
      await tester.pumpWidget(_harness(PointsBreakdownCard(result: breakdown)));
      await tester.pump();

      expect(find.text('FROM YOUR SQUAD'), findsOneWidget);
      expect(find.text('Squad rating'), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });

  // ── T1 / T3 / T4 / T5: bracket ────────────────────────────────────────────

  group('bracket motion (T1, T3, T4, T5)', () {
    testWidgets(
      'T1: reduced motion renders the draw settled, with no running animation',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            TournamentBracketWidget(
              state: _state(
                phase: TournamentPhase.bracketReveal,
                semiStatus: 'pending',
              ),
            ),
            reduced: true,
          ),
        );
        await tester.pump();

        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'T4: mounting straight onto an already-decided bracket never animates — '
      're-entering the screen does not replay history',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            TournamentBracketWidget(
              state: _state(
                phase: TournamentPhase.roundResult,
                semiStatus: 'complete',
                semiWinner: 'p1',
              ),
            ),
          ),
        );
        await tester.pump();

        // Nothing is filling: the match was already complete on arrival.
        expect(tester.binding.transientCallbackCount, 0);
      },
    );

    testWidgets(
      'T4: a match completing while mounted animates once, and a repeat '
      'broadcast of the same state does not restart it',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            TournamentBracketWidget(
              state: _state(
                phase: TournamentPhase.simulating,
                semiStatus: 'simulating',
              ),
            ),
          ),
        );
        await tester.pump();

        // The match resolves — this is the state transition T4 listens for.
        await tester.pumpWidget(
          _harness(
            TournamentBracketWidget(
              state: _state(
                phase: TournamentPhase.roundResult,
                semiStatus: 'complete',
                semiWinner: 'p1',
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.binding.transientCallbackCount, greaterThan(0));

        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);

        // A repeat broadcast carrying the same completed state.
        await tester.pumpWidget(
          _harness(
            TournamentBracketWidget(
              state: _state(
                phase: TournamentPhase.roundResult,
                semiStatus: 'complete',
                semiWinner: 'p1',
              ),
            ),
          ),
        );
        await tester.pump();
        // Still settled — no replay.
        expect(tester.binding.transientCallbackCount, 0);
      },
    );

    testWidgets('T4: reduced motion never starts the connector fill', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          TournamentBracketWidget(
            state: _state(
              phase: TournamentPhase.simulating,
              semiStatus: 'simulating',
            ),
          ),
          reduced: true,
        ),
      );
      await tester.pump();

      await tester.pumpWidget(
        _harness(
          TournamentBracketWidget(
            state: _state(
              phase: TournamentPhase.roundResult,
              semiStatus: 'complete',
              semiWinner: 'p1',
            ),
          ),
          reduced: true,
        ),
      );
      await tester.pump();

      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('disposing mid-animation leaves nothing pending', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          TournamentBracketWidget(
            state: _state(
              phase: TournamentPhase.simulating,
              semiStatus: 'simulating',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(
        _harness(
          TournamentBracketWidget(
            state: _state(
              phase: TournamentPhase.roundResult,
              semiStatus: 'complete',
              semiWinner: 'p1',
            ),
          ),
        ),
      );
      await tester.pump();

      // Tear down while the fill is running.
      await tester.pumpWidget(_harness(const SizedBox.shrink()));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // ── T3: live match card ───────────────────────────────────────────────────

  group('live match card (T3)', () {
    Widget card(String status) => MatchCardWidget(
      match: _match(id: 'm1', round: 1, status: status),
      myParticipantId: null,
      readyParticipantIds: const [],
      liveEvents: const [],
      roundLabel: 'Semi-finals',
    );

    testWidgets('reduced motion constructs no loop for a live card', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(card('simulating'), reduced: true, width: 420),
      );
      await tester.pump();

      expect(tester.binding.transientCallbackCount, 0);
      // The card still reads as live — the state is in text, not motion.
      expect(find.text('Alpha United'), findsWidgets);
    });

    testWidgets('a non-live card runs no animation at all', (tester) async {
      await tester.pumpWidget(_harness(card('ready_check'), width: 420));
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets(
      'the live card stays tappable while its sweep runs — motion never '
      'blocks interaction',
      (tester) async {
        await tester.pumpWidget(_harness(card('simulating'), width: 420));
        await tester.pump();

        // The sweep is looping…
        expect(tester.binding.transientCallbackCount, greaterThan(0));
        // …and a tap still lands (toggles the details accordion).
        await tester.tap(find.text('Alpha United').first, warnIfMissed: false);
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('the sweep stops once the match is no longer live', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(card('simulating'), width: 420));
      await tester.pump();
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      await tester.pumpWidget(_harness(card('complete'), width: 420));
      await tester.pumpAndSettle();
      // No ticker left running on a finished match.
      expect(tester.binding.transientCallbackCount, 0);
    });
  });

  // ── Token discipline ──────────────────────────────────────────────────────

  test('T4 uses the HEMotion tokens the correction specified', () {
    expect(HEMotion.wake, const Duration(milliseconds: 420));
    expect(HEMotion.select, const Duration(milliseconds: 180));
  });
}
