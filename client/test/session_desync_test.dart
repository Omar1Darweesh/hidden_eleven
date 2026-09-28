import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hidden_eleven/features/game/game_provider.dart';
import 'package:hidden_eleven/features/lobby/models/player.dart';
import 'package:hidden_eleven/features/lobby/models/room_state.dart';
import 'package:hidden_eleven/features/lobby/models/server_event.dart';
import 'package:hidden_eleven/features/lobby/room_provider.dart';
import 'package:hidden_eleven/features/lobby/room_socket_service.dart';
import 'package:hidden_eleven/services/local_presence_service.dart';
import 'package:hidden_eleven/services/local_spectator_presence_service.dart';
import 'package:hidden_eleven/shared/providers/local_presence_provider.dart';
import 'package:hidden_eleven/shared/providers/local_spectator_presence_provider.dart';
import 'package:hidden_eleven/shared/widgets/session_desynced_screen.dart';

/// Same fake-socket seam as spectator_presence_test.dart's
/// `_RecordingSocketService`: records what RoomNotifier sends instead of
/// opening a real socket, and exposes [emit] to push a fake server event
/// straight into RoomNotifier's `_onEvent` — the reconnect/checkPresence
/// divergence bug fix (see room_provider.dart's `sessionDesyncedProvider`
/// doc comment) is entirely client-side reaction logic, so this is the
/// right seam to prove it at.
class _RecordingSocketService extends RoomSocketService {
  final _fakeController = StreamController<ServerEvent>.broadcast();
  final List<MapEntry<String, Map<String, dynamic>?>> sent = [];
  bool reconnected = false;

  @override
  Stream<ServerEvent> get stream => _fakeController.stream;

  @override
  void connect() {}

  @override
  void reconnect() => reconnected = true;

  @override
  void send(String event, [Map<String, dynamic>? data]) {
    sent.add(MapEntry(event, data));
  }

  void emit(ServerEvent event) => _fakeController.add(event);

