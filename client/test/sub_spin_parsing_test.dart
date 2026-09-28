import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/lobby/models/server_event.dart';

/// Regression coverage for the subs-phase crash: a `sub_spin_result` payload
/// used to be parsed via a single `.map().toList()` where every player card
/// went through unsafe `as int?` casts on numeric fields (rating/pace/
/// shooting/etc). One malformed field on ONE player threw for the entire
/// batch — the reported symptom was "pick one sub, the rest disappear",
/// because the event never finished parsing at all, so SubsPanel never
/// received a usable result.
///
/// The fix: numeric fields go through a safe num→int coercion, and each
/// player is parsed in its own try/catch so a bad record becomes a visible
/// placeholder card instead of discarding the whole response.
void main() {
  Map<String, dynamic> subSpinEvent(List<Map<String, dynamic>> players) => {
    'event': 'sub_spin_result',
    'data': {
      'positionGroup': 'att',
      'clubName': 'Crystal Palace',
      'players': players,
    },
  };

  Map<String, dynamic> wellFormedPlayer({String id = 'p1'}) => {
    'id': id,
    'name': 'Test Player',
    'position': 'ST',
    'rating': 82,
    'pace': 80,
    'shooting': 78,
    'passing': 70,
    'dribbling': 75,
    'defending': 40,
    'physical': 77,
  };

  test('parses a normal batch of players with int-typed numeric fields', () {
    final event = parseServerEvent(
      subSpinEvent([wellFormedPlayer(id: 'p1'), wellFormedPlayer(id: 'p2')]),
      'local-player-id',
    );

    expect(event, isA<SubSpinResult>());
    final result = event as SubSpinResult;
    expect(result.clubName, 'Crystal Palace');
    expect(result.players, hasLength(2));
    expect(result.players[0].rating, 82);
    expect(result.players[0].cardId, 'p1');
  });

  test(
    'a rating arriving as a double (e.g. 85.0) no longer throws — coerces to int',
    () {
      final malformed = wellFormedPlayer(id: 'p1');
      malformed['rating'] = 85.0; // jsonDecode gives a double for this shape

      final event = parseServerEvent(
        subSpinEvent([malformed]),
        'local-player-id',
      );

      expect(event, isA<SubSpinResult>());
      final result = event as SubSpinResult;
      expect(result.players, hasLength(1));
      expect(result.players[0].rating, 85);
    },
  );

  test('one malformed player does not discard the rest of the batch — '
      'this is the exact "pick one sub, the rest vanish" bug', () {
    final good1 = wellFormedPlayer(id: 'p1');
    final bad = wellFormedPlayer(id: 'p2');
    bad['position'] = 12345; // wrong type — basePositionType expects a String
    final good2 = wellFormedPlayer(id: 'p3');

    final event = parseServerEvent(
      subSpinEvent([good1, bad, good2]),
      'local-player-id',
    );

    expect(event, isA<SubSpinResult>());
    final result = event as SubSpinResult;
    // All 3 slots are present — the malformed one became a placeholder
    // instead of the whole list disappearing.
    expect(result.players, hasLength(3));
    expect(result.players[0].cardId, 'p1');
    expect(result.players[2].cardId, 'p3');
    // The malformed entry is clearly marked, not silently blank/zeroed data
    // that looks like a real, pickable player.
    expect(result.players[1].playerName, 'Unavailable player');
  });

  test('an empty players list still parses to a valid (empty) result', () {
    final event = parseServerEvent(subSpinEvent(const []), 'local-player-id');

    expect(event, isA<SubSpinResult>());
    expect((event as SubSpinResult).players, isEmpty);
  });
}
