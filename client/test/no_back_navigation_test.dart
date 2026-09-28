import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Navigation contract for the screens that hold live server-backed state.
///
/// "Back" out of a game, tournament or result has no meaning: the server keeps
/// the player enrolled either way, so popping the route only desyncs the
/// client from an event it is still part of. Those screens therefore expose no
/// back affordance at all — leaving is an explicit, confirmed, server-
/// acknowledged action instead.
///
/// This test reads the sources rather than pumping each screen, because the
/// thing being protected is the *absence* of an affordance: several of these
/// screens need a fully wired socket/router to build, and the regression this
/// guards against is someone re-introducing a back arrow (or deleting an
/// `automaticallyImplyLeading: false`) — which is visible statically and would
/// otherwise pass unnoticed.
void main() {
  String read(String path) => File('lib/$path').readAsStringSync();

  group('live-state screens expose no back navigation', () {
    const liveScreens = <String, String>{
      'tournament hub': 'features/tournament/screens/tournament_hub_screen.dart',
      'result': 'features/result/result_screen.dart',
      'lobby': 'features/lobby/lobby_screen.dart',
    };

    for (final entry in liveScreens.entries) {
      test('${entry.key} disables the implicit back arrow', () {
        final src = read(entry.value);
        expect(
          src.contains('automaticallyImplyLeading: false'),
          isTrue,
          reason:
              '${entry.key} must not inherit AppBar\'s automatic back button — '
              'backing out of live server state desyncs the client',
        );
      });

      test('${entry.key} never calls context.pop() to exit', () {
        final src = read(entry.value);
        expect(
          src.contains('context.pop()'),
          isFalse,
          reason:
              '${entry.key} must leave via an explicit server-acknowledged '
              'action, not by popping the route',
        );
      });
    }

    test('the tournament hub offers an explicit leave action instead', () {
      final src = read('features/tournament/screens/tournament_hub_screen.dart');
      // Removing back is only safe because a deliberate way out exists.
      expect(src.contains('_confirmLeaveTournament'), isTrue);
      expect(src.contains('exitGameToHome'), isTrue);
      expect(
        src.contains('Leave tournament?'),
        isTrue,
        reason: 'leaving a tournament must be confirmed, not one stray tap',
      );
    });

    test('the game screen leaves via exitGameToHome, not a route pop', () {
      final src = read('features/game/game_screen.dart');
      expect(src.contains('exitGameToHome'), isTrue);
    });
  });

  group('pre-commitment screens deliberately keep back', () {
    // Host and Join are reached *before* joining any server-side session, so
    // back is both safe and necessary there — removing it would strand a
    // player on a setup screen with no way out. Host additionally guards the
    // exit with a discard confirmation.
    test('join room keeps a back affordance', () {
      final src = read('features/join/join_room_screen.dart');
      expect(src.contains('arrow_back_ios_new_rounded'), isTrue);
    });

    test('host room keeps a back affordance', () {
      final src = read('features/host/host_room_screen.dart');
      expect(src.contains('arrow_back_ios_new_rounded'), isTrue);
    });
  });
}