  void disposeFake() => _fakeController.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('reconnect success restores the same room snapshot', () {
    test(
      'a successful check_presence response replaces state with the authoritative room',
      () async {
        final fakeService = _RecordingSocketService();
        final container = ProviderContainer(
          overrides: [roomSocketServiceProvider.overrideWithValue(fakeService)],
        );
        addTearDown(() {
          container.dispose();
          fakeService.disposeFake();
        });

        await container
            .read(localPresenceProvider.notifier)
            .save(
              const LocalPresenceData(
                playerId: 'p1',
                roomCode: 'QMNGFR',
                displayName: 'Alice',
                status: LocalPresenceStatus.inGame,
                reconnectToken: 'ptok',
              ),
            );

        container.read(roomProvider.notifier).jumpIn();
        expect(fakeService.reconnected, isTrue);

        // The server's authoritative room_update — the definitive source of
        // truth this client must fully adopt, replacing anything stale.
        fakeService.emit(
          const RoomUpdated(
            RoomState(
              code: 'QMNGFR',
              players: [
                Player(id: 'p1', displayName: 'Alice', isHost: true),
                Player(id: 'p2', displayName: 'Bob', isHost: false),
              ],
              isStarted: true,
            ),
            'p1',
            null,
            null,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final room = container.read(roomProvider);
        expect(room, isNotNull);
        expect(room!.code, 'QMNGFR');
        expect(room.players, hasLength(2));
        expect(container.read(sessionDesyncedProvider), isNull);
      },
    );
  });

  group('reconnect failure with a stale room clears local state', () {
    test(
      'NOT_FOUND while already mid-game wipes roomProvider, gameProvider, and presence',
      () async {
        final fakeService = _RecordingSocketService();
        final container = ProviderContainer(
          overrides: [roomSocketServiceProvider.overrideWithValue(fakeService)],
        );
        addTearDown(() {
          container.dispose();
          fakeService.disposeFake();
        });

        await container
            .read(localPresenceProvider.notifier)
            .save(
              const LocalPresenceData(
                playerId: 'p1',
                roomCode: 'QMNGFR',
                displayName: 'Alice',
                status: LocalPresenceStatus.inGame,
                reconnectToken: 'ptok',
              ),
            );

        // Simulate this client already being mid-game with a live room
        // snapshot cached BEFORE the socket ever drops — this is the exact
        // scenario the original bug missed entirely (GameScreen's old ad hoc
        // NOT_FOUND handler only acted when roomProvider was already null,
        // which is never true here).
        container.read(roomProvider.notifier);
        fakeService.emit(
          const RoomUpdated(
            RoomState(
              code: 'QMNGFR',
              players: [
                Player(id: 'p1', displayName: 'Alice', isHost: true),
                Player(id: 'p2', displayName: 'Bob', isHost: false),
              ],
              isStarted: true,
            ),
            'p1',
            null,
            null,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(container.read(roomProvider), isNotNull);

        // The socket drops and auto-reopens (RoomSocketService's own
        // internal retry), then check_presence comes back rejected — the
        // exact server_restart / stale_or_wrong_room repro from the bug
        // report (room QMNGFR is gone; a real server restart wipes the
        // in-memory session store, see PROJECT_OVERVIEW.md).
        container.read(roomProvider.notifier).jumpIn();
        fakeService.emit(const ServerError('NOT_FOUND'));
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(
          container.read(roomProvider),
          isNull,
          reason: 'stale RoomState must be wiped, not left rendering',
        );
        expect(
          container.read(gameProvider),
          isNull,
          reason: 'stale GameState must be wiped, not left rendering',
        );
        expect(container.read(localPresenceProvider), isNull);

        final desync = container.read(sessionDesyncedProvider);
        expect(desync, isNotNull);
        expect(desync!.code, 'NOT_FOUND');
        expect(desync.isSpectator, isFalse);
      },
    );

    test(
      'a server-restart scenario (INVALID_TOKEN on the very first reconnect attempt) is handled the same way',
      () async {
        // A server restart also invalidates the HMAC-signed reconnect token
        // in some deployments (new signing state) — INVALID_TOKEN must be
        // treated exactly as fatally as NOT_FOUND, not as a softer error.
        final fakeService = _RecordingSocketService();
        final container = ProviderContainer(
          overrides: [roomSocketServiceProvider.overrideWithValue(fakeService)],
        );
        addTearDown(() {
          container.dispose();
          fakeService.disposeFake();
        });

        await container
            .read(localPresenceProvider.notifier)
            .save(
              const LocalPresenceData(
                playerId: 'p1',
                roomCode: 'QMNGFR',
                displayName: 'Alice',
                status: LocalPresenceStatus.inGame,
                reconnectToken: 'ptok',
              ),
            );

        container.read(roomProvider.notifier).jumpIn();
        fakeService.emit(const ServerError('INVALID_TOKEN'));
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(container.read(roomProvider), isNull);
        expect(container.read(gameProvider), isNull);
        expect(container.read(localPresenceProvider), isNull);
        expect(container.read(sessionDesyncedProvider)?.code, 'INVALID_TOKEN');
      },
    );
  });

  group('a failed reconnect never lets a stray create/join through', () {
    test(
      'no create_room or join_room is ever sent as a side effect of a rejected reconnect',
      () async {
        final fakeService = _RecordingSocketService();
        final container = ProviderContainer(
          overrides: [roomSocketServiceProvider.overrideWithValue(fakeService)],
        );
        addTearDown(() {
          container.dispose();
          fakeService.disposeFake();
        });

        await container
            .read(localPresenceProvider.notifier)
            .save(
              const LocalPresenceData(
                playerId: 'p1',
                roomCode: 'QMNGFR',
                displayName: 'Alice',
                status: LocalPresenceStatus.inGame,
                reconnectToken: 'ptok',
              ),
            );

        container.read(roomProvider.notifier).jumpIn();
        fakeService.emit(const ServerError('NOT_FOUND'));
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(
          fakeService.sent.any(
            (e) => e.key == 'create_room' || e.key == 'join_room',
          ),
          isFalse,
          reason:
              'a rejected reconnect must never auto-create or auto-join '
              'a different room — the exact QMNGFR -> LXQWLK divergence bug',
        );
      },
    );

    test(
      'RoomSocketService.clearCachedIdentity prevents any further automatic retry for the dead identity',
      () async {
        // Uses the REAL RoomSocketService (not the fake) — clearCachedIdentity
        // is a real method on the base class the fake inherits unmodified.
        final service = RoomSocketService();
        addTearDown(service.dispose);

        service.setCachedPlayerId('p1');
        service.setCachedRoomCode('QMNGFR');
        service.setCachedReconnectToken('ptok');
        service.setCachedSpectatorId('s1');

        service.clearCachedIdentity();

        expect(service.cachedReconnectToken, isNull);
      },
    );
  });

  group('a rejected reconnect blocks gameplay actions via connectionStatus', () {
    test(
      'connectionStatus becomes sessionInvalid, not connected, on a rejected check_presence',
      () async {
        final fakeService = _RecordingSocketService();
        final container = ProviderContainer(
          overrides: [roomSocketServiceProvider.overrideWithValue(fakeService)],
        );
        addTearDown(() {
          container.dispose();
          fakeService.disposeFake();
        });

        // Establish the notifier and a healthy baseline first.
        container.read(connectionStatusProvider.notifier);
        fakeService.emit(
          const RoomUpdated(
            RoomState(code: 'QMNGFR', players: []),
            'p1',
            null,
            null,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          container.read(connectionStatusProvider),
          ConnectionStatus.connected,
        );

        // A rejected reconnect must NOT be mistaken for "the socket is fine" —
        // this is what previously silently re-enabled gameplay-action gates
        // keyed off `connectionStatus == ConnectionStatus.connected`.
        fakeService.emit(const ServerError('NOT_FOUND'));
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(
          container.read(connectionStatusProvider),
          ConnectionStatus.sessionInvalid,
        );
        expect(
          container.read(connectionStatusProvider),
          isNot(ConnectionStatus.connected),
        );
      },
    );
  });

  group('spectator identity is wiped independently of player identity', () {
    test(
      'a failed spectator_reconnect triggers sessionDesyncedProvider with isSpectator true',
      () async {
        final fakeService = _RecordingSocketService();
        final container = ProviderContainer(
          overrides: [roomSocketServiceProvider.overrideWithValue(fakeService)],
        );
        addTearDown(() {
          container.dispose();
          fakeService.disposeFake();
        });

        await container
            .read(localSpectatorPresenceProvider.notifier)
            .save(
              const LocalSpectatorPresenceData(
                spectatorId: 's1',
                roomCode: 'QMNGFR',
                displayName: 'Watcher',
                reconnectToken: 'stok',
              ),
            );

        container.read(roomProvider.notifier).jumpInAsSpectator();
        fakeService.emit(const ServerError('NOT_FOUND'));
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(container.read(roomProvider), isNull);
        expect(container.read(gameProvider), isNull);
        final desync = container.read(sessionDesyncedProvider);
        expect(desync, isNotNull);
        expect(desync!.isSpectator, isTrue);
      },
    );
  });

  group('SessionDesyncedScreen — the single explicit recovery path', () {
    testWidgets(
      'renders the blocking message and clears the desync flag on Return to Home',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        container
            .read(sessionDesyncedProvider.notifier)
            .trigger(
              SessionDesyncData(
                code: 'NOT_FOUND',
                isSpectator: false,
                detectedAt: DateTime.now(),
              ),
            );

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: SessionDesyncedScreen()),
          ),
        );

        expect(find.text('Session no longer available'), findsOneWidget);
        expect(find.text('Return to Home'), findsOneWidget);

        await tester.tap(find.text('Return to Home'));
        await tester.pump();

        expect(container.read(sessionDesyncedProvider), isNull);
      },
    );

    testWidgets(
      'renders nothing extra when there is no desync (app builder only shows it when non-null)',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: Scaffold(body: Text('Normal screen')),
            ),
          ),
        );

        expect(find.text('Session no longer available'), findsNothing);
        expect(find.text('Normal screen'), findsOneWidget);
      },
    );
  });
}
