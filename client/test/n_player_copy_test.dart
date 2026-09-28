import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/game/game_screen.dart';
import 'package:hidden_eleven/features/subs/subs_panel.dart';

/// Coverage for the small N>2 client copy/aggregation fixes from
/// FLUTTER_CLIENT_AUDIT.md's remaining items:
///
/// 1. Subs panel opponent-status wording (`opponentStatusLabel`) — the
///    underlying "did everyone else confirm" aggregation in subs_panel.dart
///    (`.every(...)` over all non-local entries) was already N>2-correct;
///    only the copy said "opponent" (singular) regardless of how many other
///    players were actually in the room.
///
/// 2. The turn_auto_picked snackbar (`turnAutoPickedMessage`) — previously
///    always said the generic "Opponent timed out.", which is ambiguous the
///    moment there's more than one other player in the room.
void main() {
  group('opponentStatusLabel — 2-player wording stays natural', () {
    test('not yet all picked, 1 opponent', () {
      expect(
        opponentStatusLabel(
          localConfirmed: false,
          opponentConfirmed: false,
          opponentCount: 1,
        ),
        'Waiting for opponent to finish…',
      );
    });

    test('locally confirmed, opponent still confirming, 1 opponent', () {
      expect(
        opponentStatusLabel(
          localConfirmed: true,
          opponentConfirmed: false,
          opponentCount: 1,
        ),
        'Waiting for opponent to submit…',
      );
    });

    test('both confirmed, 1 opponent', () {
      expect(
        opponentStatusLabel(
          localConfirmed: true,
          opponentConfirmed: true,
          opponentCount: 1,
        ),
        'Opponent submitted lineup ✓',
      );
    });
  });

  group('opponentStatusLabel — N>2 wording is correct', () {
    test('not yet all picked, 3 opponents', () {
      expect(
        opponentStatusLabel(
          localConfirmed: false,
          opponentConfirmed: false,
          opponentCount: 3,
        ),
        'Waiting for opponents to finish…',
      );
    });

    test('locally confirmed, others still confirming, 2 opponents', () {
      expect(
        opponentStatusLabel(
          localConfirmed: true,
          opponentConfirmed: false,
          opponentCount: 2,
        ),
        'Waiting for opponents to submit…',
      );
    });

    test('all confirmed, 2 opponents', () {
      expect(
        opponentStatusLabel(
          localConfirmed: true,
          opponentConfirmed: true,
          opponentCount: 2,
        ),
        'All opponents submitted lineup ✓',
      );
    });

    test(
      'opponentCount of 0 (should not happen mid-game, but must not read as singular)',
      () {
        expect(
          opponentStatusLabel(
            localConfirmed: true,
            opponentConfirmed: true,
            opponentCount: 0,
          ),
          'All opponents submitted lineup ✓',
        );
      },
    );
  });

  group('turnAutoPickedMessage — timeout snackbar naming', () {
    test(
      'local player timing out always gets the same first-person copy, regardless of name',
      () {
        expect(
          turnAutoPickedMessage(isLocal: true, timedOutPlayerName: 'Alice'),
          "Time's up! A card was picked for you.",
        );
        expect(
          turnAutoPickedMessage(isLocal: true, timedOutPlayerName: null),
          "Time's up! A card was picked for you.",
        );
      },
    );

    test('shows the specific player name when resolvable', () {
      expect(
        turnAutoPickedMessage(isLocal: false, timedOutPlayerName: 'Bob'),
        'Bob timed out.',
      );
    });

    test(
      'falls back to generic copy when the name cannot be resolved (null)',
      () {
        expect(
          turnAutoPickedMessage(isLocal: false, timedOutPlayerName: null),
          'Opponent timed out.',
        );
      },
    );

    test('falls back to generic copy when the resolved name is empty', () {
      expect(
        turnAutoPickedMessage(isLocal: false, timedOutPlayerName: ''),
        'Opponent timed out.',
      );
    });
  });
}
