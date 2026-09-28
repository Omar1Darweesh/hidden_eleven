import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hidden_eleven/features/game/game_screen.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/widgets/arena_frame.dart';
import 'package:hidden_eleven/features/game/widgets/arena_metrics.dart';
import 'package:hidden_eleven/features/game/widgets/pitch_view.dart';
import 'package:hidden_eleven/features/subs/sub_swap_selection.dart';

/// Regression sweep for "BOTTOM OVERFLOWED BY 3.0 PIXELS".
///
/// The overflow had two independent causes, both covered here:
///
///  1. `ArenaFrame` consumes `bezel*2 + borderWidth*2` (31px) because
///     `Container` adds its border's dimensions to its padding, but the
///     layout budgeted `bezel*2` (28px) — a CONSTANT 3px shortfall at every
///     viewport height.
///  2. A `+ 4` tolerance in the `needsScroll` check let a genuinely-too-tall
///     pitch skip the scroll fallback, stacking up to 4 more px on top.
///
/// A third, quieter bug is covered too: on the narrow path a `SizedBox`
/// taller than its parent's `maxHeight` silently resolves to the parent's
/// height, so the pitch LOST its 0.625 ratio instead of erroring. That never
/// produced a red banner, which is why it went unnoticed — hence the ratio
/// assertions below, not just exception assertions.
void main() {
  const ratio = GameArenaMetrics.kRatio; // 0.625

  List<PitchSlot> elevenSlots() {
    const labels = [
      'GK',
      'LB',
      'CB',
      'CB',
      'RB',
      'CM',
      'CM',
      'CAM',
      'LW',
      'ST',
      'RW',
    ];
    return [
      for (var i = 0; i < labels.length; i++)
        PitchSlot(index: i, label: labels[i], basePositionType: labels[i]),
    ];
  }

  GameState game() => GameState(
    sessionId: 's1',
    roomCode: 'RM1',
    formationName: '4-3-3',
    players: const [
      GamePlayer(id: 'p1', displayName: 'You', isHost: true),
      GamePlayer(id: 'p2', displayName: 'Al Rossi', isHost: false),
    ],
    pitches: const {},
    baseTurnOrder: const ['p1', 'p2'],
    currentRound: 2,
    totalRounds: 11,
    currentTurnOrder: const ['p1', 'p2'],
    currentTurnIndex: 0,
    currentRoundSlotIndex: null,
    turn: const GameTurn(
      turnId: 't1',
      phase: 'selecting_position',
      activePlayerId: 'p1',
    ),
    status: 'drafting',
    isFinished: false,
  );

  // ── The metrics themselves ───────────────────────────────────────────────
  //
  // Asserted against the real GameArenaMetrics the widget builds from, not a
  // re-derivation of the formula in the test.

  group('GameArenaMetrics', () {
    const desktopSizes = <String, Size>{
      '1920x1080': Size(1920, 1080),
      '1440x900': Size(1440, 900),
      '1366x768': Size(1366, 768),
    };

    desktopSizes.forEach((name, size) {
      test('$name — pitch fits without scrolling', () {
        // The body region sits below the match bar; approximate that chrome.
        const matchBar = 62.0;
        final m = GameArenaMetrics.forViewport(
          vw: size.width,
          vh: size.height - matchBar,
        );

        expect(
          m.needsScroll,
          isFalse,
          reason: '$name is tall enough for a full pitch — must not scroll',
        );
        expect(
          m.pitchH,
          lessThanOrEqualTo(m.availPitchH),
          reason: '$name: pitch must fit the space budgeted for it',
        );
        expect(
          m.columnHeight,
          lessThanOrEqualTo(size.height - matchBar),
          reason: '$name: whole left column must fit the viewport',
        );
        expect(
          m.pitchW / m.pitchH,
          closeTo(ratio, 0.02),
          reason: '$name: pitch ratio must hold',
        );
      });
    });

    test('1440x550 — genuinely too short, scrolls rather than shrinking', () {
      final m = GameArenaMetrics.forViewport(vw: 1440, vh: 550 - 62);

      expect(m.needsScroll, isTrue);
      // The whole point of the scroll fallback: never shrink below the
      // legibility floor, because tiny tactical cards are worse than a scroll.
      expect(m.pitchW, greaterThanOrEqualTo(GameArenaMetrics.kMinPitchW));
      expect(m.pitchW / m.pitchH, closeTo(ratio, 0.02));
    });

    test('vertical chrome derives from ArenaFrame, never from bezel*2', () {
      // The exact regression. If someone re-hardcodes `bezel * 2` this fails.
      expect(
        GameArenaMetrics.vChrome,
        16 +
            GameArenaMetrics.kTabOverlap +
            ArenaFrame.totalInset(GameArenaMetrics.kBezel) +
            16 +
            16,
      );
      expect(
        GameArenaMetrics.vChrome,
        isNot(
          16 +
              GameArenaMetrics.kTabOverlap +
              GameArenaMetrics.kBezel * 2 +
              16 +
              16,
        ),
        reason: 'budgeting bezel*2 is the 3px overflow bug',
      );
    });

    test('no scroll tolerance — one pixel too tall must scroll', () {
      // Sweep the band the old `+ 4` slack silently allowed to overflow.
      for (var vh = 480.0; vh <= 600.0; vh += 1) {
        final m = GameArenaMetrics.forViewport(vw: 1440, vh: vh);
        if (!m.needsScroll) {
          expect(
            m.pitchH,
            lessThanOrEqualTo(m.availPitchH),
            reason:
                'vh=$vh: non-scrolling layout must fit exactly — no tolerance',
          );
        }
      }
    });

    test('dimensions are whole pixels at every width', () {
      for (var vw = 1000.0; vw <= 1920.0; vw += 7) {
        final m = GameArenaMetrics.forViewport(vw: vw, vh: 900);
        expect(m.pitchW, m.pitchW.floorToDouble(), reason: 'vw=$vw width');
        expect(m.pitchH, m.pitchH.floorToDouble(), reason: 'vw=$vw height');
      }
    });
  });

  // ── The real widget tree ─────────────────────────────────────────────────

  group('GamePitchStage (narrow path)', () {
    Widget harness(Size box) => ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: box.width,
              height: box.height,
              child: GamePitchStage(
                game: game(),
                orderedIds: const ['p1', 'p2'],
                localPlayerId: 'p1',
                viewedPlayerId: 'p1',
                viewedSlots: elevenSlots(),
                isMyTurn: true,
                tabIndex: 0,
                subSwap: SubSwapView.none,
                swappedSubSlots: const {},
                onSubsPitchSlotTap: (_) {},
                onTabChanged: (_) {},
                onSlotTap: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    // 390x844 minus a match bar, mission ribbon and action drawer leaves the
    // pitch stage roughly this much. Sweep a band around it, including the
    // heights the old `+ 4` tolerance silently distorted the ratio at.
    for (final h in <double>[360, 420, 470, 476, 477, 478, 480, 520, 620]) {
      testWidgets('390-wide stage at height $h — no overflow, ratio holds', (
        tester,
      ) async {
        await tester.pumpWidget(harness(Size(358, h)));
        await tester.pump();

        expect(
          tester.takeException(),
          isNull,
          reason: 'height $h must not overflow',
        );

        final size = tester.getSize(find.byType(PitchView));
        expect(
          size.width / size.height,
          closeTo(ratio, 0.02),
          reason:
              'height $h: pitch must keep its ratio, never squash to fit the '
              'parent height',
        );
        expect(
          size.width,
          greaterThanOrEqualTo(300.0),
          reason: 'height $h: legibility floor',
        );
      });
    }
  });
}
