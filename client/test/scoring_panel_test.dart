import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/game/models/chemistry_vars.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/widgets/scoring_panel.dart';

const _preview = ScoringPreview(
  defAvg: 70,
  midAvg: 75,
  atkAvg: 80,
  linesTotal: 225,
  userChallenges: [],
  userChemTotal: 0,
  cardChemTotal: 0,
  estimatedScore: 225,
);

Future<void> _pump(WidgetTester tester, {double width = 400}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: const ScoringPanel(preview: _preview),
        ),
      ),
    ),
  );
}

/// A maximal-width summary bar: 3-digit score with 2 decimals and a 2-digit
/// chemistry total — the widest the numeric content ever gets.
const _wideNumbersPreview = ScoringPreview(
  defAvg: 90,
  midAvg: 92,
  atkAvg: 94,
  linesTotal: 828,
  userChallenges: [],
  userChemTotal: 24,
  cardChemTotal: 18,
  lineLeaderBonus: 6,
  estimatedScore: 876.54,
);

void main() {
  setUp(() {
    ChemistryVars.debugOverrideValues(null);
  });

  group('ScoringSummaryBar — narrow-width overflow (P1 regression)', () {
    // The reported console error was "RenderFlex overflowed by 9.7 pixels on
    // the right" with an available width of 270px. The label is now the only
    // element allowed to shrink; both numeric values must stay fully visible.
    for (final width in <double>[270, 360]) {
      testWidgets('does not overflow at ${width.toInt()}px and keeps both '
          'numeric values readable', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: width,
                child: const ScoringSummaryBar(preview: _wideNumbersPreview),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        // The data itself is never truncated or hidden.
        expect(find.text('Est. 876.54'), findsOneWidget);
        expect(find.text('+48 chem'), findsOneWidget);
      });
    }
  });

  testWidgets(
    'line-leader label shows the resolved bonus for a mocked non-default lineLeaderBonus',
    (tester) async {
      ChemistryVars.debugOverrideValues({'lineLeaderBonus': 9});
      await _pump(tester);

      expect(
        find.text(
          'Line leaders: +9 per line for the best DEF/MID/ATK '
          'card in the game — decided at full time',
        ),
        findsOneWidget,
      );
      // The old hardcoded copy must not be the rendered source anymore.
      expect(
        find.text(
          'Line leaders: +2 per line for the best DEF/MID/ATK '
          'card in the game — decided at full time',
        ),
        findsNothing,
      );
    },
  );

  testWidgets('falls back to the v1 default before any config is loaded', (
    tester,
  ) async {
    await _pump(tester);

    expect(
      find.text(
        'Line leaders: +2 per line for the best DEF/MID/ATK '
        'card in the game — decided at full time',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'a maximal (3-digit) resolved value does not overflow the panel at a narrow width',
    (tester) async {
      ChemistryVars.debugOverrideValues({'lineLeaderBonus': 999});
      await _pump(tester, width: 360);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('+999 per line'), findsOneWidget);
    },
  );

  testWidgets('does not overflow at very narrow widths (small phone screens)', (
    tester,
  ) async {
    for (final width in [300.0, 310.0, 320.0]) {
      await _pump(tester, width: width);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'width=$width');
    }
  });
}
