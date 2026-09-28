import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/subs/club_roulette_drum.dart';

/// Regression coverage for the ClubRouletteDrum crash fix: this widget used
/// to render via `ListWheelScrollView`, whose `RenderListWheelViewport`
/// applies a genuine 3D cylindrical-projection `Matrix4` transform every
/// frame (perspective is asserted `> 0`, so it can never be flattened to a
/// 2D transform by tuning parameters). That 3D-transform codepath is exactly
/// the class of operation known to crash natively (SIGQUIT/tombstone) on
/// Impeller's OpenGLES backend on some Android emulator GPU configs — and
/// the AndroidManifest `EnableImpeller=false` workaround that used to paper
/// over this is confirmed inert on the currently pinned engine build (its
/// Skia Android GL surface path is compiled out behind a `SLIMPELLER`
/// flag). The fix replaces the widget's rendering with a flat, Timer-driven
/// text cycle — no `ListWheelScrollView`, no `FixedExtentScrollController`,
/// no 3D transform at all. These tests pin: (a) it no longer uses that
/// widget/controller at all, (b) it still lands on the server-provided
/// result and calls onComplete, (c) it cleans up its own timer on unmount
/// (flutter_test fails a test if a Timer is still pending after it ends).
void main() {
  testWidgets(
    'ClubRouletteDrum lands on the server-provided resultClub and calls onComplete, without ever using a ListWheelScrollView (the crash-prone 3D-transform widget)',
    (tester) async {
      var completed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClubRouletteDrum(
              clubPool: const ['Arsenal', 'Chelsea', 'Liverpool FC'],
              resultClub: 'Liverpool FC',
              onComplete: () => completed = true,
            ),
          ),
        ),
      );

      // Never renders the 3D-transform widget that caused the native crash.
      expect(find.byType(ListWheelScrollView), findsNothing);

      // Drive the cycling-then-landing sequence to completion (cycle phase
      // is well under 1.5s per _scheduleCycle's stop condition, plus the
      // 900ms landed-freeze before onComplete fires).
      await tester.pump(const Duration(seconds: 3));

      expect(find.text('Liverpool FC'), findsWidgets);
      expect(completed, isTrue);
    },
  );

  testWidgets(
    'ClubRouletteDrum falls back to its built-in club pool when clubPool is empty, and still lands correctly',
    (tester) async {
      var completed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClubRouletteDrum(
              clubPool: const [],
              resultClub: 'Napoli',
              onComplete: () => completed = true,
            ),
          ),
        ),
      );

      await tester.pump(const Duration(seconds: 3));

      expect(find.text('Napoli'), findsWidgets);
      expect(completed, isTrue);
    },
  );

  testWidgets(
    'ClubRouletteDrum cancels its cycling timer cleanly if unmounted mid-animation (no pending-timer leak)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClubRouletteDrum(
              clubPool: const ['Arsenal', 'Chelsea'],
              resultClub: 'Chelsea',
              onComplete: () {},
            ),
          ),
        ),
      );

      // Unmount partway through the cycling phase.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      // If dispose() failed to cancel the pending Timer, flutter_test would
      // throw "A Timer is still pending" when the test body ends — reaching
      // this line at all is the assertion.
      await tester.pump(const Duration(seconds: 3));
    },
  );
}
