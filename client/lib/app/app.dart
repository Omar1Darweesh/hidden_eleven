import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hidden_eleven/app/router.dart';
import 'package:hidden_eleven/app/theme.dart';
import 'package:hidden_eleven/features/lobby/room_provider.dart';
import 'package:hidden_eleven/shared/audio/audio_service.dart';
import 'package:hidden_eleven/shared/providers/app_preferences_provider.dart';
import 'package:hidden_eleven/shared/widgets/global_sound_toggle.dart';
import 'package:hidden_eleven/shared/widgets/session_desynced_screen.dart';

class HiddenElevenApp extends ConsumerStatefulWidget {
  const HiddenElevenApp({super.key});

  @override
  ConsumerState<HiddenElevenApp> createState() => _HiddenElevenAppState();
}

class _HiddenElevenAppState extends ConsumerState<HiddenElevenApp> {
  @override
  void initState() {
    super.initState();
    // Started once, here at the app root, and never stopped on navigation —
    // previously this lived on HomeScreen alone (RouteAware start/stop),
    // which meant the track fell silent the moment you left home for a
    // lobby, an active match, or tournament. `playMenuMusic` already no-ops
    // if a track is playing, so this is safe even though `initState` can
    // re-run across hot restarts. The only way to silence it now is the
    // mute toggle (GlobalSoundToggle) — never an implicit route change.
    ref.read(audioServiceProvider).playMenuMusic();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Hidden Eleven',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: appRouter,
      // Global session-integrity guard: stacks the blocking
      // SessionDesyncedScreen, fully opaque, over WHATEVER route is
      // current the instant sessionDesyncedProvider fires — see that
      // provider's doc comment for the exact bug this closes. Deliberately
      // implemented here, at the app root, rather than as a per-screen
      // listener (the pattern every screen used before this fix): the
      // socket drop that leads to a rejected reconnect can happen while
      // the user is on ANY screen, and a per-screen listener can only ever
      // cover the one screen it's written on.
      builder: (context, child) {
        return Consumer(
          builder: (context, ref, _) {
            final desynced = ref.watch(sessionDesyncedProvider) != null;
            final prefs = ref.watch(appPreferencesProvider);
            final media = MediaQuery.of(context);

            // Reduced motion: either source asking for it is enough — the
            // OS-level signal is never overridden, only OR'd with the
            // in-app toggle. Widgets that already read
            // `MediaQuery.disableAnimations` directly (e.g. the hidden-pick
            // reveal intro) pick this up with no changes of their own.
            final effectiveDisableAnimations =
                media.disableAnimations || prefs.reducedMotion;

            // Text scale: the platform's own accessibility scaling is read
            // and kept, never replaced — the in-app Standard/Large/XL
            // choice is a MULTIPLIER on top of it. Reference size 14 is
            // arbitrary but stable (TextScaler.scale is not always linear
            // in principle, though in practice today's implementations
            // are); combining this way means a user who has also raised
            // their OS text size keeps that increase layered under
            // whichever in-app option they pick. Clamped so the combined
            // result can never shrink below a readable floor even if a
            // future platform scaler reports less than 1.0.
            const referenceSize = 14.0;
            final systemMultiplier =
                media.textScaler.scale(referenceSize) / referenceSize;
            final combinedMultiplier =
                (systemMultiplier * prefs.textScale.multiplier).clamp(
                  0.85,
                  2.2,
                );

            return MediaQuery(
              data: media.copyWith(
                disableAnimations: effectiveDisableAnimations,
                textScaler: TextScaler.linear(combinedMultiplier),
              ),
              child: Stack(
                children: [
                  ?child,
                  // Reachable from every screen — home, lobby, an active
                  // match, tournament, results — without each one wiring
                  // its own copy. Painted below the desync guard so it's
                  // hidden (not just inert) once that full-screen overlay
                  // takes over.
                  if (!desynced) const GlobalSoundToggle(),
                  if (desynced) const SessionDesyncedScreen(),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
