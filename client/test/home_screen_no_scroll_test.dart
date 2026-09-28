import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hidden_eleven/app/router.dart';

Future<void> _settle(WidgetTester tester) async {
  // Not `pumpAndSettle()` — the background's ambient animations are
  // deliberately infinite (see home_screen_purple_redesign_test.dart's
  // `settleHome` for the same reasoning).
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appRouter.go('/');
  });

  testWidgets(
    'Home has no scrollable viewport — the whole page fits without scrolling',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: appRouter)),
      );
      await _settle(tester);

      // A `SingleChildScrollView` would mean the page still relies on
      // scrolling to reach some content — Home is meant to fit as one screen
      // via `FittedBox` scaling instead. (A vertical `Scrollable` check would
      // also catch this, but the display-name `TextField`'s own internal
      // horizontal `EditableText` scrollable is an unrelated false positive,
      // so `SingleChildScrollView` is the precise thing to assert against.)
      expect(find.byType(SingleChildScrollView), findsNothing);
    },
  );

  testWidgets(
    'Host a Room is reachable and tappable without scrolling at a short viewport',
    (tester) async {
      tester.view.physicalSize = const Size(800, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: appRouter)),
      );
      await _settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Host a Room'), findsOneWidget);
      // Tappable implies it's actually laid out on screen (FittedBox scaled
      // the content down to fit rather than pushing it off-screen).
      await tester.tap(find.text('Host a Room'), warnIfMissed: true);
      await tester.pump();
    },
  );

  testWidgets(
    'renders without exception on a genuinely narrow (< breakpointMobile) phone viewport',
    (tester) async {
      // Regression: 410x642 (a real Chrome DevTools mobile preset) is below
      // HETheme.breakpointMobile (700), which used to make FirstTouchLayout
      // cap its width at `double.infinity`. That's harmless under a normal
      // bounded Scaffold, but Home wraps FirstTouchLayout in a FittedBox,
      // which deliberately hands its child UNBOUNDED width to measure
      // natural size — so the infinity reached _HowItWorks's
      // `Row(children: [Expanded(...)])`, and Expanded cannot flex against
      // an infinite width. That threw "BoxConstraints forces an infinite
      // width" and blanked the whole Home screen (no visible buttons) on
      // any phone-width viewport.
      tester.view.physicalSize = const Size(410, 642);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: appRouter)),
      );
      await _settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Host a Room'), findsOneWidget);
      await tester.tap(find.text('Host a Room'), warnIfMissed: true);
      await tester.pump();
    },
  );
}
