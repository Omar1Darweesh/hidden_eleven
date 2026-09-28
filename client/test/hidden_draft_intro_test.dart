import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/widgets/hidden_pick_panel.dart';
import 'package:hidden_eleven/features/lobby/models/server_event.dart';

/// Coverage for the "magician" hidden-draft intro (reveal → conceal →
/// shuffle) added on top of the existing hidden-pick flow. Three concerns:
///
/// 1. `HiddenPickPromptReceived`'s new `previewCards` field parses
///    correctly and is empty/absent-safe (an older-shaped payload, or a
///    non-active viewer who never receives the field at all, must not crash).
/// 2. `HiddenDraftIntro` runs its full timed sequence and always calls
///    `onComplete` exactly once — including the reduced-motion and
///    zero-cards edge cases, where it must skip straight through rather
///    than block the player.
/// 3. `HiddenPickPanel` shows the intro first (not the real slot grid) when
///    preview cards are present for the active picker, and swaps to the
///    real grid once the intro finishes — proving the two are sequenced,
///    not simultaneous.
CandidateCard _card(String id) => CandidateCard(
  cardId: id,
  playerName: 'Player $id',
  basePositionType: 'CM',
  rating: 80,
);

void main() {
  group('HiddenPickPromptReceived parsing — previewCards', () {
    test('parses previewCards from a full payload', () {
      final event = parseServerEvent({
        'event': 'hidden_pick_prompt',
        'data': {
          'turnId': 't1',
          'totalSlots': 3,
          'availableSlots': [0, 1, 2],
          'previewCards': [
            {
              'cardId': 'c1',
              'playerName': 'Alice',
              'basePositionType': 'CB',
              'rating': 82,
            },
            {
              'cardId': 'c2',
              'playerName': 'Bob',
              'basePositionType': 'ST',
              'rating': 77,
            },
          ],
        },
      }, null);

      expect(event, isA<HiddenPickPromptReceived>());
      final prompt = event as HiddenPickPromptReceived;
      expect(prompt.previewCards, hasLength(2));
      expect(prompt.previewCards[0].cardId, 'c1');
      expect(prompt.previewCards[1].playerName, 'Bob');
    });

    test(
      'defaults to an empty list when previewCards is absent (older/non-picker payload)',
      () {
        final event = parseServerEvent({
          'event': 'hidden_pick_prompt',
          'data': {
            'turnId': 't1',
            'totalSlots': 3,
            'availableSlots': [0, 1, 2],
          },
        }, null);

        expect(event, isA<HiddenPickPromptReceived>());
        expect((event as HiddenPickPromptReceived).previewCards, isEmpty);
      },
    );
  });

  group('HiddenDraftIntro — timed sequence', () {
    testWidgets(
      'runs the full reveal/flip/shuffle sequence and calls onComplete exactly once',
      (tester) async {
        var completedCount = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                height: 200,
                child: HiddenDraftIntro(
                  previewCards: [_card('c1'), _card('c2'), _card('c3')],
                  onComplete: () => completedCount++,
                ),
              ),
            ),
          ),
        );

        // Preview stage: nothing has completed yet.
        await tester.pump(const Duration(milliseconds: 200));
        expect(completedCount, 0);

        // Advance past the whole timeline in one lump, with slack.
        //
        // The sequence is now a single AnimationController rather than a pile
        // of Timers, so its total is exactly
        // `DossierShuffleTimeline.totalMs` (4100ms): 300 enter + 2200 preview
        // + 380 flip + 1000 shuffle + 220 settle. `dossier_shuffle_test.dart`
        // asserts those constants directly; this test only cares that
        // onComplete fires exactly once by the end.
        await tester.pump(const Duration(milliseconds: 6500));

        expect(completedCount, 1);

        // Nothing left pending — pumpAndSettle must not hang or double-fire.
        await tester.pumpAndSettle();
        expect(completedCount, 1);
      },
    );

    testWidgets('skips straight through with reduced motion enabled', (
      tester,
    ) async {
      var completed = false;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                height: 200,
                child: HiddenDraftIntro(
                  previewCards: [_card('c1'), _card('c2')],
                  onComplete: () => completed = true,
                ),
              ),
            ),
          ),
        ),
      );

      // One post-frame callback is all reduced motion needs — must not
      // require waiting through the ~2s normal sequence.
      await tester.pump();
      await tester.pump();

      expect(completed, isTrue);
    });

    testWidgets(
      'completes immediately with zero preview cards rather than hanging',
      (tester) async {
        var completed = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                height: 200,
                child: HiddenDraftIntro(
                  previewCards: const [],
                  onComplete: () => completed = true,
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump();

        expect(completed, isTrue);
      },
    );

    testWidgets(
      'interruption safety: disposing mid-sequence never throws or double-calls onComplete',
      (tester) async {
        var completedCount = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                height: 200,
                child: HiddenDraftIntro(
                  previewCards: [_card('c1'), _card('c2')],
                  onComplete: () => completedCount++,
                ),
              ),
            ),
          ),
        );

        // Mid-flip — tear the whole subtree down, simulating the server
        // moving the turn on (HiddenPickPanel's Key changes) before the
        // intro's own timers finish.
        await tester.pump(const Duration(milliseconds: 950));
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: Text('replaced'))),
        );

        // Let any stray timers that would have fired do so — must not throw
        // "setState after dispose" or otherwise misbehave.
        await tester.pump(const Duration(seconds: 3));

        expect(completedCount, 0); // never got the chance to call — that's fine
        expect(find.text('replaced'), findsOneWidget);
      },
    );
  });

  group('HiddenPickPanel — intro gates the real slot grid', () {
    testWidgets(
      'shows the intro (not tappable slots) first, then the real grid once it completes',
      (tester) async {
        var picked = -1;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HiddenPickPanel(
                key: const ValueKey('t1'),
                isActivePicker: true,
                totalSlots: 2,
                availableSlots: const [0, 1],
                previewCards: [_card('c1'), _card('c2')],
                onPick: (i) => picked = i,
              ),
            ),
          ),
        );

        // Still mid-intro: no "Slot 1"/"TAP TO CHOOSE" grid content yet.
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('TAP TO CHOOSE'), findsNothing);

        // Run the intro to completion (real total 4100ms — see
        // HiddenDraftIntro's timed-sequence test above) plus the panel's own
        // 260ms crossfade, with slack. `pumpAndSettle` is NOT a substitute
        // here: between this widget's discrete Timer-driven setState calls
        // there is no animation frame scheduled, so pumpAndSettle considers
        // the tree already "settled" and returns immediately without ever
        // reaching the end of the 4100ms timeline — a single big
        // `pump` is what actually advances the fake clock through it.
        await tester.pump(const Duration(milliseconds: 7000));

        // Real grid now visible and tappable.
        expect(find.text('TAP TO CHOOSE'), findsWidgets);
        await tester.tap(find.text('TAP TO CHOOSE').first);
        expect(picked, anyOf(0, 1));
      },
    );

    testWidgets('skips the intro entirely when there are no preview cards', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HiddenPickPanel(
                key: const ValueKey('t2'),
                isActivePicker: true,
                totalSlots: 1,
                availableSlots: const [0],
                previewCards: const [],
                onPick: (_) {},
              ),
            ),
          ),
        ),
      );

      // No intro to wait through — the real grid is already there.
      await tester.pump();
      expect(find.text('TAP TO CHOOSE'), findsOneWidget);
    });

    testWidgets('never shows the intro for a non-active viewer', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HiddenPickPanel(
                isActivePicker: false,
                totalSlots: 1,
                availableSlots: const [0],
                // A non-active viewer's HiddenPickData never carries
                // previewCards in the first place (see game_provider.dart /
                // rooms.gateway.ts — the field is only ever sent privately to
                // the active picker) — passing it here anyway must still not
                // trigger the intro for a non-active viewer.
                previewCards: [_card('c1')],
                waitingForName: 'Alice',
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.textContaining("Here's what's left"), findsNothing);
      expect(find.textContaining('Waiting for Alice'), findsOneWidget);
    });
  });
}
