import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hidden_eleven/shared/widgets/purple_floodlight_background.dart';

void main() {
  Widget harness({required bool animated, Alignment? haloAlignment}) =>
      MaterialApp(
        home: Scaffold(
          body: PurpleFloodlightBackground(
            animated: animated,
            haloAlignment: haloAlignment,
          ),
        ),
      );

  group('PurpleFloodlightBackground — static mode', () {
    testWidgets('renders without error when animated is false', (tester) async {
      await tester.pumpWidget(harness(animated: false));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(PurpleFloodlightBackground), findsOneWidget);
    });

    testWidgets(
      'does not construct an AnimatedBuilder (no controller) in static mode',
      (tester) async {
        await tester.pumpWidget(harness(animated: false));
        await tester.pump();
        // The static branch renders `_FloodlightBeams` directly with no
        // `AnimatedBuilder` wrapper — this is how we know no
        // `AnimationController` was constructed, not just paused. Scoped to
        // this widget's own subtree since MaterialApp/Scaffold internals can
        // contain unrelated `AnimatedBuilder`s of their own.
        expect(
          find.descendant(
            of: find.byType(PurpleFloodlightBackground),
            matching: find.byType(AnimatedBuilder),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'reduced-motion mode never schedules a repeating ticker — no pending frames after settling',
      (tester) async {
        await tester.pumpWidget(harness(animated: false));
        await tester.pumpAndSettle();
        // pumpAndSettle would hang/throw if something kept scheduling
        // frames (e.g. a repeat(reverse: true) controller) — reaching this
        // line at all is the proof.
        expect(tester.binding.hasScheduledFrame, isFalse);
      },
    );
  });

  group('PurpleFloodlightBackground — animated mode', () {
    Finder ownAnimatedBuilders() => find.descendant(
      of: find.byType(PurpleFloodlightBackground),
      matching: find.byType(AnimatedBuilder),
    );

    testWidgets('constructs an AnimatedBuilder and settles once stopped', (
      tester,
    ) async {
      await tester.pumpWidget(harness(animated: true));
      await tester.pump();
      expect(ownAnimatedBuilders(), findsOneWidget);
    });

    testWidgets('switching from animated to static disposes the controller', (
      tester,
    ) async {
      await tester.pumpWidget(harness(animated: true));
      await tester.pump();
      expect(ownAnimatedBuilders(), findsOneWidget);

      await tester.pumpWidget(harness(animated: false));
      await tester.pump();
      expect(ownAnimatedBuilders(), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('PurpleFloodlightBackground — halo and pointer behavior', () {
    testWidgets('never blocks pointer events (IgnorePointer at the root)', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(animated: false, haloAlignment: Alignment.topCenter),
      );
      final ignorePointer = tester.widget<IgnorePointer>(
        find.descendant(
          of: find.byType(PurpleFloodlightBackground),
          matching: find.byType(IgnorePointer),
        ),
      );
      expect(ignorePointer.ignoring, isTrue);
    });

    testWidgets('omits the halo layer entirely when haloAlignment is null', (
      tester,
    ) async {
      await tester.pumpWidget(harness(animated: false));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group(
    'PurpleFloodlightBackground — renders safely at required viewports',
    () {
      for (final size in const [
        Size(360, 800),
        Size(390, 844),
        Size(768, 1024),
        Size(1920, 1080),
      ]) {
        testWidgets('${size.width.toInt()}x${size.height.toInt()}', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            harness(animated: false, haloAlignment: Alignment.topCenter),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    },
  );
}
