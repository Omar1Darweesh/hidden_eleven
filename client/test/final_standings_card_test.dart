import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/result/widgets/final_standings_card.dart';

/// Phase B: the champion row gets a restrained gold-tinted resting
/// background, and the current-player row gets a persistent left accent bar
/// — independent of (not a replacement for) the existing tap-to-select
/// violet highlight.
void main() {
  Widget harness(Widget child) =>
      MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: child));

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
  );

  const rankMap = {
    'p1': PlayerResult(playerId: 'p1', displayName: 'Alice', rank: 1, score: 300),
    'p2': PlayerResult(playerId: 'p2', displayName: 'Bob', rank: 2, score: 250),
  };

  testWidgets(
    'the champion row (rank 1) carries a distinct background from a '
    'non-champion row, even with nothing selected',
    (tester) async {
      await tester.pumpWidget(
        harness(
          FinalStandingsCard(
            game: game,
            orderedIds: const ['p1', 'p2'],
            localPlayerId: 'p2', // neither row is "isLocal" for p1 here
            rankMap: rankMap,
            selectedPlayerId: null,
            onTap: (_) {},
          ),
        ),
      );

      final containers = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.decoration is BoxDecoration)
          .map((c) => (c.decoration as BoxDecoration).color)
          .whereType<Color>()
          .toList();

      expect(
        containers.any((c) => c == HETheme.pfGold.withValues(alpha: 0.06)),
        isTrue,
        reason: 'expected the champion row\'s gold-tinted resting background',
      );
    },
  );

  testWidgets(
    'the current-player row shows a violet accent bar independent of '
    'selection state (isSelected: false)',
    (tester) async {
      await tester.pumpWidget(
        harness(
          FinalStandingsCard(
            game: game,
            orderedIds: const ['p1', 'p2'],
            localPlayerId: 'p2',
            rankMap: rankMap,
            selectedPlayerId: null, // nothing selected — isolates the effect
            onTap: (_) {},
          ),
        ),
      );

      // "(you)" suffix confirms which row is the local player.
      expect(find.text('Bob (you)'), findsOneWidget);

      // The accent bar is a 3px-wide Positioned strip — its width is the
      // distinguishing trait among this row's widgets (nothing else in a
      // standings row is a fixed 3px-wide Positioned element).
      final accentBars = tester
          .widgetList<Positioned>(find.byType(Positioned))
          .where((p) => p.width == 3);
      expect(accentBars, isNotEmpty);
    },
  );
}
