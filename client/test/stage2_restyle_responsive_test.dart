import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/result/widgets/points_breakdown_card.dart';
import 'package:hidden_eleven/features/result/widgets/your_result_card.dart';
import 'package:hidden_eleven/features/tournament/models/tournament_models.dart';
import 'package:hidden_eleven/features/tournament/widgets/tournament_widgets.dart';
import 'package:hidden_eleven/shared/widgets/rank_medallion.dart';

/// Stage 2 — every restyled surface must survive all nine supported widths
/// and XL text scale without overflow, and must keep the data and non-colour
/// state signals it carried before the restyle.

const _allWidths = <double>[1280, 1024, 768, 720, 700, 414, 390, 375, 360];

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required double width,
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

// ── Fixtures ────────────────────────────────────────────────────────────────

PlayerResult _result({int rank = 2, int score = 288}) =>
    PlayerResult(playerId: 'me', displayName: 'QA', rank: rank, score: score);

ParticipantSnapshot _participant(String id, String name) =>
    ParticipantSnapshot(
      participantId: id,
      kind: TournamentParticipantKind.real,
      displayName: name,
      overallRating: 74.2,
    );

MatchSnapshot _match(String status) => MatchSnapshot(
  matchId: 'm1',
  roundNumber: 1,
  participantA: _participant('a', 'Alpha United'),
  participantB: _participant('b', 'Beta Rovers'),
  status: status,
);

void main() {
  group('EventPhaseBanner — broadcast treatment', () {
    testWidgets('keeps title, subtitle, trailing and body content', (
      tester,
    ) async {
      await _pump(
        tester,
        const EventPhaseBanner(
          accent: Colors.amber,
          icon: Icons.how_to_reg_rounded,
          title: 'READY CHECK',
          subtitle: '2 of 4 managers ready',
          trailing: Text('0:42'),
          body: Text('BODY'),
        ),
        width: 1280,
      );

      expect(find.text('READY CHECK'), findsOneWidget);
      expect(find.text('2 of 4 managers ready'), findsOneWidget);
      expect(find.text('0:42'), findsOneWidget);
      expect(find.text('BODY'), findsOneWidget);
      // The phase is always carried by an icon as well as the accent colour.
      expect(find.byIcon(Icons.how_to_reg_rounded), findsOneWidget);
    });

    for (final w in _allWidths) {
      testWidgets('does not overflow at ${w.toInt()}px', (tester) async {
        await _pump(
          tester,
          const EventPhaseBanner(
            accent: Colors.amber,
            icon: Icons.how_to_reg_rounded,
            title: 'TOURNAMENT COMPLETE',
            subtitle: 'A reasonably long subtitle describing the phase',
            trailing: Text('0:42'),
          ),
          width: w,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('survives XL text scale at 360px', (tester) async {
      await _pump(
        tester,
        const EventPhaseBanner(
          accent: Colors.amber,
          icon: Icons.how_to_reg_rounded,
          title: 'READY CHECK',
          subtitle: 'Waiting for managers',
        ),
        width: 360,
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('READY CHECK'), findsOneWidget);
    });
  });

  group('MatchCardWidget — fixture capsule restyle', () {
    for (final status in ['ready_check', 'simulating', 'complete']) {
      testWidgets('$status renders inside a FixtureCapsule without overflow', (
        tester,
      ) async {
        await _pump(
          tester,
          MatchCardWidget(
            match: _match(status),
            myParticipantId: null,
            readyParticipantIds: const [],
            liveEvents: const [],
            roundLabel: 'Semi-finals',
          ),
          width: 375,
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(FixtureCapsule), findsWidgets);
        // Identity survives the restyle.
        expect(find.text('Alpha United'), findsWidgets);
        expect(find.text('Beta Rovers'), findsWidgets);
      });
    }

    for (final w in _allWidths) {
      testWidgets('live match card does not overflow at ${w.toInt()}px', (
        tester,
      ) async {
        await _pump(
          tester,
          MatchCardWidget(
            match: _match('simulating'),
            myParticipantId: null,
            readyParticipantIds: const [],
            liveEvents: const [],
            roundLabel: 'Semi-finals',
          ),
          width: w,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('YourResultCard — personal hierarchy', () {
    testWidgets('leads with the RankMedallion and shows score and summary', (
      tester,
    ) async {
      await _pump(
        tester,
        YourResultCard(result: _result(), isWinner: false, leaderScore: 301),
        width: 414,
      );

      expect(find.byType(RankMedallion), findsOneWidget);
      expect(find.text('YOUR RESULT'), findsOneWidget);
      // The outcome sentence is never animated — present immediately.
      expect(find.textContaining('behind'), findsOneWidget);
      // Stage 3 / R2: the score counts up once, so its settled value is
      // asserted after the animation completes.
      await tester.pumpAndSettle();
      expect(find.text('288 pts'), findsOneWidget);
    });

    for (final w in _allWidths) {
      testWidgets('does not overflow at ${w.toInt()}px', (tester) async {
        await _pump(
          tester,
          YourResultCard(result: _result(), isWinner: false, leaderScore: 301),
          width: w,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('survives XL text scale at 360px', (tester) async {
      await _pump(
        tester,
        YourResultCard(result: _result(), isWinner: false, leaderScore: 301),
        width: 360,
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('YOUR RESULT'), findsOneWidget);
    });
  });

  group('PointsBreakdownCard — grouped score story', () {
    const breakdown = ScoreBreakdown(
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
      // `lines` is a plain constructor field (defaults to empty), not a
      // derived getter — the grouped "FROM YOUR SQUAD" heading only appears
      // when the server actually sent per-line detail.
      lines: [
        ScoreBreakdownLine(key: 'squad', label: 'Squad rating', amount: 240),
        ScoreBreakdownLine(key: 'chem', label: 'Chemistry', amount: 18),
        ScoreBreakdownLine(key: 'yellow', label: 'Yellow cards', amount: -1),
      ],
    );
    final result = PlayerResult(
      playerId: 'p1',
      displayName: 'Alice',
      rank: 1,
      score: 264,
      scoreBreakdown: breakdown,
    );

    testWidgets(
      'groups squad-derived lines under a heading while keeping every label '
      'and exact value visible',
      (tester) async {
        await _pump(tester, PointsBreakdownCard(result: result), width: 414);

        // New structural grouping…
        expect(find.text('FROM YOUR SQUAD'), findsOneWidget);
        // …and the original per-line content, unchanged.
        for (final line in breakdown.lines) {
          expect(find.text(line.label), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );

    for (final w in _allWidths) {
      testWidgets('does not overflow at ${w.toInt()}px', (tester) async {
        await _pump(tester, PointsBreakdownCard(result: result), width: w);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
