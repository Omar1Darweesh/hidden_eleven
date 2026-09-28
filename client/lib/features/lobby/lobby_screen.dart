import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/app/routes.dart';
import 'package:hidden_eleven/features/lobby/models/player.dart';
import 'package:hidden_eleven/features/lobby/models/room_state.dart';
import 'package:hidden_eleven/features/lobby/models/server_event.dart';
import 'package:hidden_eleven/features/lobby/models/spectator.dart';
import 'package:hidden_eleven/features/game/game_provider.dart';
import 'package:hidden_eleven/features/lobby/room_provider.dart';
import 'package:hidden_eleven/features/tournament/widgets/tournament_mode_badge.dart';
import 'package:hidden_eleven/shared/ads/ad_config.dart';
import 'package:hidden_eleven/shared/ads/side_ad_rail.dart';
import 'package:hidden_eleven/shared/providers/local_presence_provider.dart';
import 'package:hidden_eleven/shared/widgets/first_touch_layout.dart';
import 'package:hidden_eleven/shared/widgets/he_button.dart';
import 'package:hidden_eleven/shared/widgets/he_card.dart';
import 'package:hidden_eleven/shared/widgets/matchday_background.dart';
import 'package:hidden_eleven/shared/widgets/screen_entrance.dart';

/// Minimum connected (non-waiting) players required before the host can
/// start the match. Mirrors the same rule enforced server-side.
const int kMinPlayersToStart = 2;

