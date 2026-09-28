import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hidden_eleven/features/game/game_provider.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/lobby/models/server_event.dart';
import 'package:hidden_eleven/features/lobby/room_provider.dart';
import 'package:hidden_eleven/features/lobby/room_socket_service.dart';

/// Reproduces the "opening the ended game" bug: gameProvider used to keep a
/// finished GameState across sessions, so the next host/join built a game
/// route that immediately navigated to the old result. Every exit path — and
/// starting a fresh host/join — must now leave gameProvider null.
class _FakeSocket extends RoomSocketService {
  final _controller = StreamController<ServerEvent>.broadcast();
  @override
  Stream<ServerEvent> get stream => _controller.stream;
  @override
  void connect() {}
  @override
  void reconnect() {}
  @override
  void send(String event, [Map<String, dynamic>? data]) {}
  void emit(ServerEvent e) => _controller.add(e);
  void closeFake() => _controller.close();
}

GameState _finishedGame() => const GameState(
  sessionId: 's1',
  roomCode: 'ROOM1',
  formationName: '4-3-3',
  players: [GamePlayer(id: 'p1', displayName: 'You', isHost: true)],
  pitches: {},
  baseTurnOrder: ['p1'],
  currentRound: 11,
  totalRounds: 11,
  currentTurnOrder: ['p1'],
  currentTurnIndex: 0,
  currentRoundSlotIndex: null,
  turn: GameTurn(
    turnId: 't1',
    phase: 'selecting_position',
    activePlayerId: 'p1',
  ),
  status: 'finished',
  isFinished: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(ProviderContainer, _FakeSocket)> seedFinishedGame() async {
    final socket = _FakeSocket();
    final container = ProviderContainer(
      overrides: [roomSocketServiceProvider.overrideWithValue(socket)],
    );
    // Force gameProvider to build & subscribe, then push a finished game.
    container.read(gameProvider);
    socket.emit(GameStateReceived(_finishedGame(), 'p1'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      container.read(gameProvider)?.isFinished,
      isTrue,
      reason: 'precondition: a finished game is in gameProvider',
    );
    return (container, socket);
  }

  void tearDownContainer(ProviderContainer c, _FakeSocket s) {
    c.dispose();
    s.closeFake();
  }

  test('createRoom wipes a leftover finished game', () async {
    final (c, s) = await seedFinishedGame();
    addTearDown(() => tearDownContainer(c, s));
    c.read(roomProvider.notifier).createRoom('You');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c.read(gameProvider), isNull);
  });

  test('joinRoom wipes a leftover finished game', () async {
    final (c, s) = await seedFinishedGame();
    addTearDown(() => tearDownContainer(c, s));
    c.read(roomProvider.notifier).joinRoom('ABCDEF', 'You');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c.read(gameProvider), isNull);
  });

  test('clearAfterGameEnd resets gameProvider', () async {
    final (c, s) = await seedFinishedGame();
    addTearDown(() => tearDownContainer(c, s));
    c.read(roomProvider.notifier).clearAfterGameEnd();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c.read(gameProvider), isNull);
  });

  test('clearAfterKick resets gameProvider', () async {
    final (c, s) = await seedFinishedGame();
    addTearDown(() => tearDownContainer(c, s));
    c.read(roomProvider.notifier).clearAfterKick();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c.read(gameProvider), isNull);
  });

  test('leaveGamePermanently resets gameProvider', () async {
    final (c, s) = await seedFinishedGame();
    addTearDown(() => tearDownContainer(c, s));
    c.read(roomProvider.notifier).leaveGamePermanently();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c.read(gameProvider), isNull);
  });
}
