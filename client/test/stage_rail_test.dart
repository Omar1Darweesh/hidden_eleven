import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/tournament/widgets/stage_rail.dart';

const _stages = [
  TournamentStage(label: 'Draw', done: true),
  TournamentStage(label: 'Semis', done: false),
  TournamentStage(label: 'Final', done: false),
  TournamentStage(label: 'Champion', done: false),
];

Future<void> _pump(
  WidgetTester tester, {
  List<TournamentStage> stages = _stages,
  int currentIndex = 1,
  double width = 1280,
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: StageRail(
                stages: stages,
                currentIndex: currentIndex,
                compact: width < 700,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('renders every stage label', (tester) async {
    await _pump(tester);
    for (final s in _stages) {
      expect(find.text(s.label), findsOneWidget);
    }
  });

  testWidgets('marks completed stages with a tick, not colour alone', (
    tester,
  ) async {
    await _pump(tester);
    // "Draw" is done.
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    // The current stage carries its own distinct marker.
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets(
    'an unknown current stage (-1) shows no current marker rather than '
    'inventing one',
    (tester) async {
      await _pump(tester, currentIndex: -1);

      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
      // Stages themselves still render — nothing is hidden.
      expect(find.text('Semis'), findsOneWidget);
    },
  );

  testWidgets('an empty stage list renders nothing at all', (tester) async {
    await _pump(tester, stages: const [], currentIndex: -1);
    expect(find.byType(Row), findsNothing);
  });

  testWidgets('announces progress and completion to screen readers', (
    tester,
  ) async {
    await _pump(tester);

    final semantics = tester.getSemantics(find.byType(StageRail));
    expect(semantics.label, contains('currently Semis'));
    expect(semantics.label, contains('completed: Draw'));
  });

  testWidgets('scrolls horizontally instead of squeezing labels', (
    tester,
  ) async {
    await _pump(tester, width: 360);
    expect(
      find.descendant(
        of: find.byType(StageRail),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
  });

  testWidgets('does not overflow at any supported width', (tester) async {
    for (final w in <double>[1280, 1024, 768, 720, 700, 414, 390, 375, 360]) {
      await _pump(tester, width: w);
      expect(tester.takeException(), isNull, reason: 'overflow at ${w}px');
    }
  });

  testWidgets('survives XL text scale at 360px', (tester) async {
    await _pump(tester, width: 360, textScale: 1.3);
    expect(tester.takeException(), isNull);
    expect(find.text('Champion'), findsOneWidget);
  });
}
