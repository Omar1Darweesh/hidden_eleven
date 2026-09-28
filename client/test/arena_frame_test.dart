import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hidden_eleven/features/game/widgets/arena_frame.dart';

/// Regression lock for the constant 3px GameScreen overflow.
///
/// `ArenaFrame` is a `Container` with BOTH an explicit `padding` (the bezel)
/// and a `decoration` whose border reports `dimensions`. Flutter ADDS the
/// border's dimensions to the padding, so the frame's real layout cost is
/// `bezel * 2 + borderWidth * 2` — not the `bezel * 2` a caller would
/// naively assume.
///
/// The game screen originally budgeted `bezel * 2`, under-reporting by
/// exactly `borderWidth * 2 = 3.0` and producing "BOTTOM OVERFLOWED BY 3.0
/// PIXELS" at every viewport height. These tests tie the frame's advertised
/// cost ([ArenaFrame.totalInset]) to what it actually consumes, so the two
/// can never drift apart again.
void main() {
  Future<Size> frameSizeFor(
    WidgetTester tester, {
    required double bezel,
    required Size child,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ArenaFrame(
              bezel: bezel,
              child: SizedBox(width: child.width, height: child.height),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return tester.getSize(find.byType(ArenaFrame));
  }

  testWidgets('consumed size equals child + totalInset on both axes', (
    tester,
  ) async {
    const child = Size(300, 400);
    final size = await frameSizeFor(tester, bezel: 14, child: child);
    final inset = ArenaFrame.totalInset(14);

    expect(size.width, child.width + inset);
    expect(size.height, child.height + inset);
  });

  testWidgets('totalInset accounts for the border, not just the bezel', (
    tester,
  ) async {
    // The exact regression: 14px bezel + 1.5px border per side = 31, not 28.
    expect(ArenaFrame.totalInset(14), 31.0);
    expect(ArenaFrame.totalInset(14), isNot(28.0));

    final size = await frameSizeFor(
      tester,
      bezel: 14,
      child: const Size(300, 400),
    );
    expect(
      size.height - 400,
      31.0,
      reason: 'the frame really does consume 31px vertically, not 28',
    );
  });

  testWidgets('totalInset holds across a range of bezels', (tester) async {
    for (final bezel in <double>[0, 4, 14, 24]) {
      final size = await frameSizeFor(
        tester,
        bezel: bezel,
        child: const Size(200, 200),
      );
      expect(
        size.height - 200,
        ArenaFrame.totalInset(bezel),
        reason: 'bezel $bezel: advertised inset must match consumed height',
      );
      expect(size.width - 200, ArenaFrame.totalInset(bezel));
    }
  });
}
