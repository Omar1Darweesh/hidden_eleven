import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hidden_eleven/app/router.dart';

/// Advances past every one-shot entrance animation (≤700ms) without ever
/// calling `pumpAndSettle()` — `PurpleFloodlightBackground`'s ambient
/// floodlight breathe is a deliberate, infinite `repeat(reverse: true)`
/// animation, so `pumpAndSettle()` on the real Home screen never actually
/// settles and times out. This is expected production behavior, not a bug;
/// tests just need to advance a bounded amount instead.
Future<void> settleHome(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // `appRouter` is the app's real, module-level GoRouter singleton — its
    // current location survives across tests in the same run (a previous
    // test navigating to /host-room leaves it there), so every test must
    // force it back to Home before pumping, or it silently renders
    // whatever screen the last test left it on instead of Home.
    appRouter.go('/');
  });

  Widget harness() =>
      ProviderScope(child: MaterialApp.router(routerConfig: appRouter));

  /// Home's full column (logo, tagline, chips, name field, all three
  /// buttons, How it works) exceeds the default 800x600 test surface —
  /// widen it so every control used below is actually on-screen and
  /// hit-testable without needing to scroll to it first.
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('Home — renders and stays interactive during the entrance animation', () {
    testWidgets(
      'name field and Host button are present and usable on the very first frame',
      (tester) async {
        useTallSurface(tester);
        await tester.pumpWidget(harness());
        // Deliberately a single `pump()`, not settled — the whole point is
        // proving interaction works WHILE the entrance animation is still
        // running, not after it finishes.
        await tester.pump();

        expect(find.text('Host a Room'), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'Alice');
        await tester.pump();
        expect(find.text('Alice'), findsOneWidget);

        // Drain the action-zone's delayed ScreenEntrance timer (120ms) so the
        // test doesn't end with a pending Timer still outstanding.
        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets('tapping Host a Room mid-animation navigates normally', (
      tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(harness());
      await tester.pump(); // still mid-entrance, deliberately not settled

      await tester.enterText(find.byType(TextField), 'Alice');
      await tester.pump();
      await tester.tap(find.text('Host a Room'));
      await settleHome(tester);

      expect(find.text('Set Up Your Room'), findsOneWidget);

      // Drain HostRoomScreen's own entrance timers/animations too, so no
      // pending Timer leaks into the next test.
      await tester.pump(const Duration(milliseconds: 700));
    });
  });

  group('Home — validation behavior unchanged', () {
    testWidgets(
      'shows an inline error and does not navigate with an empty name',
      (tester) async {
        useTallSurface(tester);
        await tester.pumpWidget(harness());
        await settleHome(tester);

        await tester.tap(find.text('Host a Room'));
        await tester.pump();

        expect(find.text('Enter a display name to continue'), findsOneWidget);
        expect(find.text('Set Up Your Room'), findsNothing);
      },
    );

    testWidgets('Join a Room navigates to the join screen with a valid name', (
      tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(harness());
      await settleHome(tester);

      await tester.enterText(find.byType(TextField), 'Bob');
      await tester.pump();
      await tester.tap(find.text('Join a Room'));
      await settleHome(tester);

      expect(find.text('Enter the Room Code'), findsOneWidget);

      // Drain JoinRoomScreen's own entrance timers/animations too, so no
      // pending Timer leaks into the next test.
      await tester.pump(const Duration(milliseconds: 700));
    });
  });

  group('Home — text scale', () {
    for (final scale in [1.0, 1.15, 1.3]) {
      testWidgets('renders without overflow at ${scale}x text scale', (
        tester,
      ) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp.router(
              routerConfig: appRouter,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
            ),
          ),
        );
        await settleHome(tester);

        expect(tester.takeException(), isNull);
        expect(find.text('Host a Room'), findsOneWidget);
      });
    }
  });

  group('Home — reduced motion', () {
    testWidgets('renders correctly with reduced motion enabled', (
      tester,
    ) async {
      final dispatcher = tester.platformDispatcher;
      dispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(dispatcher.clearAccessibilityFeaturesTestValue);

      useTallSurface(tester);
      await tester.pumpWidget(harness());
      // No settling needed — under reduced motion the hero should already
      // be at its settled state on the first frame, and the background's
      // ambient animation never even constructs a controller.
      await tester.pump();

      expect(find.text('Host a Room'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
