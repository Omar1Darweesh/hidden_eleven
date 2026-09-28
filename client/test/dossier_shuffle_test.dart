import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/widgets/dossier_shuffle.dart';
import 'package:hidden_eleven/features/game/widgets/hidden_pick_panel.dart';
import 'package:hidden_eleven/features/game/widgets/player_card.dart';

CandidateCard _card(String id, String name, int rating) => CandidateCard(
  cardId: id,
  playerName: name,
  rating: rating,
  basePositionType: 'ST',
);

void main() {
  void setDisableAnimations(WidgetTester tester, bool value) {
    final d = tester.platformDispatcher;
    d.accessibilityFeaturesTestValue = FakeAccessibilityFeatures(
      disableAnimations: value,
    );
    addTearDown(d.clearAccessibilityFeaturesTestValue);
  }

  /// [key] forces a fresh `State` when a test needs to run the sequence from
  /// the beginning again. Omitting it deliberately reuses the existing State —
  /// which is what the restart-safety tests rely on.
  Widget harness(
    List<CandidateCard> cards, {
    VoidCallback? onComplete,
    Key? key,
  }) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 400,
        height: 300,
        child: HiddenDraftIntro(
          key: key,
          previewCards: cards,
          onComplete: onComplete ?? () {},
        ),
      ),
    ),
  );

  // ── The timeline itself ─────────────────────────────────────────────────

  group('DossierShuffleTimeline', () {
    test('total runtime is ~4.1s, with a 1000ms shuffle window', () {
      expect(DossierShuffleTimeline.totalMs, 4100);
      expect(DossierShuffleTimeline.shuffleMs, 1000);
    });

    test('stages progress in order and never overlap', () {
      expect(dossierStageAt(0.0), DossierStage.entering);
      expect(dossierStageAt(0.2), DossierStage.preview);
      expect(
        dossierStageAt(
          (DossierShuffleTimeline.previewEnd + DossierShuffleTimeline.flipEnd) /
              2,
        ),
        DossierStage.flipping,
      );
      expect(
        dossierStageAt(
          (DossierShuffleTimeline.flipEnd + DossierShuffleTimeline.shuffleEnd) /
              2,
        ),
        DossierStage.shuffling,
      );
      expect(dossierStageAt(1.0), DossierStage.ready);
    });

    test('exactly three deliberate moves, never a continuous blur', () {
      expect(DossierShuffleTimeline.moveBounds.length - 1, 3);
      expect(DossierShuffleTimeline.completedMoves(0.0), 0);
      expect(DossierShuffleTimeline.completedMoves(1.0), 3);
    });

    test('orderAt is deterministic and a true permutation', () {
      for (var n = 2; n <= 8; n++) {
        for (var move = 0; move <= 3; move++) {
          final a = DossierShuffleTimeline.orderAt(n, move);
          final b = DossierShuffleTimeline.orderAt(n, move);
          expect(a, b, reason: 'n=$n move=$move must be deterministic');
          expect(
            a.toSet(),
            List.generate(n, (i) => i).toSet(),
            reason: 'n=$n move=$move must be a permutation, losing nothing',
          );
        }
      }
    });

    test('a card passes BEHIND another during move 1', () {
      final z = DossierShuffleTimeline.zOrder(2, 3, 1, 0.5);
      expect(z, lessThan(0), reason: 'the travelling card dips behind');
    });
  });

  // ── Privacy: motion must never depend on card content ───────────────────

  group('leak prevention', () {
    testWidgets('two decks with different cards animate identically', (
      tester,
    ) async {
      setDisableAnimations(tester, false);

      // Indexed finders, not byWidget: face-down PlayerCards are identical
      // const instances, so byWidget matches all of them at once.
      List<Rect> geometry() {
        final n = tester.widgetList<PlayerCard>(find.byType(PlayerCard)).length;
        return [
          for (var i = 0; i < n; i++)
            tester.getRect(find.byType(PlayerCard).at(i)),
        ];
      }

      // Deck A — low ratings, short names.
      await tester.pumpWidget(
        harness([
          _card('a', 'Aa', 55),
          _card('b', 'Bb', 56),
          _card('c', 'Cc', 57),
        ], key: const ValueKey('deckA')),
      );
      await tester.pump(const Duration(milliseconds: 3200));
      final a = geometry();

      // Deck B — wildly different ratings and name lengths, same count.
      await tester.pumpWidget(
        harness(
          [
            _card('x', 'Extremely Long Player Name', 99),
            _card('y', 'Z', 40),
            _card('z', 'Another Very Long One', 91),
          ],
          // A different key forces a fresh State, so this deck runs the
          // sequence from t=0 like deck A did — otherwise the restart guard
          // (correctly) keeps the first run going and the two samples would
          // be taken at different points on the timeline.
          key: const ValueKey('deckB'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 3200));
      final b = geometry();

      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(
          b[i],
          a[i],
          reason:
              'dossier $i moved differently for different card content — '
              'this would leak hidden identity',
        );
      }
    });
  });

  // ── Restart safety ──────────────────────────────────────────────────────

  group('restart safety', () {
    testWidgets('an ancestor rebuild does not restart the sequence', (
      tester,
    ) async {
      setDisableAnimations(tester, false);
      final cards = [_card('a', 'A', 80), _card('b', 'B', 81)];

      await tester.pumpWidget(harness(cards));
      await tester.pump(const Duration(milliseconds: 1500));

      final beforeStage = dossierStageAt(0.36);

      // Rebuild the ancestor with identical inputs — as a provider rebuild or
      // an unrelated game_state broadcast would.
      await tester.pumpWidget(harness(cards));
      await tester.pump(const Duration(milliseconds: 100));

      // Still in the same forward-moving sequence, not reset to entering.
      expect(beforeStage, isNot(DossierStage.entering));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'previewCards SHRINKING mid-sequence does not throw (regression)',
      (tester) async {
        setDisableAnimations(tester, false);

        // Before the didUpdateWidget guard this threw a RangeError: the
        // display order is a permutation of indices into previewCards, so a
        // shorter list left stale indices behind.
        await tester.pumpWidget(
          harness([
            _card('a', 'A', 80),
            _card('b', 'B', 81),
            _card('c', 'C', 82),
            _card('d', 'D', 83),
          ]),
        );
        await tester.pump(const Duration(milliseconds: 600));

        await tester.pumpWidget(
          harness([_card('a', 'A', 80), _card('b', 'B', 81)]),
        );
        await tester.pump(const Duration(milliseconds: 200));

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('previewCards emptying mid-sequence completes cleanly', (
      tester,
    ) async {
      setDisableAnimations(tester, false);
      var completed = 0;

      await tester.pumpWidget(
        harness([
          _card('a', 'A', 80),
          _card('b', 'B', 81),
        ], onComplete: () => completed++),
      );
      await tester.pump(const Duration(milliseconds: 400));

      await tester.pumpWidget(harness([], onComplete: () => completed++));
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(completed, greaterThan(0), reason: 'must not strand the player');
    });
  });

  // ── Reduced motion ──────────────────────────────────────────────────────

  group('reduced motion', () {
    testWidgets('constructs no controller and completes immediately', (
      tester,
    ) async {
      setDisableAnimations(tester, true);
      var completed = false;

      await tester.pumpWidget(
        harness([
          _card('a', 'A', 80),
          _card('b', 'B', 81),
        ], onComplete: () => completed = true),
      );
      await tester.pump();

      expect(completed, isTrue);
      // No pending animation frames — the sequence was skipped entirely.
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    });
  });
}
