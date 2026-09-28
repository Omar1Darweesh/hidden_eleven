import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hidden_eleven/app/routes.dart';
import 'package:hidden_eleven/app/router.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/game_provider.dart';
import 'package:hidden_eleven/features/lobby/room_provider.dart';
import 'package:hidden_eleven/shared/widgets/he_button.dart';

/// The hard, blocking recovery screen for a fatal session desync — a
/// check_presence/spectator_reconnect that came back NOT_FOUND or
/// INVALID_TOKEN (most commonly because the server restarted and wiped its
/// in-memory session store; see PROJECT_OVERVIEW.md).
///
/// This is deliberately NOT a toast or a snackbar. A rejected reconnect
/// means the room/game this client thought it was part of can never be
/// resumed — continuing to show ANY prior screen risks that screen still
/// rendering stale players/lineups (exactly the bug this fixes: one client
/// silently kept showing an old, orphaned room while the other client
/// carried on in a brand new one). `HiddenElevenApp`'s root `builder` stacks
/// this screen, fully opaque, on top of whatever route is current the
/// instant [sessionDesyncedProvider] is non-null (the underlying GoRouter
/// navigator stays mounted beneath it, untouched, so its state survives),
/// and only this screen's own button can dismiss it — the single explicit
/// recovery path the fix requires.
///
/// By the time this screen is shown, `RoomNotifier._handleReconnectRejection`
/// has already wiped `roomProvider`, `gameProvider`, and the relevant local
/// presence cache — "Return to Home" only needs to acknowledge the desync
/// (clear [sessionDesyncedProvider]) and navigate; there is no other stale
/// state left to clean up.
class SessionDesyncedScreen extends ConsumerWidget {
  const SessionDesyncedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(sessionDesyncedProvider);

    return Scaffold(
      backgroundColor: HETheme.pfBgVoid,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Status badge: reads as "session unavailable / reconnect
                // failed" at a glance — link_off is the clearest match for a
                // dead room/session (vs. wifi_off, which reads more like a
                // pure network-connectivity problem, or warning_amber_rounded,
                // which is too generic for this specific failure). Explicit
                // `alignment: Alignment.center` guarantees the icon is
                // perfectly centered regardless of Icon's own intrinsic
                // sizing — not left to Container's implicit child placement.
                Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: HETheme.pfDanger.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: HETheme.pfDanger.withValues(alpha: 0.45),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    Icons.link_off_rounded,
                    color: HETheme.pfDanger,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Session no longer available',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: HETheme.pfTextPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'The server may have restarted or your room is invalid. '
                  'Return to home and join or create a fresh room.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: HETheme.pfTextSecondary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                if (data != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '(${data.code.toLowerCase().replaceAll('_', ' ')})',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: HETheme.pfTextSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                HEButton(
                  label: 'Return to Home',
                  icon: Icons.home_rounded,
                  onPressed: () => _returnHome(ref),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The single explicit recovery path. Local state is already fully wiped
  /// by the time this runs (see the class doc comment) — this replaces the
  /// GoRouter stack with Home (so the invalid room/game route is never left
  /// reachable via the back button) and then clears the desync flag so this
  /// overlay stops covering every route.
  ///
  /// Uses the top-level `appRouter` directly rather than `context.go(...)` —
  /// this screen is stacked ALONGSIDE the routed subtree (see the class doc
  /// comment), not inside it, so `context` here has no GoRouter ancestor to
  /// resolve.
  void _returnHome(WidgetRef ref) {
    debugPrint(
      '[SessionDesyncedScreen] "Return to Home" tapped — '
      'navigating home and acknowledging desync',
    );
    // Defense in depth — RoomNotifier already reset these when the desync
    // was detected, but a second reset here costs nothing and guarantees
    // this screen never depends on that ordering.
    ref.read(gameProvider.notifier).reset();
    appRouter.goNamed(Routes.home);
    ref.read(sessionDesyncedProvider.notifier).acknowledge();
  }
}
