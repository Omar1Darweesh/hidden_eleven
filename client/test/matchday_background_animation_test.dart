import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hidden_eleven/shared/widgets/matchday_background.dart';

void main() {
  void setDisableAnimations(WidgetTester tester, bool value) {
    final dispatcher = tester.platformDispatcher;
    dispatcher.accessibilityFeaturesTestValue = FakeAccessibilityFeatures(
      disableAnimations: value,
    );
    addTearDown(dispatcher.clearAccessibilityFeaturesTestValue);
  }

  Finder ownAnimatedBuilders() => find.descendant(
    of: find.byType(MatchdayBackground),
    matching: find.byType(AnimatedBuilder),
  );

  testWidgets(
    'constructs ambient AnimatedBuilders (breathe + drift) when motion is not reduced',
    (tester) async {
      setDisableAnimations(tester, false);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MatchdayBackground())),
      );
      await tester.pump();
      // One each for the floodlight breathe, the floating-shapes drift, and
      // the pitch-line glow sweep.
      expect(ownAnimatedBuilders(), findsNWidgets(3));
    },
  );

  testWidgets('never constructs an AnimatedBuilder under reduced motion', (
    tester,
  ) async {
    setDisableAnimations(tester, true);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MatchdayBackground())),
    );
    await tester.pump();
    expect(ownAnimatedBuilders(), findsNothing);
  });

  testWidgets('reduced motion never schedules a pending frame after settling', (
    tester,
  ) async {
    setDisableAnimations(tester, true);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MatchdayBackground())),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets(
    'halo layer is present when haloAlignment is set, absent when null',
    (tester) async {
      setDisableAnimations(tester, true);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: MatchdayBackground(haloAlignment: null)),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('never blocks pointer events', (tester) async {
    setDisableAnimations(tester, true);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MatchdayBackground())),
    );
    final ignorePointer = tester.widget<IgnorePointer>(
      find.descendant(
        of: find.byType(MatchdayBackground),
        matching: find.byType(IgnorePointer),
      ),
    );
    expect(ignorePointer.ignoring, isTrue);
  });
}
