import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hidden_eleven/features/lobby/models/room_state.dart';
import 'package:hidden_eleven/features/lobby/models/server_event.dart';
import 'package:hidden_eleven/features/lobby/room_provider.dart';
import 'package:hidden_eleven/features/lobby/room_socket_service.dart';
import 'package:hidden_eleven/services/local_presence_service.dart';
import 'package:hidden_eleven/services/local_spectator_presence_service.dart';
import 'package:hidden_eleven/shared/providers/local_presence_provider.dart';
import 'package:hidden_eleven/shared/providers/local_spectator_presence_provider.dart';

/// Records what RoomNotifier sends instead of opening a real WebSocket, and
/// exposes [emit] so a test can push a fake server event straight into
/// RoomNotifier's `_onEvent` — the same seam RoomSocketService's real
/// `_onData` would otherwise feed it from an actual socket. This is what
/// lets jumpInAsSpectator()'s send path and the NOT_FOUND/INVALID_TOKEN
/// precedence branches be exercised without a live server, following the
/// existing convention in this codebase of testing extracted logic directly
/// rather than driving a real socket.
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

  group('Spectator presence persistence', () {
    test(
      'save/restore round trip through LocalSpectatorPresenceService',
      () async {
        final service = LocalSpectatorPresenceService();
        expect(await service.load(), isNull);

        await service.save(
          const LocalSpectatorPresenceData(
            spectatorId: 's1',
            roomCode: 'ABCDEF',
            displayName: 'Watcher',
            reconnectToken: 'tok',
          ),
        );

        final loaded = await service.load();
        expect(loaded, isNotNull);
        expect(loaded!.spectatorId, 's1');
        expect(loaded.roomCode, 'ABCDEF');
        expect(loaded.displayName, 'Watcher');
        expect(loaded.reconnectToken, 'tok');
      },
    );

    test('clear removes all persisted spectator keys', () async {
      final service = LocalSpectatorPresenceService();
      await service.save(
        const LocalSpectatorPresenceData(
          spectatorId: 's1',
          roomCode: 'ABCDEF',
          displayName: 'Watcher',
        ),
      );

      await service.clear();

      expect(await service.load(), isNull);
    });

    test(
      'LocalSpectatorPresenceNotifier.ready resolves, save/clear update provider state',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await container.read(localSpectatorPresenceProvider.notifier).ready;
        expect(container.read(localSpectatorPresenceProvider), isNull);

        await container
            .read(localSpectatorPresenceProvider.notifier)
            .save(
              const LocalSpectatorPresenceData(
                spectatorId: 's1',
                roomCode: 'RM1',
                displayName: 'W',
                reconnectToken: 'tok',
              ),
            );
        expect(
          container.read(localSpectatorPresenceProvider)?.spectatorId,
          's1',
        );

        await container.read(localSpectatorPresenceProvider.notifier).clear();
        expect(container.read(localSpectatorPresenceProvider), isNull);
      },
    );
  });

  group(
    'saveSpectatorPresence never clobbers a good persisted token with a null cache',
    () {
      test(
        'a game_state after a cold-start spectator_reconnect keeps the previously-saved token',
        () async {
          // Reproduces the exact sequence a second app refresh hits: (1) an
          // earlier session already persisted a good reconnectToken from the
          // original spectate_room ack; (2) this session is a fresh cold start,
          // so RoomSocketService's in-memory cachedReconnectToken starts null;
          // (3) spectator_reconnect succeeds (its own ack carries no token to
          // re-cache — see rooms.gateway.ts's handleSpectatorReconnect); (4) the
          // game_state that follows must not overwrite the still-good token
          // with the still-null cache.
          final fakeService = _RecordingSocketService();
          final container = ProviderContainer(
            overrides: [
              roomSocketServiceProvider.overrideWithValue(fakeService),
            ],
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
                  roomCode: 'RM1',
                  displayName: 'Watcher',
                  reconnectToken: 'good-token-from-original-spectate',
                ),
              );

          // The spectator_reconnect ack: a RoomUpdated with localSpectatorId set
          // but no reconnectToken (matches the real server response shape).
          container.read(
            roomProvider.notifier,
          ); // ensure build()/subscription exists
          fakeService.emit(
            const RoomUpdated(
              RoomState(code: 'RM1', players: []),
              null,
              's1',
              null,
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 20));

          // The game_state that follows triggers the actual save.
          container
              .read(roomProvider.notifier)
              .saveSpectatorPresence('Watcher');
          await Future<void>.delayed(const Duration(milliseconds: 20));

          final saved = container.read(localSpectatorPresenceProvider);
          expect(saved, isNotNull);
          expect(saved!.reconnectToken, 'good-token-from-original-spectate');
        },
      );
    },
  );

  group('jumpInAsSpectator — spectator_reconnect wiring', () {
    late _RecordingSocketService fakeService;
    late ProviderContainer container;

    setUp(() {
      fakeService = _RecordingSocketService();
      container = ProviderContainer(
        overrides: [roomSocketServiceProvider.overrideWithValue(fakeService)],
      );
      addTearDown(() {
        container.dispose();
        fakeService.disposeFake();
      });
    });

    test('does nothing when there is no saved spectator presence', () async {
      await container.read(localSpectatorPresenceProvider.notifier).ready;

      container.read(roomProvider.notifier).jumpInAsSpectator();

      expect(fakeService.sent, isEmpty);
      expect(fakeService.reconnected, isFalse);
    });

    test(
      'does nothing when the saved presence has no reconnect token',
      () async {
        await container
            .read(localSpectatorPresenceProvider.notifier)
            .save(
              const LocalSpectatorPresenceData(
                spectatorId: 's1',
                roomCode: 'RM1',
                displayName: 'W',
              ),
            );

        container.read(roomProvider.notifier).jumpInAsSpectator();

        expect(fakeService.sent, isEmpty);
        expect(fakeService.reconnected, isFalse);
      },
    );

    test(
      'sends spectator_reconnect with the saved identity once a token exists',
      () async {
        await container
            .read(localSpectatorPresenceProvider.notifier)
            .save(
              const LocalSpectatorPresenceData(
                spectatorId: 's1',
                roomCode: 'RM1',
                displayName: 'W',
                reconnectToken: 'tok123',
              ),
            );

        container.read(roomProvider.notifier).jumpInAsSpectator();

        expect(fakeService.reconnected, isTrue);
        expect(fakeService.sent, hasLength(1));
        expect(fakeService.sent.single.key, 'spectator_reconnect');
        expect(fakeService.sent.single.value, {
          'roomCode': 'RM1',
          'spectatorId': 's1',
          'reconnectToken': 'tok123',
        });
      },
    );
  });

  group('stopSpectating clears persisted spectator presence', () {
    test(
      'stopSpectating sends stop_spectating and clears the persisted seat',
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
                roomCode: 'RM1',
                displayName: 'W',
                reconnectToken: 'tok',
              ),
            );
        expect(container.read(localSpectatorPresenceProvider), isNotNull);

        container.read(roomProvider.notifier).stopSpectating();
        // clear() is fire-and-forget from stopSpectating's perspective (an
        // async SharedPreferences write) — give it a moment to settle before
        // asserting on the resulting provider state.
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(fakeService.sent.any((e) => e.key == 'stop_spectating'), isTrue);
        expect(container.read(localSpectatorPresenceProvider), isNull);
      },
    );
  });

  group(
    'Precedence — stale spectator state never overrides a real player identity',
    () {
      test(
        'a real player presence is untouched by an unrelated saved spectator presence',
        () async {
          final container = ProviderContainer();
          addTearDown(container.dispose);

          await container
              .read(localPresenceProvider.notifier)
              .save(
                const LocalPresenceData(
                  playerId: 'p1',
                  roomCode: 'RM1',
                  displayName: 'Alice',
                  status: LocalPresenceStatus.inGame,
                  reconnectToken: 'ptok',
                ),
              );
          await container
              .read(localSpectatorPresenceProvider.notifier)
              .save(
                const LocalSpectatorPresenceData(
                  spectatorId: 's1',
                  roomCode: 'RM1',
                  displayName: 'Bob',
                  reconnectToken: 'stok',
                ),
              );

          // Mirrors home_screen.dart's own display precedence:
          // `hasActiveGame ? null : spectatorPresence`.
          final hasActiveGame = container.read(localPresenceProvider) != null;
          final displayedSpectatorPresence = hasActiveGame
              ? null
              : container.read(localSpectatorPresenceProvider);

          expect(hasActiveGame, isTrue);
          expect(displayedSpectatorPresence, isNull);
          expect(container.read(localPresenceProvider)?.playerId, 'p1');
        },
      );

      test(
        'a failed spectator_reconnect (NOT_FOUND) clears only spectator presence, never player presence',
        () async {
          final fakeService = _RecordingSocketService();
          final container = ProviderContainer(
            overrides: [
              roomSocketServiceProvider.overrideWithValue(fakeService),
            ],
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
                  roomCode: 'RM1',
                  displayName: 'Alice',
                  status: LocalPresenceStatus.inGame,
                  reconnectToken: 'ptok',
                ),
              );
          await container
              .read(localSpectatorPresenceProvider.notifier)
              .save(
                const LocalSpectatorPresenceData(
                  spectatorId: 's1',
                  roomCode: 'RM1',
                  displayName: 'Bob',
                  reconnectToken: 'stok',
                ),
              );

          container.read(roomProvider.notifier).jumpInAsSpectator();
          fakeService.emit(const ServerError('NOT_FOUND'));
          // Let the stream's microtask deliver the event to RoomNotifier.
          await Future<void>.delayed(const Duration(milliseconds: 20));

          expect(container.read(localSpectatorPresenceProvider), isNull);
          expect(container.read(localPresenceProvider)?.playerId, 'p1');
        },
      );

      test(
        'a failed check_presence (NOT_FOUND) with no spectator attempt pending clears only player presence',
        () async {
          final fakeService = _RecordingSocketService();
          final container = ProviderContainer(
            overrides: [
              roomSocketServiceProvider.overrideWithValue(fakeService),
            ],
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
                  roomCode: 'RM1',
                  displayName: 'Alice',
                  status: LocalPresenceStatus.inGame,
                  reconnectToken: 'ptok',
                ),
              );
          await container
              .read(localSpectatorPresenceProvider.notifier)
              .save(
                const LocalSpectatorPresenceData(
                  spectatorId: 's1',
                  roomCode: 'RM1',
                  displayName: 'Bob',
                  reconnectToken: 'stok',
                ),
              );

          // Force RoomNotifier's build() (and its stream subscription) to exist
          // without going through jumpIn/jumpInAsSpectator — this NOT_FOUND
          // belongs to an ordinary (player) check_presence attempt instead.
          container.read(roomProvider.notifier);
          fakeService.emit(const ServerError('NOT_FOUND'));
          await Future<void>.delayed(const Duration(milliseconds: 20));

          expect(container.read(localPresenceProvider), isNull);
          expect(container.read(localSpectatorPresenceProvider), isNotNull);
        },
      );
    },
  );

  group('Existing player reconnect flow still passes', () {
    test(
      'jumpIn sends check_presence with the saved player identity',
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
                roomCode: 'RM1',
                displayName: 'Alice',
                status: LocalPresenceStatus.inGame,
                reconnectToken: 'ptok',
              ),
            );

        container.read(roomProvider.notifier).jumpIn();

        expect(fakeService.reconnected, isTrue);
        expect(fakeService.sent, hasLength(1));
        expect(fakeService.sent.single.key, 'check_presence');
        expect(fakeService.sent.single.value, {
          'playerId': 'p1',
          'roomCode': 'RM1',
          'reconnectToken': 'ptok',
        });
      },
    );

    test('jumpIn is a no-op with no saved player presence', () async {
      final fakeService = _RecordingSocketService();
      final container = ProviderContainer(
        overrides: [roomSocketServiceProvider.overrideWithValue(fakeService)],
      );
      addTearDown(() {
        container.dispose();
        fakeService.disposeFake();
      });

      container.read(roomProvider.notifier).jumpIn();

      expect(fakeService.sent, isEmpty);
      expect(fakeService.reconnected, isFalse);
    });
  });
}
