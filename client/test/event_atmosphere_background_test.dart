import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/shared/widgets/event_atmosphere_background.dart';

Future<void> _pump(
  WidgetTester tester, {
  required EventAtmosphereVariant variant,
  bool goldFocus = false,
  bool reduced = false,
  Widget? overlay,
  Size size = const Size(1280, 800),
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size, disableAnimations: reduced),
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: size.width,
            height: size.height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: EventAtmosphereBackground(
                    variant: variant,
                    goldFocus: goldFocus,
                  ),
                ),
                if (overlay != null) Positioned.fill(child: overlay),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  // The suite disables ambient drift globally (see flutter_test_config.dart)
  // so `pumpAndSettle` works everywhere else. This file is the one place that
  // asserts the drift itself, so it turns it back on for its own cases.
  setUp(() => EventAtmosphereBackground.debugAmbientDriftEnabled = true);
  tearDown(() => EventAtmosphereBackground.debugAmbientDriftEnabled = false);

  for (final variant in EventAtmosphereVariant.values) {
    testWidgets('renders the ${variant.name} variant without exception', (
      tester,
    ) async {
      await _pump(tester, variant: variant);
      expect(tester.takeException(), isNull);
      expect(find.byType(EventAtmosphereBackground), findsOneWidget);
    });
  }

  testWidgets(
    'is non-interactive — a tap passes straight through to content behind it',
    (tester) async {
      var tapped = false;
      await _pump(
        tester,
        variant: EventAtmosphereVariant.tournament,
        overlay: Center(
          child: ElevatedButton(
            onPressed: () => tapped = true,
            child: const Text('Behind'),
          ),
        ),
      );

      await tester.tap(find.text('Behind'));
      await tester.pump();
      expect(tapped, isTrue);
    },
  );

  testWidgets('wraps its painting in IgnorePointer and RepaintBoundary', (
    tester,
  ) async {
    await _pump(tester, variant: EventAtmosphereVariant.tournament);

    expect(
      find.descendant(
        of: find.byType(EventAtmosphereBackground),
        matching: find.byType(IgnorePointer),
      ),
      findsOneWidget,
    );
    // Every painted layer is isolated so one repaint can't drag the others.
    expect(
      find.descendant(
        of: find.byType(EventAtmosphereBackground),
        matching: find.byType(RepaintBoundary),
      ),
      findsAtLeastNWidgets(4),
    );
  });

  testWidgets(
    'Stage 4: the atmosphere drifts on exactly one shared ambient clock — '
    'never a ticker per layer',
    (tester) async {
      await _pump(tester, variant: EventAtmosphereVariant.tournament);
      await tester.pump();

      // Drifting, so frames are being scheduled…
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      // …but by a single controller, no matter how many painted layers read
      // it. Two drifting layers on two tickers would report 2.
      expect(tester.binding.transientCallbackCount, 1);
    },
  );

  testWidgets(
    'reduced motion constructs no controller at all and renders the same '
    'layers — atmosphere is lost, information never is',
    (tester) async {
      await _pump(
        tester,
        variant: EventAtmosphereVariant.tournament,
        reduced: true,
      );
      await tester.pump();

      // Not a paused controller — none. A paused one still schedules frames.
      expect(tester.binding.transientCallbackCount, 0);
      // Would time out if anything were repeating.
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final reducedLayers = find
          .descendant(
            of: find.byType(EventAtmosphereBackground),
            matching: find.byType(CustomPaint),
          )
          .evaluate()
          .length;

      await _pump(tester, variant: EventAtmosphereVariant.tournament);
      await tester.pump();
      final animatedLayers = find
          .descendant(
            of: find.byType(EventAtmosphereBackground),
            matching: find.byType(CustomPaint),
          )
          .evaluate()
          .length;

      // Same composition either way; only movement differs.
      expect(reducedLayers, animatedLayers);
    },
  );

  testWidgets('animate: false is honoured even without reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EventAtmosphereBackground(
            variant: EventAtmosphereVariant.results,
            animate: false,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
    'the reserved gold atmosphere paints only when goldFocus is set',
    (tester) async {
      await _pump(
        tester,
        variant: EventAtmosphereVariant.results,
        goldFocus: false,
      );
      final withoutGold = find
          .descendant(
            of: find.byType(EventAtmosphereBackground),
            matching: find.byType(CustomPaint),
          )
          .evaluate()
          .length;

      await _pump(
        tester,
        variant: EventAtmosphereVariant.results,
        goldFocus: true,
      );
      final withGold = find
          .descendant(
            of: find.byType(EventAtmosphereBackground),
            matching: find.byType(CustomPaint),
          )
          .evaluate()
          .length;

      // Exactly one extra painted layer — the gold radial — and never
      // present otherwise.
      expect(withGold, withoutGold + 1);
    },
  );

  testWidgets('renders at every supported width without overflow', (
    tester,
  ) async {
    for (final w in <double>[1280, 1024, 768, 720, 700, 414, 390, 375, 360]) {
      await _pump(
        tester,
        variant: EventAtmosphereVariant.tournament,
        size: Size(w, 800),
      );
      expect(tester.takeException(), isNull, reason: 'failed at ${w}px');
    }
  });

  test('the particle cap stays small enough to read as atmosphere', () {
    expect(EventAtmosphereBackground.kMaxParticles, lessThanOrEqualTo(24));
  });
}
