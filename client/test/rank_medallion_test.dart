import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/shared/widgets/rank_medallion.dart';

/// Coverage for the one controlled rank marker used across Results and
/// Tournament — Phase 4's replacement for medal emoji. Confirms every tier
/// (1/2/3/4+) always shows the numeral (never an emoji fallback) and maps to
/// the intended gold/silver-neutral/bronze/violet-neutral tier color.
void main() {
  Future<Color> paintedFill(WidgetTester tester, int rank) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: RankMedallion(rank: rank))),
    );
    final painter = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byType(RankMedallion),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter;
    // ignore: avoid_dynamic_calls
    return (painter as dynamic).fill as Color;
  }

  group('RankMedallion — tier mapping', () {
    testWidgets('rank 1 uses pfGold', (tester) async {
      expect(await paintedFill(tester, 1), HETheme.pfGold);
    });

    testWidgets('rank 2 uses the silver/neutral pfLavenderText tone', (
      tester,
    ) async {
      expect(await paintedFill(tester, 2), HETheme.pfLavenderText);
    });

    testWidgets('rank 3 uses pfBronze', (tester) async {
      expect(await paintedFill(tester, 3), HETheme.pfBronze);
    });

    testWidgets('rank 4+ uses the violet-neutral tone', (tester) async {
      expect(await paintedFill(tester, 4), HETheme.pfSecondaryViolet);
      expect(await paintedFill(tester, 12), HETheme.pfSecondaryViolet);
    });
  });

  group('RankMedallion — always numeral, never emoji', () {
    testWidgets('renders the numeral for every tier', (tester) async {
      for (final rank in [1, 2, 3, 4, 7]) {
        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: RankMedallion(rank: rank))),
        );
        expect(find.text('$rank'), findsOneWidget);
      }
    });

    testWidgets('never renders a medal emoji glyph', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: RankMedallion(rank: 1))),
      );
      expect(find.textContaining('🥇'), findsNothing);
      expect(find.textContaining('🥈'), findsNothing);
      expect(find.textContaining('🥉'), findsNothing);
    });
  });

  testWidgets('exposes a "Rank N" semantics label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: RankMedallion(rank: 3))),
    );

    expect(find.bySemanticsLabel(RegExp(r'Rank 3')), findsOneWidget);

    handle.dispose();
  });
}
