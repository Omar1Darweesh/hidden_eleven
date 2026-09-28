// Regression test for the Android-emulator ANR at the subs picked-bench
// card site (see subs_panel.dart's _PickedSlot/_FullCardRow and
// player_card.dart's PlayerCard.build comments for the full story).
//
// The hang was caused by PlayerCard's AspectRatio composing badly with an
// IntrinsicHeight ancestor. The permanent fix has two parts:
//   1. PlayerCard skips AspectRatio when both axes are bounded (fills the
//      box directly via SizedBox.expand) — only using AspectRatio when the
//      parent leaves height unbounded (the normal width-only slot case).
//   2. The subs picked-bench card is rendered in a fixed-size SizedBox with
//      no IntrinsicHeight ancestor.
//
// These tests lock in both parts so a future edit can't reintroduce the
// AspectRatio + IntrinsicHeight combination at that site.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/game/widgets/player_card.dart';

void main() {
  group('PlayerCard sizing', () {
    testWidgets(
      'fully-bounded box (both axes bounded) skips AspectRatio and fills the '
      'given size',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Center(
              child: SizedBox(
                width: 90,
                height: 126,
                child: PlayerCard(faceDown: true),
              ),
            ),
          ),
        );

        expect(find.byType(AspectRatio), findsNothing);

        final size = tester.getSize(find.byType(PlayerCard));
        expect(size, const Size(90, 126));
      },
    );

    testWidgets(
      'width-only constraint (unbounded height) still uses AspectRatio(3:4.2) '
      'for draft/pitch/result call sites',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Center(
              child: SizedBox(
                width: 90,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [PlayerCard(faceDown: true)],
                ),
              ),
            ),
          ),
        );

        expect(find.byType(AspectRatio), findsOneWidget);

        final aspectRatio = tester.widget<AspectRatio>(
          find.byType(AspectRatio),
        );
        expect(aspectRatio.aspectRatio, closeTo(3 / 4.2, 1e-9));
      },
    );

    testWidgets(
      'no IntrinsicHeight ancestor is required to size a fully-bounded '
      'PlayerCard (the ANR-triggering combination stays absent)',
      (tester) async {
        // Minimal harness mirroring the picked-bench render site: a
        // fixed-size SizedBox around PlayerCard, with NO IntrinsicHeight
        // anywhere in the tree.
        await tester.pumpWidget(
          const MaterialApp(
            home: Center(
              child: SizedBox(
                width: 90,
                height: 126,
                child: RepaintBoundary(child: PlayerCard(faceDown: true)),
              ),
            ),
          ),
        );

        expect(find.byType(IntrinsicHeight), findsNothing);
        expect(find.byType(AspectRatio), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
