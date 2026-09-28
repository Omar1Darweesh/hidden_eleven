import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/shared/audio/audio_service.dart';

/// App-wide mute toggle, painted once at the app root (see [HiddenElevenApp])
/// so it's reachable from every screen — home, lobby, an active match,
/// tournament, results — without each screen wiring its own copy.
///
/// Bottom-right rather than a top corner: most screens already put their own
/// controls (settings, help, leave) in one of the top corners, and this
/// avoids fighting any of them for the same spot.
///
/// No `tooltip` on the [IconButton] here — this widget is painted as a
/// sibling of the routed content in [HiddenElevenApp]'s root `Stack`, not a
/// descendant of it, so it sits outside the `Navigator`'s `Overlay` that a
/// tooltip needs. [Semantics] carries the same information to assistive
/// tech without that dependency.
class GlobalSoundToggle extends StatelessWidget {
  const GlobalSoundToggle({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 8,
      bottom: 8,
      child: SafeArea(
        child: Consumer(
          builder: (context, ref, _) {
            final muted = ref.watch(audioMutedProvider);
            return Semantics(
              button: true,
              label: muted ? 'Unmute sound' : 'Mute sound',
              child: Material(
                color: HETheme.pfSurfaceRaised.withValues(alpha: 0.85),
                shape: const CircleBorder(),
                elevation: 2,
                child: IconButton(
                  icon: Icon(
                    muted
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                  ),
                  color: HETheme.pfTextSecondary,
                  onPressed: () => toggleAllAudioMuted(ref),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