class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key, required this.roomCode});

  final String roomCode;

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeBootstrap());
  }

  Future<void> _maybeBootstrap() async {
    if (!mounted) return;
    if (ref.read(roomProvider) != null) return;
    await ref.read(localPresenceProvider.notifier).ready;
    if (!mounted) return;
    final presence = ref.read(localPresenceProvider);
    if (presence == null || presence.roomCode != widget.roomCode) {
      context.goNamed(Routes.home);
      return;
    }
    ref.read(roomProvider.notifier).jumpIn();
  }

  /// Explains why start was blocked: the host's league + rating filter left
  /// one or more positions with too few cards for the current player count.
  void _showInsufficientPoolDialog(
    BuildContext context,
    List<PoolShortage> shortages,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HETheme.pfSurfaceGlass,
        title: const Text("Can't start yet"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The rating range is too narrow to fill every position for the '
              'current number of players. Not enough cards for:',
              style: TextStyle(color: HETheme.pfTextPrimary, fontSize: 13),
            ),
            const SizedBox(height: 10),
            ...shortages.map(
              (s) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '•  ${s.position} — ${s.available} available, ${s.needed} needed',
                  style: const TextStyle(
                    color: HETheme.pfAccentViolet,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Widen the rating range, add more leagues, or start with fewer '
              'players. (Rating range is set when creating the room.)',
              style: TextStyle(color: HETheme.pfTextSecondary, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(gameProvider, (prev, game) {
      if (prev == null && game != null && context.mounted) {
        final roomCode = ref.read(roomProvider)?.code ?? widget.roomCode;
        context.goNamed(Routes.game, pathParameters: {'roomCode': roomCode});
      }
    });

    ref.listen(serverErrorProvider, (_, next) {
      next.whenData((err) {
        if (!context.mounted) return;
        if (err.code == 'NOT_FOUND' || err.code == 'INVALID_TOKEN') {
          // check_presence/spectator_reconnect's rejection codes — distinct
          // from ROOM_NOT_FOUND below, which every OTHER lobby action
          // (kick/transfer/lock/approve/reject/start) returns instead.
          // Previously handled here directly, guarded on
          // `roomProvider == null` (never true while this screen is already
          // showing a live lobby — the case that matters) and racing
          // RoomNotifier's own handling of the identical event. Now handled
          // centrally and unconditionally by
          // RoomNotifier._handleReconnectRejection, which wipes all local
          // state and triggers sessionDesyncedProvider —
          // HiddenElevenApp's root builder shows the blocking
          // SessionDesyncedScreen over every route the instant that fires.
          return;
        }
        // Start blocked because the host's league + rating filter can't fill
        // every position for the current player count. This needs more than a
        // one-line toast — show a dialog naming the short positions and how to
        // fix it.
        if (err.code == 'INSUFFICIENT_DRAFT_POOL') {
          _showInsufficientPoolDialog(context, err.shortages);
          return;
        }
        // Every other lobby-action error (host moderation failures, a race
        // where the target/room/request changed between the tap and the
        // server's response, etc.) previously had no user-visible feedback
        // at all — the request just silently failed. A short, friendly toast
        // beats that for every code this screen's actions can actually
        // produce — see rooms.service.ts for the full, verified list this
        // switch is built from (KICKED is deliberately absent: it's a
        // join_room-only error this screen never triggers, already handled
        // with correct first-person wording on the join screen — including
        // it here would be dead, wrongly-voiced code. ROOM_FULL, unlike
        // KICKED, WAS added here later — a deferred-items cleanup pass found
        // approveJoin can now also return it, once approval re-checks
        // capacity at approval time rather than only when the request was
        // first queued).
        final message = switch (err.code) {
          'TARGET_DISCONNECTED' =>
            'That player is disconnected right now — try again once they reconnect.',
          'NOT_HOST' => 'Only the host can do that.',
          'PLAYER_NOT_FOUND' => 'That player is no longer in the room.',
          'NOT_IN_ROOM' => 'Connection interrupted — try that again.',
          'REQUEST_NOT_FOUND' => 'That join request is no longer available.',
          'NOT_ENOUGH_PLAYERS' => 'Need at least 2 connected players to start.',
          'ROOM_NOT_FOUND' => 'This room no longer exists.',
          'ROOM_FULL' =>
            'The room is full — you can\'t approve any more players.',
          _ => null,
        };
        if (message == null) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
        // A room the server says doesn't exist anymore has nothing left to
        // stay on — same "go home" outcome as the NOT_FOUND branch above,
        // just reached from a different error code.
        if (err.code == 'ROOM_NOT_FOUND') context.goNamed(Routes.home);
      });
    });

    // Dismisses the "Reconnecting…" banner the moment the socket is healthy
    // again — previously only socketDisconnectedProvider's full-failure path
    // hid it, so a normal retry that quietly succeeded (the common case: a
    // brief network blip, not an actual outage) left the banner stuck on
    // screen indefinitely with no further connection event to clear it.
    ref.listen(connectionStatusProvider, (prev, next) {
      if (next == ConnectionStatus.connected &&
          prev != ConnectionStatus.connected &&
          context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
      }
    });

    ref.listen(socketReconnectingProvider, (_, next) {
      next.whenData((_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showMaterialBanner(
          MaterialBanner(
            backgroundColor: HETheme.pfSurfaceGlass,
            leading: const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: HETheme.pfAccentViolet,
              ),
            ),
            content: const Text(
              'Reconnecting…',
              style: TextStyle(color: HETheme.pfTextSecondary, fontSize: 13),
            ),
            actions: const [SizedBox.shrink()],
          ),
        );
      });
    });

    ref.listen(socketDisconnectedProvider, (_, next) {
      next.whenData((_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text('Connection lost'),
            content: const Text(
              'Could not reconnect to the server. You will be returned to the home screen.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  ref.read(roomProvider.notifier).leaveLobby();
                  Navigator.of(context).pop();
                  context.goNamed(Routes.home);
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      });
    });

    ref.listen(joinRequestProvider, (_, next) {
      next.whenData((req) {
        if (!context.mounted) return;
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text('Join Request'),
            content: Text('${req.displayName} wants to join the room.'),
            actions: [
              TextButton(
                onPressed: () {
                  ref.read(roomProvider.notifier).rejectJoin(req.requestId);
                  Navigator.of(context).pop();
                },
                style: TextButton.styleFrom(foregroundColor: HETheme.pfDanger),
                child: const Text('Decline'),
              ),
              TextButton(
                onPressed: () {
                  ref.read(roomProvider.notifier).approveJoin(req.requestId);
                  Navigator.of(context).pop();
                },
                style: TextButton.styleFrom(
                  foregroundColor: HETheme.pfSuccess,
                ),
                child: const Text('Accept'),
              ),
            ],
          ),
        );
      });
    });

    ref.listen(kickedProvider, (_, next) {
      next.whenData((_) {
        if (!context.mounted) return;
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text('Removed from room'),
            content: const Text('The host has removed you from this room.'),
            actions: [
              TextButton(
                onPressed: () {
                  ref.read(roomProvider.notifier).clearAfterKick();
                  Navigator.of(context).pop();
                  context.goNamed(Routes.home);
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      });
    });

    final room = ref.watch(roomProvider);

    if (room == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isHost = room.localPlayer?.isHost ?? false;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.meeting_room_rounded,
              color: HETheme.pfAccentViolet,
              size: 18,
            ),
            const SizedBox(width: 8),
            const Text('Lobby'),
          ],
        ),
        actions: [
          if (isHost) _LockButton(room: room),
          TextButton.icon(
            onPressed: () {
              ref.read(roomProvider.notifier).leaveLobby();
              context.goNamed(Routes.home);
            },
            icon: const Icon(Icons.exit_to_app_rounded, size: 16),
            label: const Text('Leave'),
            style: TextButton.styleFrom(foregroundColor: HETheme.pfDanger),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SideAdRail(
        slotId: AdConfig.lobbySideSlot,
        child: Stack(
          children: [
            const MatchdayBackground(),
            SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: FirstTouchLayout(
                    child: ScreenEntrance(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _RoomCodeHero(
                            code: room.code,
                            isLocked: room.isLocked,
                            tournamentEnabled: room.tournamentEnabled,
                            isHost: isHost,
                          ),
                          const SizedBox(height: 16),
                          _LobbyStatusBanner(room: room, isHost: isHost),
                          const SizedBox(height: 24),
                          _PlayerList(room: room, isHost: isHost),
                          SpectatorList(spectators: room.spectators),
                          const SizedBox(height: 20),
                          _RatingRangeCard(room: room, isHost: isHost),
                          const SizedBox(height: 16),
                          _RoomBriefEcho(room: room),
                          const SizedBox(height: 8),
                          _QuickRulesLink(),
                          const SizedBox(height: 20),
                          _StartButton(room: room),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Lock button with pending badge ────────────────────────────────────────────

class _LockButton extends StatelessWidget {
  const _LockButton({required this.room});
  final RoomState room;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topRight,
      children: [
        Consumer(
          builder: (context, ref, _) => IconButton(
            tooltip: room.isLocked ? 'Unlock room' : 'Lock room',
            icon: Icon(
              room.isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
              size: 20,
              color: room.isLocked ? HETheme.pfAccentViolet : HETheme.pfTextSecondary,
            ),
            onPressed: () {
              if (room.isLocked) {
                ref.read(roomProvider.notifier).unlockRoom();
              } else {
                ref.read(roomProvider.notifier).lockRoom();
              }
            },
          ),
        ),
        if (room.pendingCount > 0)
          Positioned(
            top: 5,
            right: 5,
            // Was 16px/9px — the digit was close to illegible at a glance.
            // Size only; colours are untouched here (this screen's palette
            // migration is separate, later work).
            child: Container(
              width: 18,
              height: 18,
              decoration: const BoxDecoration(
                color: HETheme.pfDanger,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '${room.pendingCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Room code hero ────────────────────────────────────────────────────────────

/// The page's primary anchor — presents the room code like a match ticket:
/// a navy/cyan branded hero card with a large, legible code and a clear
/// copy action, plus the tournament badge folded in underneath so the hero
/// carries the room's full identity in one glance.
class _RoomCodeHero extends StatelessWidget {
  const _RoomCodeHero({
    required this.code,
    required this.isLocked,
    required this.tournamentEnabled,
    required this.isHost,
  });

  final String code;
  final bool isLocked;
  final bool tournamentEnabled;
  final bool isHost;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        HETheme.spaceXl,
        HETheme.spaceXxl,
        HETheme.spaceXl,
        HETheme.spaceXl,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [HETheme.pfSurfaceDeep, HETheme.pfBgVoid],
        ),
        borderRadius: BorderRadius.circular(HETheme.radiusLg),
        border: Border.all(color: HETheme.pfAccentViolet.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: HETheme.pfAccentViolet.withValues(alpha: 0.16),
            blurRadius: 32,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const HESectionLabel('Room Code'),
              if (isLocked) ...[
                const SizedBox(width: 8),
                HEBadge(
                  'Locked',
                  color: HETheme.pfAccentViolet,
                  icon: Icons.lock_rounded,
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    code,
                    style: const TextStyle(
                      color: HETheme.pfAccentViolet,
                      fontSize: 44,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _CopyCodeButton(code: code),
          const SizedBox(height: 12),
          Text(
            'Share this code with your friends to bring them in',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: HETheme.pfTextSecondary),
          ),
          if (tournamentEnabled) ...[
            const SizedBox(height: 18),
            const Divider(height: 1, color: HETheme.pfBorder),
            const SizedBox(height: 14),
            const Center(child: TournamentModeBadge(tournamentEnabled: true)),
            if (isHost) ...[
              const SizedBox(height: 6),
              const Center(
                child: Text(
                  'You enabled this — players will see a bracket after the draft.',
                  style: TextStyle(color: HETheme.pfTextSecondary, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _CopyCodeButton extends StatelessWidget {
  const _CopyCodeButton({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(HETheme.radiusMd),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: code));
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Room code copied')));
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: HETheme.spaceLg,
          vertical: HETheme.spaceSm + 2,
        ),
        decoration: BoxDecoration(
          color: HETheme.pfAccentViolet.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(HETheme.radiusMd),
          border: Border.all(color: HETheme.pfAccentViolet.withValues(alpha: 0.4)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.copy_rounded, size: 15, color: HETheme.pfAccentViolet),
            SizedBox(width: 8),
            Text(
              'Copy code',
              style: TextStyle(
                color: HETheme.pfAccentViolet,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Lobby status banner ───────────────────────────────────────────────────────

/// Ties the room's current state into one readable line: whether the squad
/// is still filling up or ready to kick off, who can act next, and whether
/// the room is accepting new players. Built from data the model already
/// exposes (connection state, host flag, lock flag, pending count) — no new
/// networking concepts introduced.
class _LobbyStatusBanner extends StatelessWidget {
  const _LobbyStatusBanner({required this.room, required this.isHost});

  final RoomState room;
  final bool isHost;

  @override
  Widget build(BuildContext context) {
    final connectedCount = room.players
        .where((p) => p.isConnected && !p.isWaiting)
        .length;
    final readyToStart = connectedCount >= kMinPlayersToStart;

    final Color tint = readyToStart
        ? HETheme.pfSuccess
        : HETheme.pfAccentViolet;
    final IconData icon = readyToStart
        ? Icons.check_circle_rounded
        : Icons.hourglass_top_rounded;
    final String title = readyToStart
        ? 'Ready to kick off'
        : 'Waiting for players';
    final String subtitle = readyToStart
        ? (isHost
              ? 'You can start the match whenever you’re ready.'
              : 'Waiting for the host to start the match.')
        : 'Need ${kMinPlayersToStart - connectedCount} more player'
              '${kMinPlayersToStart - connectedCount == 1 ? '' : 's'} to kick off.';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: HETheme.spaceLg,
        vertical: HETheme.spaceMd + 2,
      ),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(HETheme.radiusLg),
        border: Border(left: BorderSide(color: tint, width: 3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: tint),
          const SizedBox(width: HETheme.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: tint,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: HETheme.pfTextSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (isHost && room.pendingCount > 0) ...[
            const SizedBox(width: HETheme.spaceSm),
            HEBadge(
              '${room.pendingCount} waiting',
              color: HETheme.pfDanger,
              icon: Icons.person_add_alt_1_rounded,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Player list ───────────────────────────────────────────────────────────────

class _PlayerList extends ConsumerWidget {
  const _PlayerList({required this.room, required this.isHost});

  final RoomState room;
  final bool isHost;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const HESectionLabel('Players'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: HETheme.pfSurfaceGlass,
                borderRadius: BorderRadius.circular(HETheme.radiusSm),
                border: Border.all(color: HETheme.pfBorder),
              ),
              child: Text(
                '${room.players.length}',
                style: const TextStyle(
                  color: HETheme.pfTextSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Spacer(),
            // Lets a room with real players ALSO seat bots — to fill seats
            // nobody's joined yet, not just at solo-game creation. Errors
            // (room full, room already started) surface via the same
            // serverErrorProvider toast every other lobby action uses.
            if (isHost && !room.isStarted)
              TextButton.icon(
                onPressed: () => ref.read(roomProvider.notifier).addBot(1),
                icon: const Icon(Icons.smart_toy_outlined, size: 16),
                label: const Text('Add Bot'),
                style: TextButton.styleFrom(
                  foregroundColor: HETheme.pfAccentViolet,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        HECard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (int i = 0; i < room.players.length; i++) ...[
                // Keyed by player id (not position) so Flutter treats a
                // genuinely new seat — a friend joining, a bot the host just
                // added — as a fresh element that mounts (and plays the pop
                // below) rather than reusing whatever State object happened
                // to sit at that list index before.
                _TilePopIn(
                  key: ValueKey(room.players[i].id),
                  child: _PlayerTile(
                    player: room.players[i],
                    isHost: isHost,
                    isLocalPlayer: room.players[i].id == room.localPlayerId,
                    onKick: () => ref
                        .read(roomProvider.notifier)
                        .kickPlayer(room.players[i].id),
                    onTransferHost: () => ref
                        .read(roomProvider.notifier)
                        .transferHost(room.players[i].id),
                  ),
                ),
                if (i < room.players.length - 1)
                  const Divider(height: 1, indent: 20, endIndent: 20),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Plays a scale+fade "pop" exactly once when a player row first mounts —
/// which, thanks to being keyed by player id at the call site, is precisely
/// when a genuinely new seat appears (a friend joins, the host adds a bot),
/// not on every rebuild an existing row goes through (connection status
/// changing, a kick menu opening, etc).
class _TilePopIn extends StatefulWidget {
  const _TilePopIn({super.key, required this.child});
  final Widget child;

  @override
  State<_TilePopIn> createState() => _TilePopInState();
}

class _TilePopInState extends State<_TilePopIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    return FadeTransition(
      opacity: _controller,
      child: ScaleTransition(scale: curved, child: widget.child),
    );
  }
}

class _PlayerTile extends StatelessWidget {
  const _PlayerTile({
    required this.player,
    required this.isHost,
    required this.isLocalPlayer,
    required this.onKick,
    required this.onTransferHost,
  });

  final Player player;
  final bool isHost;
  final bool isLocalPlayer;
  final VoidCallback onKick;
  final VoidCallback onTransferHost;

  bool get _isDimmed => player.isWaiting || !player.isConnected;

  Widget _statusIcon() {
    if (player.isWaiting) {
      return const Icon(
        Icons.hourglass_empty_rounded,
        size: 16,
        color: HETheme.pfTextSecondary,
      );
    }
    if (!player.isConnected) {
      return const Icon(
        Icons.wifi_off_rounded,
        size: 16,
        color: HETheme.pfDanger,
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final showStatus = player.isWaiting || !player.isConnected;
    // A connected, non-placeholder player is on the pitch and ready to go —
    // this labels that existing derived state rather than adding a new one.
    final isReady = !player.isWaiting && player.isConnected;

    return Container(
      color: isLocalPlayer
          ? HETheme.pfAccentViolet.withValues(alpha: 0.06)
          : Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: HETheme.spaceXl,
          vertical: HETheme.spaceMd + 2,
        ),
        child: Row(
          children: [
            // "You" highlight rail
            Container(
              width: 3,
              height: 34,
              margin: const EdgeInsets.only(right: HETheme.spaceMd),
              decoration: BoxDecoration(
                color: isLocalPlayer ? HETheme.pfAccentViolet : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Avatar with colour derived from name
            if (_isDimmed)
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: HETheme.pfSurfaceRaised,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: HETheme.pfBorder),
                ),
                child: Center(child: _statusIcon()),
              )
            else
              HEAvatar(name: player.displayName, size: 38, radius: 10),

            const SizedBox(width: 14),

            // Name + status
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          player.displayName,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: _isDimmed
                                    ? HETheme.pfTextSecondary
                                    : HETheme.pfTextPrimary,
                                fontWeight: FontWeight.w600,
                                fontStyle: player.isWaiting
                                    ? FontStyle.italic
                                    : null,
                              ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isLocalPlayer) ...[
                        const SizedBox(width: 6),
                        HEBadge('You', color: HETheme.pfAccentViolet),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  if (showStatus)
                    Text(
                      player.isWaiting ? 'Reconnecting…' : 'Disconnected',
                      style: TextStyle(
                        color: player.isConnected
                            ? HETheme.pfTextSecondary
                            : HETheme.pfDanger,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else if (isReady)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: HETheme.pfSuccess,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'Ready',
                          style: TextStyle(
                            color: HETheme.pfSuccess,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),

            // HOST badge
            if (player.isHost)
              const HEBadge(
                'Host',
                color: HETheme.pfGold,
                icon: Icons.star_rounded,
              ),

            // BOT badge — a bot is always isConnected:true (it has no socket
            // to drop), so without this it would look like an ordinary,
            // already-joined human player.
            if (player.isBot) ...[
              const SizedBox(width: 4),
              const HEBadge(
                'AI',
                color: HETheme.pfAccentViolet,
                icon: Icons.smart_toy_outlined,
              ),
            ],

            // Host action menu
            if (isHost && !isLocalPlayer && !player.isHost) ...[
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'kick') onKick();
                  if (value == 'transfer') onTransferHost();
                },
                icon: const Icon(
                  Icons.more_vert_rounded,
                  size: 20,
                  color: HETheme.pfTextSecondary,
                ),
                itemBuilder: (_) => [
                  // Transferring host to someone currently disconnected would
                  // leave the room with no reachable host until they happen
                  // to reconnect — the server rejects this too
                  // (TARGET_DISCONNECTED), but omitting the option here means
                  // the host never sees an action that can't succeed. A bot
                  // is always isConnected:true (no socket to drop) but
                  // obviously can't run the room either, so it's excluded
                  // the same way regardless of that flag.
                  if (player.isConnected && !player.isBot)
                    const PopupMenuItem(
                      value: 'transfer',
                      child: Row(
                        children: [
                          Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: HETheme.pfGold,
                          ),
                          SizedBox(width: 10),
                          Text('Make Host'),
                        ],
                      ),
                    ),
                  PopupMenuItem(
                    value: 'kick',
                    child: Row(
                      children: [
                        const Icon(
                          Icons.person_remove_rounded,
                          size: 16,
                          color: HETheme.pfDanger,
                        ),
                        const SizedBox(width: 10),
                        Text('Kick', style: TextStyle(color: HETheme.pfDanger)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Spectator list ─────────────────────────────────────────────────────────
//
// Deliberately minimal — first spectator-visibility slice only (see
// FLUTTER_CLIENT_AUDIT.md). No connection-status detail beyond a dimmed
// name, no host moderation actions (spectators aren't kickable/transferable
// today), no interaction at all. Renders nothing when empty, so a room with
// no spectators looks exactly like it did before this existed.
//
// Public (not `_SpectatorList`) specifically so it's directly widget-testable
// in isolation — it has no provider/context dependencies of its own, just a
// plain `spectators` list, so it doesn't need the rest of LobbyScreen's
// router/provider setup to verify it renders correctly.

class SpectatorList extends StatelessWidget {
  const SpectatorList({super.key, required this.spectators});

  final List<Spectator> spectators;

  @override
  Widget build(BuildContext context) {
    if (spectators.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.visibility_rounded,
                size: 14,
                color: HETheme.pfTextSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                'Watching (${spectators.length})',
                style: const TextStyle(
                  color: HETheme.pfTextSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: spectators
                .map(
                  (s) => HEBadge(
                    s.displayName,
                    color: s.isConnected
                        ? HETheme.pfTextSecondary
                        : HETheme.pfDanger,
                    icon: s.isConnected
                        ? Icons.visibility_rounded
                        : Icons.wifi_off_rounded,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ── Start button ──────────────────────────────────────────────────────────────

// ── Room brief echo ───────────────────────────────────────────────────────────

/// Read-only recap of the room's settings, using only fields [RoomState]
/// already exposes — leagues and tournament mode. No new backend call, no
/// new provider; just surfacing what's already on `room` in one compact
/// line so a host can double-check what they configured without leaving
/// the lobby.
class _RoomBriefEcho extends StatelessWidget {
  const _RoomBriefEcho({required this.room});

  final RoomState room;

  @override
  Widget build(BuildContext context) {
    final leagueSummary = room.leagues.isEmpty
        ? 'All allowed leagues'
        : room.leagues.join(', ');
    final parts = [
      leagueSummary,
      if (room.tournamentEnabled) 'Tournament mode',
    ];
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: HETheme.spaceLg,
        vertical: HETheme.spaceMd,
      ),
      decoration: BoxDecoration(
        color: HETheme.pfSurfaceRaised,
        borderRadius: BorderRadius.circular(HETheme.radiusMd),
        border: Border.all(color: HETheme.pfBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.summarize_outlined,
            color: HETheme.pfTextMuted,
            size: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              parts.join('  ·  '),
              style: const TextStyle(
                color: HETheme.pfTextSecondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Quick rules link ──────────────────────────────────────────────────────────

/// Waiting-room productivity: a low-emphasis link into the existing Help
/// route — no new help content, just a way to review the rules while
/// waiting for other players.
class _QuickRulesLink extends StatelessWidget {
  const _QuickRulesLink();

  @override
  Widget build(BuildContext context) {
    return HEButton(
      label: 'Review Quick Rules',
      icon: Icons.help_outline_rounded,
      variant: HEButtonVariant.ghost,
      onPressed: () => context.pushNamed(Routes.help),
    );
  }
}

class _StartButton extends ConsumerWidget {
  const _StartButton({required this.room});

  final RoomState room;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localPlayer = room.localPlayer;
    final isHost = localPlayer?.isHost ?? false;
    final connectedCount = room.players
        .where((p) => p.isConnected && !p.isWaiting)
        .length;
    final canStart = isHost && connectedCount >= kMinPlayersToStart;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HEButton(
          label: isHost
              ? (canStart ? 'Start Game' : 'Need at least 2 players…')
              : 'Waiting for host to start…',
          icon: isHost && canStart
              ? Icons.play_arrow_rounded
              : Icons.hourglass_empty_rounded,
          onPressed: canStart
              ? () => ref.read(roomProvider.notifier).startGame()
              : null,
        ),
        // A persistent caption beneath the button, not just the label swap
        // above — the label change alone is easy to miss since it's the
        // only thing that differs from the enabled state.
        if (!isHost) ...[
          const SizedBox(height: 8),
          const Text(
            'Only the host can start the match.',
            textAlign: TextAlign.center,
            style: TextStyle(color: HETheme.pfTextMuted, fontSize: 11),
          ),
        ] else if (!canStart) ...[
          const SizedBox(height: 8),
          Text(
            'Waiting for ${kMinPlayersToStart - connectedCount} more connected '
            '${kMinPlayersToStart - connectedCount == 1 ? 'player' : 'players'} '
            'before you can start.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: HETheme.pfTextMuted, fontSize: 11),
          ),
        ],
      ],
    );
  }
}

/// Lobby card for the draft rating window. The host gets a live dual-handle
/// slider; every change is sent to the server, which re-broadcasts the range
/// plus a fresh pool-sufficiency check for the CURRENT player count — so the
/// status line below updates both as the host drags and as players join or
/// leave. Guests see a read-only view, and only when a restriction is active.
class _RatingRangeCard extends ConsumerStatefulWidget {
  const _RatingRangeCard({required this.room, required this.isHost});

  final RoomState room;
  final bool isHost;

  @override
  ConsumerState<_RatingRangeCard> createState() => _RatingRangeCardState();
}

class _RatingRangeCardState extends ConsumerState<_RatingRangeCard> {
  late RangeValues _values;

  @override
  void initState() {
    super.initState();
    _values = _fromRoom(widget.room);
  }

  RangeValues _fromRoom(RoomState r) => RangeValues(
    (r.minRating ?? 1).toDouble(),
    (r.maxRating ?? 99).toDouble(),
  );

  @override
  void didUpdateWidget(covariant _RatingRangeCard old) {
    super.didUpdateWidget(old);
    // Re-sync only when the room's window actually changed (our committed
    // edit echoed back, or a reconnect refresh) — never on unrelated
    // room_updates like a player joining, which must not clobber a live drag.
    if (old.room.minRating != widget.room.minRating ||
        old.room.maxRating != widget.room.maxRating) {
      _values = _fromRoom(widget.room);
    }
  }

  void _commit(RangeValues v) {
    final min = v.start.round();
    final max = v.end.round();
    ref
        .read(roomProvider.notifier)
        .setRatingRange(min > 1 ? min : null, max < 99 ? max : null);
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final restricted = room.ratingRestricted;
    // Guests only see this card when a restriction is actually in effect.
    if (!widget.isHost && !restricted) return const SizedBox.shrink();

    final minV = _values.start.round();
    final maxV = _values.end.round();
    final ok = room.poolOk;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HETheme.pfSurfaceRaised,
        borderRadius: BorderRadius.circular(HETheme.radiusMd),
        border: Border.all(
          color: ok ? HETheme.pfBorder : HETheme.pfDanger.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.tune_rounded,
                color: HETheme.pfTextSecondary,
                size: 16,
              ),
              const SizedBox(width: 8),
              const Text(
                'Card Rating Range',
                style: TextStyle(
                  color: HETheme.pfTextPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                restricted ? '$minV–$maxV' : 'All cards',
                style: TextStyle(
                  color: restricted
                      ? HETheme.pfAccentViolet
                      : HETheme.pfTextSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (widget.isHost)
            RangeSlider(
              values: _values,
              min: 1,
              max: 99,
              divisions: 98,
              labels: RangeLabels('$minV', '$maxV'),
              activeColor: HETheme.pfAccentViolet,
              inactiveColor: HETheme.pfBorder,
              onChanged: (v) {
                if (v.end - v.start < 1) return;
                setState(() => _values = v);
              },
              onChangeEnd: _commit,
            )
          else
            const SizedBox(height: 10),
          _RatingStatusLine(room: room),
        ],
      ),
    );
  }
}

/// The green/amber "does this filter fit the current players?" line under the
/// rating slider. Driven entirely by the server's live pool-sufficiency check.
class _RatingStatusLine extends StatelessWidget {
  const _RatingStatusLine({required this.room});

  final RoomState room;

  @override
  Widget build(BuildContext context) {
    final count = room.players
        .where((p) => p.isConnected && !p.isWaiting)
        .length;

    if (room.poolOk) {
      return Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF2ECC71),
            size: 15,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Enough players for every position ($count in room).',
              style: const TextStyle(
                color: Color(0xFF2ECC71),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }

    final shorts = room.poolShortages
        .map((s) => '${s.position} ${s.available}/${s.needed}')
        .join(' · ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.warning_amber_rounded,
          color: HETheme.pfDanger,
          size: 15,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Too narrow for $count players — short: $shorts. '
            'Widen the range to start.',
            style: const TextStyle(
              color: HETheme.pfDanger,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
