import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/services/local_presence_service.dart';
import 'package:hidden_eleven/services/local_spectator_presence_service.dart';
import 'package:hidden_eleven/shared/widgets/he_button.dart';
import 'package:hidden_eleven/shared/widgets/he_card.dart';

class CurrentRoomCard extends StatelessWidget {
  const CurrentRoomCard({
    super.key,
    required this.presence,
    required this.isJumpingIn,
    required this.onJumpIn,
    required this.onLeave,
  });

  final LocalPresenceData presence;
  final bool isJumpingIn;
  final VoidCallback onJumpIn;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return HECard(
      variant: HECardVariant.accent,
      padding: const EdgeInsets.all(HETheme.spaceXl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const HEBadge(
                'Game in Progress',
                icon: Icons.sports_soccer_rounded,
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: HETheme.spaceMd,
                  vertical: HETheme.spaceXs,
                ),
                decoration: BoxDecoration(
                  color: HETheme.accentEmerald.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(HETheme.radiusSm),
                ),
                child: Text(
                  presence.roomCode,
                  style: const TextStyle(
                    color: HETheme.accentEmerald,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              HEAvatar(name: presence.displayName, size: 32),
              const SizedBox(width: 10),
              Text(
                'Playing as ${presence.displayName}',
                style: const TextStyle(
                  color: HETheme.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (isJumpingIn)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(color: HETheme.accentEmerald),
              ),
            )
          else
            HEButton(
              label: 'Rejoin Game',
              icon: Icons.login_rounded,
              onPressed: onJumpIn,
            ),
          const SizedBox(height: 10),
          HEButton(
            label: 'Leave Permanently',
            icon: Icons.logout_rounded,
            variant: HEButtonVariant.secondary,
            onPressed: isJumpingIn ? null : onLeave,
          ),
        ],
      ),
    );
  }
}

/// Spectator equivalent of [CurrentRoomCard]. Only ever shown when there is
/// no player presence for this device (see home_screen.dart's precedence
/// rule) — a spectator seat has no "Leave Permanently" server-side concept,
/// since a spectator was never in the room's roster to begin with; "Stop
/// Watching" only clears the local cached seat.
class CurrentSpectatingCard extends StatelessWidget {
  const CurrentSpectatingCard({
    super.key,
    required this.presence,
    required this.isJumpingIn,
    required this.onResume,
    required this.onStopWatching,
  });

  final LocalSpectatorPresenceData presence;
  final bool isJumpingIn;
  final VoidCallback onResume;
  final VoidCallback onStopWatching;

  @override
  Widget build(BuildContext context) {
    return HECard(
      variant: HECardVariant.accent,
      padding: const EdgeInsets.all(HETheme.spaceXl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const HEBadge('Watching', icon: Icons.visibility_rounded),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: HETheme.spaceMd,
                  vertical: HETheme.spaceXs,
                ),
                decoration: BoxDecoration(
                  color: HETheme.accentEmerald.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(HETheme.radiusSm),
                ),
                child: Text(
                  presence.roomCode,
                  style: const TextStyle(
                    color: HETheme.accentEmerald,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              HEAvatar(name: presence.displayName, size: 32),
              const SizedBox(width: 10),
              Text(
                'Spectating as ${presence.displayName}',
                style: const TextStyle(
                  color: HETheme.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (isJumpingIn)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(color: HETheme.accentEmerald),
              ),
            )
          else
            HEButton(
              label: 'Resume Watching',
              icon: Icons.login_rounded,
              onPressed: onResume,
            ),
          const SizedBox(height: 10),
          HEButton(
            label: 'Stop Watching',
            icon: Icons.logout_rounded,
            variant: HEButtonVariant.secondary,
            onPressed: isJumpingIn ? null : onStopWatching,
          ),
        ],
      ),
    );
  }
}
