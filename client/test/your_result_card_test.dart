import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/result/widgets/your_result_card.dart';
import 'package:hidden_eleven/shared/widgets/rank_medallion.dart';

void main() {
  Widget harness(Widget child) =>
      MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: child));

  const secondPlace = PlayerResult(
    playerId: 'p2',
    displayName: 'Bob',
    rank: 2,
    score: 301,
  );

  testWidgets('renders medallion, rank, and score', (tester) async {
    await tester.pumpWidget(
      harness(
        const YourResultCard(
          result: secondPlace,
          isWinner: false,
          leaderScore: 314,
        ),
      ),
    );

    expect(find.byType(RankMedallion), findsOneWidget);
    expect(find.text('#2'), findsOneWidget);
    // Stage 3 / R2: the score counts up once on mount, so the settled value
    // is asserted after the animation completes. The rank, medallion and
    // summary sentence are never animated and are present before this.
    await tester.pumpAndSettle();
    expect(find.text('301 pts'), findsOneWidget);
  });

  testWidgets(
    'friendly summary names the ordinal, score, and gap behind the leader '
    '— using only data already displayed elsewhere, no invented metric',
    (tester) async {
      await tester.pumpWidget(
        harness(
          const YourResultCard(
            result: secondPlace,
            isWinner: false,
            leaderScore: 314,
          ),
        ),
      );

      expect(
        find.text('You finished 2nd with 301 points — 13 behind the leader.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('winner phrasing never mentions being "behind" anyone', (
    tester,
  ) async {
    const champion = PlayerResult(
      playerId: 'p1',
      displayName: 'Alice',
      rank: 1,
      score: 400,
    );
    await tester.pumpWidget(
      harness(
        const YourResultCard(result: champion, isWinner: true, leaderScore: 400),
      ),
    );

    expect(find.textContaining('behind'), findsNothing);
    expect(find.textContaining('1st'), findsOneWidget);
  });

  testWidgets('omitting leaderScore drops the gap clause without crashing', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(const YourResultCard(result: secondPlace, isWinner: false)),
    );

    expect(find.text('You finished 2nd with 301 points.'), findsOneWidget);
  });
}
