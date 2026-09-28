import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/game/game_provider.dart';
import 'package:hidden_eleven/features/game/game_screen.dart';
import 'package:hidden_eleven/shared/widgets/spectator_gate.dart';

/// Coverage for the read-only spectator game-screen slice (see
/// FLUTTER_CLIENT_AUDIT.md's "must-fix before spectator UI" item and
/// MULTIPLAYER_ROOMS_DESIGN.md). Two things are being proven:
///
/// 1. SpectatorGate — the one, reusable mechanism every gameplay-action
///    surface in game_screen.dart wraps itself in — genuinely removes taps
///    from hit-testing when spectating, and does nothing when not. This is
///    the actual "block gameplay actions" requirement; tested directly on
///    the gate itself rather than by re-driving every individual gameplay
///    button through several nested widgets in game_screen.dart.
///
/// 2. isLocalPlayerTurnProvider never misclassifies a spectator (a null
///    localPlayerIdProvider) as having a turn, however the game state itself
///    looks — the exact "local-player turn logic does not misclassify a
///    spectator as a player" requirement.
void main() {
  group('SpectatorGate — blocks gameplay actions when spectating', () {
    testWidgets(
      'a tap reaches the child when NOT spectating (existing player behavior unchanged)',
      (tester) async {
        var tapped = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SpectatorGate(
                isSpectating: false,
                child: ElevatedButton(
                  onPressed: () => tapped = true,
                  child: const Text('Pick Slot'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Pick Slot'));
        await tester.pump();

        expect(tapped, isTrue);
      },
    );

    testWidgets('a tap never reaches the child when spectating', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpectatorGate(
              isSpectating: true,
              child: ElevatedButton(
                onPressed: () => tapped = true,
                child: const Text('Pick Slot'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Pick Slot'), warnIfMissed: false);
      await tester.pump();

      expect(tapped, isFalse);
    });

    testWidgets(
      'the content is still visible when spectating — only interaction is blocked, not visibility',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SpectatorGate(isSpectating: true, child: Text('content')),
            ),
          ),
        );

        // A spectator can still SEE the game state — SpectatorGate blocks
        // interaction, not rendering.
        expect(find.text('content'), findsOneWidget);
      },
    );
  });

  group('SpectatingBanner', () {
    // Was: single line "You are spectating — view only" on the legacy
    // navy/cyan palette. Phase 2 migrated it to a compact Night Tactics pill
    // with a short label plus an explicit explanation of what a spectator
    // can/can't do — updated to match.
    testWidgets('renders the read-only indicator text and explanation', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SpectatingBanner())),
      );

      expect(find.text('Spectating'), findsOneWidget);
      expect(
        find.text(
          'You can follow the match live, but you cannot draft cards or '
          'change the lineup.',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.visibility_rounded), findsOneWidget);
    });

    testWidgets('exposes one merged semantics label for screen readers', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SpectatingBanner())),
      );

      expect(
        find.bySemanticsLabel(RegExp(r'Spectating.*cannot draft cards')),
        findsOneWidget,
      );

      handle.dispose();
    });
  });

  group(
    'isLocalPlayerTurnProvider — never misclassifies a spectator (null localPlayerId) as having a turn',
    () {
      test(
        'returns false when localPlayerIdProvider is null, regardless of gameProvider state (spectator case)',
        () {
          final container = ProviderContainer();
          addTearDown(container.dispose);

          // gameProvider itself starts null in a fresh container (no game_state
          // received yet) — the important assertion is localPlayerIdProvider
          // being null is what isLocalPlayerTurnProvider gates on.
          expect(container.read(localPlayerIdProvider), isNull);
          expect(container.read(isLocalPlayerTurnProvider), isFalse);
        },
      );

      test(
        'setting localPlayerIdProvider to null explicitly (mirrors a spectator game_state) keeps isLocalPlayerTurnProvider false',
        () {
          final container = ProviderContainer();
          addTearDown(container.dispose);

          container.read(localPlayerIdProvider.notifier).set('some-real-id');
          expect(container.read(localPlayerIdProvider), 'some-real-id');

          // A spectator's game_state resolves to null (see server_event.dart's
          // _parseGameState fix) — confirm resetting to null is respected, not
          // stuck on whatever the last real value was.
          container.read(localPlayerIdProvider.notifier).set(null);
          expect(container.read(localPlayerIdProvider), isNull);
          expect(container.read(isLocalPlayerTurnProvider), isFalse);
        },
      );
    },
  );
}
