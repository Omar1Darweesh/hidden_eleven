import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hidden_eleven/shared/widgets/matchday_background.dart';

void main() {
  Widget harness({required Size size, bool showClassifiedGlow = false}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: Scaffold(
            body: MatchdayBackground(showClassifiedGlow: showClassifiedGlow),
          ),
        ),
      );

  for (final size in const [
    Size(360, 800),
    Size(390, 844),
    Size(412, 915),
    Size(768, 1024),
    Size(1024, 768),
    Size(1920, 1080),
  ]) {
    testWidgets('renders without error at ${size.width}x${size.height}', (
      tester,
    ) async {
      await tester.pumpWidget(harness(size: size));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(MatchdayBackground), findsOneWidget);
    });
  }

  testWidgets('never blocks pointer events (IgnorePointer at the root)', (
    tester,
  ) async {
    await tester.pumpWidget(harness(size: const Size(400, 800)));
    final ignorePointer = tester.widget<IgnorePointer>(
      find.descendant(
        of: find.byType(MatchdayBackground),
        matching: find.byType(IgnorePointer),
      ),
    );
    expect(ignorePointer.ignoring, isTrue);
  });

  testWidgets('showClassifiedGlow defaults to false', (tester) async {
    await tester.pumpWidget(harness(size: const Size(400, 800)));
    const widget = MatchdayBackground();
    expect(widget.showClassifiedGlow, isFalse);
  });
}
