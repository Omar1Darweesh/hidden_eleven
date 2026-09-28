import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hidden_eleven/shared/widgets/hero_entrance.dart';

void main() {
  void setDisableAnimations(WidgetTester tester, bool value) {
    final dispatcher = tester.platformDispatcher;
    dispatcher.accessibilityFeaturesTestValue = FakeAccessibilityFeatures(
      disableAnimations: value,
    );
    addTearDown(dispatcher.clearAccessibilityFeaturesTestValue);
  }

  Finder scaleTransition() => find
      .ancestor(of: find.text('hero'), matching: find.byType(ScaleTransition))
      .first;

  testWidgets(
    'scales in from 92% and settles at 100% when motion is not reduced',
    (tester) async {
      setDisableAnimations(tester, false);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: HeroEntrance(child: Text('hero'))),
        ),
      );
      final scaleAtStart = tester
          .widget<ScaleTransition>(scaleTransition())
          .scale
          .value;
      expect(scaleAtStart, lessThan(1.0));

      await tester.pumpAndSettle();
      final scaleAtEnd = tester
          .widget<ScaleTransition>(scaleTransition())
          .scale
          .value;
      expect(scaleAtEnd, 1.0);
    },
  );

  testWidgets('jumps straight to fully settled under reduced motion', (
    tester,
  ) async {
    setDisableAnimations(tester, true);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: HeroEntrance(child: Text('hero'))),
      ),
    );
    await tester.pump();
    expect(tester.widget<ScaleTransition>(scaleTransition()).scale.value, 1.0);
    expect(find.text('hero'), findsOneWidget);
  });
}
