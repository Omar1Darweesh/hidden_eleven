import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hidden_eleven/shared/widgets/screen_entrance.dart';

void main() {
  // Setting disableAnimations via the platform dispatcher's accessibility
  // features (rather than wrapping a MediaQuery ancestor around `home`) is
  // the reliable way to drive this in tests — MaterialApp derives its own
  // MediaQuery from the test view/platform, not from an inherited ancestor
  // placed above or around it, so a plain MediaQuery wrapper is silently
  // ignored for this flag exactly as it is for size (see
  // first_touch_layout_test.dart's equivalent fix). Uses flutter_test's own
  // `FakeAccessibilityFeatures`.
  void setDisableAnimations(WidgetTester tester, bool value) {
    final dispatcher = tester.platformDispatcher;
    dispatcher.accessibilityFeaturesTestValue = FakeAccessibilityFeatures(
      disableAnimations: value,
    );
    addTearDown(dispatcher.clearAccessibilityFeaturesTestValue);
  }

  // The innermost FadeTransition ancestor of the content is ScreenEntrance's
  // own — MaterialApp's route-transition FadeTransition sits further out.
  Finder screenEntranceFade() => find
      .ancestor(of: find.text('content'), matching: find.byType(FadeTransition))
      .first;

  testWidgets('animates in normally when motion is not reduced', (
    tester,
  ) async {
    setDisableAnimations(tester, false);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ScreenEntrance(child: Text('content'))),
      ),
    );
    final opacityAtStart = tester
        .widget<FadeTransition>(screenEntranceFade())
        .opacity
        .value;
    expect(opacityAtStart, lessThan(1.0));

    await tester.pumpAndSettle();
    final opacityAtEnd = tester
        .widget<FadeTransition>(screenEntranceFade())
        .opacity
        .value;
    expect(opacityAtEnd, 1.0);
  });

  testWidgets('jumps straight to the settled state when motion is reduced', (
    tester,
  ) async {
    setDisableAnimations(tester, true);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ScreenEntrance(child: Text('content'))),
      ),
    );
    // No pumpAndSettle needed — should already be fully visible on the very
    // first frame, never animating in the first place.
    final opacity = tester
        .widget<FadeTransition>(screenEntranceFade())
        .opacity
        .value;
    expect(opacity, 1.0);
    expect(find.text('content'), findsOneWidget);
  });
}
