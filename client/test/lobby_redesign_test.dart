import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hidden_eleven/features/lobby/lobby_screen.dart';
import 'package:hidden_eleven/features/lobby/models/player.dart';
import 'package:hidden_eleven/features/lobby/models/room_state.dart';
import 'package:hidden_eleven/features/lobby/room_provider.dart';

/// A `RoomNotifier` stand-in that just serves a fixed [RoomState] with no
/// socket connection — the real notifier's constructor work (subscribing to
/// server events) never runs since `build()` is overridden outright.
class _FakeRoomNotifier extends RoomNotifier {
  _FakeRoomNotifier(this._state);
  final RoomState _state;

  @override
  RoomState? build() => _state;
}

Widget harness(RoomState room) => ProviderScope(
  overrides: [roomProvider.overrideWith(() => _FakeRoomNotifier(room))],
  child: MaterialApp(home: LobbyScreen(roomCode: room.code)),
);

RoomState hostOnlyRoom({
  List<String> leagues = const [],
  bool tournamentEnabled = false,
}) => RoomState(
  code: 'ABCDEF',
  players: const [Player(id: 'p1', displayName: 'Alice', isHost: true)],
  localPlayerId: 'p1',
  leagues: leagues,
  tournamentEnabled: tournamentEnabled,
);

RoomState twoPlayerRoom() => const RoomState(
  code: 'ABCDEF',
  players: [
    Player(id: 'p1', displayName: 'Alice', isHost: true),
    Player(id: 'p2', displayName: 'Bob', isHost: false),
  ],
  localPlayerId: 'p1',
);

void main() {
  group('Lobby — persistent Start Match disabled-reason caption', () {
    testWidgets(
      'host with only 1 connected player sees a caption explaining why start is blocked',
      (tester) async {
        await tester.pumpWidget(harness(hostOnlyRoom()));
        await tester.pump();

        expect(find.text('Need at least 2 players…'), findsOneWidget);
        expect(
          find.textContaining('Waiting for 1 more connected player'),
          findsOneWidget,
        );
      },
    );

    testWidgets('host with enough connected players sees no blocking caption', (
      tester,
    ) async {
      await tester.pumpWidget(harness(twoPlayerRoom()));
      await tester.pump();

      expect(find.text('Start Game'), findsOneWidget);
      expect(find.textContaining('Waiting for'), findsNothing);
    });
  });

  group('Lobby — Room Brief echo', () {
    testWidgets('shows "All allowed leagues" when none were selected', (
      tester,
    ) async {
      await tester.pumpWidget(harness(hostOnlyRoom()));
      await tester.pump();

      expect(find.textContaining('All allowed leagues'), findsOneWidget);
    });

    testWidgets('lists selected leagues and tournament mode when set', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          hostOnlyRoom(
            leagues: const ['Premier League', 'La Liga'],
            tournamentEnabled: true,
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Premier League, La Liga'), findsOneWidget);
      expect(find.textContaining('Tournament mode'), findsOneWidget);
    });
  });

  group('Lobby — quick rules link', () {
    testWidgets('offers a way to review the rules while waiting', (
      tester,
    ) async {
      await tester.pumpWidget(harness(hostOnlyRoom()));
      await tester.pump();

      expect(find.text('Review Quick Rules'), findsOneWidget);
    });
  });
}
