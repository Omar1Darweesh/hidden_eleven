import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/lobby/models/server_event.dart';

/// Pitch-slot numerics in game_state used to cast with `as int?`, which throws
/// when JSON delivers a double (e.g. 85.0). Sub-spin parsing was fixed earlier;
/// this guards the same class of bug on pitch cards.
void main() {
  Map<String, dynamic> gameStateWithPitchRating(dynamic rating) => {
    'localPlayerId': 'p1',
    'players': [
      {'id': 'p1', 'displayName': 'Alice', 'isHost': true, 'isConnected': true},
    ],
    'status': 'drafting',
    'pitches': {
      'p1': {
        'filledCount': 1,
        'slots': [
          {
            'index': 0,
            'label': 'ST',
            'basePositionType': 'att',
            'card': {
              'cardId': 'c1',
              'playerName': 'Test',
              'rating': rating,
              'pace': 80.0,
              'shooting': 78,
              'passing': 70,
              'dribbling': 75,
              'defending': 40,
              'physical': 77,
            },
          },
        ],
      },
    },
  };

  test(
    'game_state pitch card rating as double coerces to int without throwing',
    () {
      final event = parseServerEvent({
        'event': 'game_state',
        'data': gameStateWithPitchRating(85.0),
      }, 'p1');
      expect(event, isA<GameStateReceived>());
      final state = (event as GameStateReceived).state;
      expect(state.pitches['p1']!.slots.first.cardRating, 85);
      expect(state.pitches['p1']!.slots.first.cardPace, 80);
    },
  );
}
