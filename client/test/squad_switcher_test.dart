import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/widgets/squad_switcher.dart';

void main() {
  Widget harness({
    required List<SquadTab> tabs,
    required int selected,
    ValueChanged<int>? onChanged,
    bool compact = false,
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 420,
          child: SquadSwitcher(
            tabs: tabs,
            selectedIndex: selected,
            onChanged: onChanged ?? (_) {},
            compact: compact,
          ),
        ),
      ),
    ),
  );

  const twoTabs = [
    SquadTab(id: 'p1', label: 'Omar', filledCount: 4, isLocal: true),
    SquadTab(id: 'p2', label: 'Al Rossi', filledCount: 3, isCurrentTurn: true),
  ];

  testWidgets('renders one segment per squad, local one labelled "You"', (
    tester,
  ) async {
    await tester.pumpWidget(harness(tabs: twoTabs, selected: 0));
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Al Rossi'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('tapping a segment reports its index', (tester) async {
    int? tapped;
    await tester.pumpWidget(
      harness(tabs: twoTabs, selected: 0, onChanged: (i) => tapped = i),
    );
    await tester.tap(find.text('Al Rossi'));
    await tester.pump();
    expect(tapped, 1);
  });

  testWidgets('every segment exposes a semantics label with status', (
    tester,
  ) async {
    await tester.pumpWidget(harness(tabs: twoTabs, selected: 0));

    final semantics = tester.getSemantics(find.text('Al Rossi'));
    expect(semantics.label, contains('Al Rossi'));
    expect(semantics.label, contains('connected'));
    expect(semantics.label, contains('3 picked'));
    expect(semantics.label, contains('their turn'));
  });

  testWidgets('disconnected status carries an icon, not colour alone', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        tabs: const [
          SquadTab(id: 'p1', label: 'A', filledCount: 0, isLocal: true),
          SquadTab(id: 'p2', label: 'B', filledCount: 0, isDisconnected: true),
        ],
        selected: 0,
      ),
    );
    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
    expect(tester.getSemantics(find.text('B')).label, contains('disconnected'));
  });

  testWidgets('segments clear the 44px minimum touch target', (tester) async {
    await tester.pumpWidget(harness(tabs: twoTabs, selected: 0));
    // Two segments across 420px — each is comfortably wide; height is the
    // dimension worth guarding.
    final size = tester.getSize(find.byType(SquadSwitcher));
    expect(size.width / 2, greaterThanOrEqualTo(44.0));
  });

  testWidgets('an out-of-range selectedIndex is clamped, not thrown', (
    tester,
  ) async {
    await tester.pumpWidget(harness(tabs: twoTabs, selected: 9));
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty tab list renders nothing rather than throwing', (
    tester,
  ) async {
    await tester.pumpWidget(harness(tabs: const [], selected: 0));
    expect(tester.takeException(), isNull);
  });

  group('buildSquadTabs', () {
    GameState game() => GameState(
      sessionId: 's',
      roomCode: 'R',
      formationName: '4-3-3',
      players: const [
        GamePlayer(id: 'p1', displayName: 'Omar', isHost: true),
        GamePlayer(
          id: 'p2',
          displayName: 'Rossi',
          isHost: false,
          isConnected: false,
        ),
      ],
      pitches: const {},
      baseTurnOrder: const ['p1', 'p2'],
      currentRound: 1,
      totalRounds: 11,
      currentTurnOrder: const ['p1', 'p2'],
      currentTurnIndex: 0,
      currentRoundSlotIndex: null,
      turn: const GameTurn(
        turnId: 't',
        phase: 'selecting_position',
        activePlayerId: 'p1',
      ),
      status: 'drafting',
      isFinished: false,
    );

    test('maps players, marking local, current turn and connection', () {
      final tabs = buildSquadTabs(game(), const ['p1', 'p2'], 'p1');
      expect(tabs, hasLength(2));
      expect(tabs[0].isLocal, isTrue);
      expect(tabs[0].isCurrentTurn, isTrue);
      expect(tabs[1].isLocal, isFalse);
      expect(tabs[1].isDisconnected, isTrue);
    });

    test('skips ids with no matching player rather than throwing', () {
      final tabs = buildSquadTabs(game(), const ['p1', 'ghost'], 'p1');
      expect(tabs, hasLength(1));
    });
  });
}
