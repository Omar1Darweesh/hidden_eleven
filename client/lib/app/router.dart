import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hidden_eleven/app/routes.dart';
import 'package:hidden_eleven/features/game/game_screen.dart';
import 'package:hidden_eleven/features/home/home_screen.dart';
import 'package:hidden_eleven/features/host/host_room_screen.dart';
import 'package:hidden_eleven/features/join/join_room_screen.dart';
import 'package:hidden_eleven/features/lobby/lobby_screen.dart';
import 'package:hidden_eleven/features/admin/admin_shell.dart';
import 'package:hidden_eleven/features/help/help_screen.dart';
import 'package:hidden_eleven/features/result/result_screen.dart';
import 'package:hidden_eleven/features/tournament/screens/tournament_hub_screen.dart';
import 'package:hidden_eleven/features/tournament/screens/tournament_complete_screen.dart';

/// Lets a screen know when another route is pushed on top of it / popped
/// back to it — used by [HomeScreen] to pause its menu music while a
/// lobby/game screen is on top (pushNamed keeps Home mounted underneath
/// rather than disposing it) and resume when the player returns to it.
final routeObserver = RouteObserver<PageRoute>();

final appRouter = GoRouter(
  initialLocation: '/',
  observers: [routeObserver],
  routes: [
    GoRoute(
      name: Routes.home,
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      name: Routes.hostRoom,
      path: '/host-room',
      builder: (context, state) {
        // A plain String extra (the ordinary "Host a Room" tap) means no
        // pre-seeded bots; the record form is how "Play vs AI" arrives here
        // with the same settings screen but AI Opponents defaulted to 1.
        final extra = state.extra;
        if (extra is ({String displayName, int botCount})) {
          return HostRoomScreen(
            displayName: extra.displayName,
            initialBotCount: extra.botCount,
          );
        }
        return HostRoomScreen(displayName: extra as String? ?? '');
      },
    ),
    GoRoute(
      name: Routes.joinRoom,
      path: '/join-room',
      builder: (context, state) {
        final displayName = state.extra as String? ?? '';
        return JoinRoomScreen(displayName: displayName);
      },
    ),
    GoRoute(
      name: Routes.lobby,
      path: '/lobby/:roomCode',
      builder: (context, state) =>
          LobbyScreen(roomCode: state.pathParameters['roomCode']!),
    ),
    GoRoute(
      name: Routes.game,
      path: '/game/:roomCode',
      builder: (context, state) =>
          GameScreen(roomCode: state.pathParameters['roomCode']!),
      routes: [
        GoRoute(
          path: 'tournament/bracket',
          builder: (context, state) => const TournamentHubScreen(),
        ),
        GoRoute(
          path: 'tournament/complete',
          builder: (context, state) => const TournamentCompleteScreen(),
        ),
      ],
    ),
    GoRoute(
      name: Routes.result,
      path: '/result/:roomCode',
      builder: (context, state) =>
          ResultScreen(roomCode: state.pathParameters['roomCode']!),
    ),
    GoRoute(
      name: Routes.admin,
      path: '/admin',
      builder: (context, state) => const AdminShell(),
    ),
    GoRoute(
      name: Routes.help,
      path: '/help',
      builder: (context, state) => const HelpScreen(),
    ),
  ],
);
