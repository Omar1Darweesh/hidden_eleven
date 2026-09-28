import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/lobby/lobby_screen.dart';
import 'package:hidden_eleven/features/lobby/models/room_state.dart';
import 'package:hidden_eleven/features/lobby/models/server_event.dart';
import 'package:hidden_eleven/features/lobby/models/spectator.dart';
import 'package:hidden_eleven/features/lobby/room_provider.dart';

/// Coverage for the Flutter client audit's spectator-safety fixes (see
/// FLUTTER_CLIENT_AUDIT.md) across two passes:
///
/// Pass 1 — `room_update`'s `localPlayerId`: a spectator's room_update
/// carries `localPlayerId: null` from the server. `_parseRoomUpdate` used to
/// coerce a missing/null value all the way down to `''`, which RoomNotifier
/// would then cache via `setCachedPlayerId('')` — silently corrupting a real
/// player's cached identity. Also covers the additive `RoomState.spectators`
/// parsing added in the same pass.
///
/// Pass 2 — the identical mirror bug in `game_state`'s `localPlayerId`
/// (`_parseGameState`), plus the first spectate_room/stop_spectating client
/// plumbing: `RoomUpdated.localSpectatorId`, its own cached-fallback
/// (mirroring localPlayerId's, for the same "don't look like you stopped
/// spectating just because someone else broadcast something" reason), and
/// `RoomState.clearLocalSpectatorId()` (stopSpectating's optimistic clear,
/// since the server sends this socket no ack for stop_spectating).
///
/// `isCacheablePlayerId` was renamed to `isCacheableId` in pass 2 since the
/// same guard is now shared by both player and spectator ids.
void main() {
  group('parseServerEvent — room_update localPlayerId (spectator safety)', () {
    Map<String, dynamic> roomUpdateEvent({
      String? localPlayerId,
      List<Map<String, dynamic>>? spectators,
    }) => {
      'event': 'room_update',
      'data': {
        'code': 'ABCDEF',
        'players': [
          {
            'id': 'p1',
            'displayName': 'Alice',
            'isHost': true,
            'isConnected': true,
          },
        ],
        if (spectators != null) 'spectators': spectators,
        'isStarted': false,
        'isLocked': false,
        'pendingCount': 0,
        if (localPlayerId != null) 'localPlayerId': localPlayerId,
        'tournamentEnabled': false,
      },
    };

    test(
      'a spectator room_update (localPlayerId: null, no cached id) stays null — never coerced to empty string',
      () {
        final event = parseServerEvent(roomUpdateEvent(), null) as RoomUpdated;

        expect(event.localPlayerId, isNull);
        expect(event.room.localPlayerId, isNull);
      },
    );

    test(
      'localPlayerId: null falls back to a cached player id when one exists (a real player broadcast, not a spectator)',
      () {
        final event =
            parseServerEvent(roomUpdateEvent(), 'cached-p1') as RoomUpdated;

        expect(event.localPlayerId, 'cached-p1');
        expect(event.room.localPlayerId, 'cached-p1');
      },
    );

    test(
      'a real localPlayerId from the server is used directly, ignoring any cached value',
      () {
        final event =
            parseServerEvent(
                  roomUpdateEvent(localPlayerId: 'p1'),
                  'stale-cached-id',
                )
                as RoomUpdated;

        expect(event.localPlayerId, 'p1');
      },
    );

    test(
      'an explicit JSON null for localPlayerId (the exact shape a spectator ack sends) resolves to null, not the string "null"',
      () {
        // Mirrors the real server payload shape: the key is present with a
        // JSON null value (exactly what jsonDecode produces for a server
        // response containing `"localPlayerId": null`), not simply absent.
        final event =
            parseServerEvent({
                  'event': 'room_update',
                  'data': <String, dynamic>{
                    'code': 'ABCDEF',
                    'players': <dynamic>[],
                    'localPlayerId': null,
                  },
                }, null)
                as RoomUpdated;

        expect(event.localPlayerId, isNull);
      },
    );
  });

  group('parseServerEvent — room_update spectators (additive parsing)', () {
    test('spectators array parses into the Spectator model correctly', () {
      final event =
          parseServerEvent({
                'event': 'room_update',
                'data': {
                  'code': 'ABCDEF',
                  'players': [],
                  'spectators': [
                    {
                      'id': 'spec-1',
                      'displayName': 'Watcher',
                      'isConnected': true,
                    },
                    {
                      'id': 'spec-2',
                      'displayName': 'Lurker',
                      'isConnected': false,
                    },
                  ],
                },
              }, null)
              as RoomUpdated;

      expect(event.room.spectators, hasLength(2));
      expect(event.room.spectators[0].id, 'spec-1');
      expect(event.room.spectators[0].displayName, 'Watcher');
      expect(event.room.spectators[0].isConnected, true);
      expect(event.room.spectators[1].isConnected, false);
    });

    test(
      'a missing spectators field is safe and defaults to an empty list (backward-compatible with older payload shapes)',
      () {
        final event =
            parseServerEvent({
                  'event': 'room_update',
                  'data': {
                    'code': 'ABCDEF',
                    'players': [
                      {
                        'id': 'p1',
                        'displayName': 'Alice',
                        'isHost': true,
                        'isConnected': true,
                      },
                    ],
                    // No 'spectators' key at all.
                  },
                }, null)
                as RoomUpdated;

        expect(event.room.spectators, isEmpty);
      },
    );

    test(
      'existing player parsing is completely unaffected by the spectators addition',
      () {
        final event =
            parseServerEvent({
                  'event': 'room_update',
                  'data': {
                    'code': 'ABCDEF',
                    'players': [
                      {
                        'id': 'p1',
                        'displayName': 'Alice',
                        'isHost': true,
                        'isConnected': true,
                      },
                      {
                        'id': 'p2',
                        'displayName': 'Bob',
                        'isHost': false,
                        'isConnected': false,
                      },
                    ],
                    'isStarted': true,
                    'isLocked': true,
                    'pendingCount': 3,
                    'localPlayerId': 'p1',
                    'tournamentEnabled': true,
                  },
                }, null)
                as RoomUpdated;

        expect(event.room.players, hasLength(2));
        expect(event.room.players[0].id, 'p1');
        expect(event.room.players[0].isHost, true);
        expect(event.room.players[1].isConnected, false);
        expect(event.room.isStarted, true);
        expect(event.room.isLocked, true);
        expect(event.room.pendingCount, 3);
        expect(event.room.localPlayerId, 'p1');
        expect(event.room.tournamentEnabled, true);
        expect(event.room.localPlayer?.id, 'p1');
      },
    );
  });

  group(
    'isCacheableId — the RoomNotifier caching guard (shared by player and spectator ids)',
    () {
      test('null is not cacheable', () {
        expect(isCacheableId(null), isFalse);
      });

      test('empty string is not cacheable', () {
        expect(isCacheableId(''), isFalse);
      });

      test('a real id is cacheable', () {
        expect(isCacheableId('a-real-uuid'), isTrue);
      });
    },
  );

  group('parseServerEvent — game_state localPlayerId (mirror fix)', () {
    Map<String, dynamic> gameStateEvent({String? localPlayerId}) => {
      'event': 'game_state',
      'data': <String, dynamic>{
        'sessionId': 'sess-1',
        'roomCode': 'ABCDEF',
        'players': <dynamic>[],
        'pitches': <String, dynamic>{},
        'turn': <String, dynamic>{},
        'status': 'drafting',
        'localPlayerId': localPlayerId,
      },
    };

    test(
      'a spectator game_state (localPlayerId: null, no cached id) stays null — never coerced to empty string',
      () {
        final event =
            parseServerEvent(gameStateEvent(), null) as GameStateReceived;

        expect(event.localPlayerId, isNull);
      },
    );

    test(
      'localPlayerId: null falls back to a cached player id when one exists',
      () {
        final event =
            parseServerEvent(gameStateEvent(), 'cached-p1')
                as GameStateReceived;

        expect(event.localPlayerId, 'cached-p1');
      },
    );

    test(
      'a real localPlayerId from the server is used directly, ignoring any cached value',
      () {
        final event =
            parseServerEvent(
                  gameStateEvent(localPlayerId: 'p1'),
                  'stale-cached-id',
                )
                as GameStateReceived;

        expect(event.localPlayerId, 'p1');
      },
    );
  });

  group(
    'parseServerEvent — room_update localSpectatorId (spectate_room plumbing)',
    () {
      test(
        'a spectate_room ack (localSpectatorId present, no cache) resolves directly',
        () {
          final event =
              parseServerEvent({
                    'event': 'room_update',
                    'data': <String, dynamic>{
                      'code': 'ABCDEF',
                      'players': <dynamic>[],
                      'localSpectatorId': 'spec-1',
                    },
                  }, null)
                  as RoomUpdated;

          expect(event.localSpectatorId, 'spec-1');
          expect(event.room.localSpectatorId, 'spec-1');
          expect(event.room.isSpectating, isTrue);
          // A spectator never also has a player seat.
          expect(event.localPlayerId, isNull);
        },
      );

      test(
        'a generic room broadcast (localSpectatorId: null) falls back to the cached spectator id — a spectator does not appear to stop spectating just because someone else joined',
        () {
          final event =
              parseServerEvent(
                    {
                      'event': 'room_update',
                      'data': <String, dynamic>{
                        'code': 'ABCDEF',
                        'players': <dynamic>[],
                        'localSpectatorId': null,
                      },
                    },
                    null,
                    null,
                    'cached-spec-1',
                  )
                  as RoomUpdated;

          expect(event.localSpectatorId, 'cached-spec-1');
          expect(event.room.isSpectating, isTrue);
        },
      );

      test('no localSpectatorId and no cache means not spectating', () {
        final event =
            parseServerEvent({
                  'event': 'room_update',
                  'data': <String, dynamic>{
                    'code': 'ABCDEF',
                    'players': <dynamic>[],
                  },
                }, null)
                as RoomUpdated;

        expect(event.localSpectatorId, isNull);
        expect(event.room.isSpectating, isFalse);
      });
    },
  );

  group(
    'RoomState.clearLocalSpectatorId — used by stopSpectating\'s optimistic clear',
    () {
      test(
        'clears localSpectatorId back to null without touching any other field',
        () {
          const room = RoomState(
            code: 'ABCDEF',
            players: [],
            localPlayerId: null,
            localSpectatorId: 'spec-1',
            isStarted: true,
            isLocked: true,
            pendingCount: 2,
            tournamentEnabled: true,
          );

          final cleared = room.clearLocalSpectatorId();

          expect(cleared.localSpectatorId, isNull);
          expect(cleared.isSpectating, isFalse);
          expect(cleared.code, 'ABCDEF');
          expect(cleared.isStarted, true);
          expect(cleared.isLocked, true);
          expect(cleared.pendingCount, 2);
          expect(cleared.tournamentEnabled, true);
        },
      );

      test(
        'copyWith cannot clear localSpectatorId (documents the known limitation clearLocalSpectatorId exists to work around)',
        () {
          const room = RoomState(
            code: 'ABCDEF',
            players: [],
            localSpectatorId: 'spec-1',
          );

          // Passing null through copyWith's `??` convention keeps the old value —
          // this is exactly why stopSpectating uses clearLocalSpectatorId() instead.
          final unchanged = room.copyWith(localSpectatorId: null);

          expect(unchanged.localSpectatorId, 'spec-1');
        },
      );
    },
  );

  group('SpectatorList widget — minimal lobby spectator visibility', () {
    testWidgets(
      'renders nothing when there are no spectators (a room with none looks exactly as before)',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: SpectatorList(spectators: [])),
          ),
        );

        expect(find.byType(SpectatorList), findsOneWidget);
        expect(find.text('Watching (0)'), findsNothing);
        expect(find.byIcon(Icons.visibility_rounded), findsNothing);
      },
    );

    testWidgets('renders a "Watching (N)" label and one badge per spectator', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SpectatorList(
              spectators: [
                Spectator(
                  id: 'spec-1',
                  displayName: 'Watcher',
                  isConnected: true,
                ),
                Spectator(
                  id: 'spec-2',
                  displayName: 'Lurker',
                  isConnected: false,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Watching (2)'), findsOneWidget);
      // HEBadge uppercases its label — this is the app's existing badge
      // convention (already used for "Host"/"You"), not something new here.
      expect(find.text('WATCHER'), findsOneWidget);
      expect(find.text('LURKER'), findsOneWidget);
      // Connected spectator gets the "watching" icon, disconnected gets the
      // "offline" icon — a real, if minimal, connection-state signal.
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    });
  });
}
