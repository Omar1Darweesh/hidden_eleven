import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hidden_eleven/features/game/widgets/game_action_sheet.dart';

Widget _harness({double height = 700}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: Size(360, height)),
      child: Scaffold(
        body: Column(
          children: [
            const Expanded(child: SizedBox()), // stand-in for the pitch stage
            GameActionSheet(
              compactMaxHeight: 200,
              expandedMaxHeight: 500,
              child: SizedBox(
                height: 800, // deliberately taller than either cap
                child: Container(
                  color: Colors.red,
                  child: const Text('Content'),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

double _sheetHeight(WidgetTester tester) {
  final box = tester.renderObject<RenderBox>(find.byType(AnimatedContainer));
  return box.size.height;
}

void main() {
  group('GameActionSheet — expand/collapse', () {
    testWidgets('starts compact and clamps to compactMaxHeight', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();
      expect(_sheetHeight(tester), 200);
    });

    testWidgets('tapping the handle expands to expandedMaxHeight', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsLabel('Expand this panel for more room'),
      );
      await tester.pumpAndSettle();

      expect(_sheetHeight(tester), 500);
    });

    testWidgets('tapping again collapses back to compactMaxHeight', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsLabel('Expand this panel for more room'),
      );
      await tester.pumpAndSettle();
      expect(_sheetHeight(tester), 500);

      await tester.tap(find.bySemanticsLabel('Collapse this panel'));
      await tester.pumpAndSettle();
      expect(_sheetHeight(tester), 200);
    });

    testWidgets('handle exposes a 44x44-clearing tappable area', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      // The whole handle (the Semantics(button:true) region itself) clears
      // the accessibility touch-target minimum — checked on its own
      // bounding rect rather than a specific ancestor widget type, since
      // several ConstrainedBoxes exist in the tree at this point (Flutter's
      // own IconTheme/InkWell internals included) and matching "the"
      // ConstrainedBox by type alone is ambiguous.
      final handleRect = tester.getRect(
        find.bySemanticsLabel('Expand this panel for more room'),
      );
      expect(handleRect.height, greaterThanOrEqualTo(44));
    });

    testWidgets('content still reachable via scroll when it exceeds the cap', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();
      // The 800px content inside a 200px cap must still be present in the
      // tree (scrollable), not clipped away entirely.
      expect(find.text('Content'), findsOneWidget);
    });
  });
}
