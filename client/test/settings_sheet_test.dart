import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hidden_eleven/app/routes.dart';
import 'package:hidden_eleven/features/lobby/models/server_event.dart';
import 'package:hidden_eleven/features/lobby/room_socket_service.dart';
import 'package:hidden_eleven/shared/audio/audio_service.dart';
import 'package:hidden_eleven/shared/providers/app_preferences_provider.dart';
import 'package:hidden_eleven/shared/widgets/settings_sheet.dart';

/// Same minimal fake-socket seam `session_desync_test.dart` already uses:
/// records what's sent instead of opening a real socket, so
/// `roomProvider`/`gameProvider` can be exercised (here, just enough for
/// "Leave Room" to have somewhere to route to) without any network I/O.
class _RecordingSocketService extends RoomSocketService {
  final _fakeController = StreamController<ServerEvent>.broadcast();
  final List<String> sentEvents = [];

  @override
  Stream<ServerEvent> get stream => _fakeController.stream;

  @override
  void connect() {}

  @override
  void reconnect() {}

  @override
  void send(String event, [Map<String, dynamic>? data]) {
    sentEvents.add(event);
  }
}

/// Builds a minimal app shell — real GoRouter (so `context.pushNamed` /
/// `context.goNamed` used inside the sheet actually resolve) with a single
/// button that opens the settings sheet, matching how it's really invoked
/// from `CommandStrip.onSettingsTap`. Takes the one fake this file ever
/// needs to override directly (a stand-in `RoomSocketService`) rather than
/// a generically-typed override list, which the installed `flutter_riverpod`
/// version doesn't cleanly expose the `Override` type for at the import
/// surface this file has access to.
Widget _harness({RoomSocketService? fakeSocket, required double width}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        name: 'home',
        path: '/',
        builder: (context, state) => Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showSettingsSheet(context),
                child: const Text('Open Settings'),
              ),
            ),
          ),
        ),
      ),
      GoRoute(
        name: Routes.help,
        path: '/help',
        builder: (context, state) => const Scaffold(body: Text('Help Screen')),
      ),
    ],
  );

  final app = MediaQuery(
    data: MediaQueryData(size: Size(width, 800)),
    child: MaterialApp.router(routerConfig: router),
  );

  return fakeSocket == null
      ? ProviderScope(child: app)
      : ProviderScope(
          overrides: [roomSocketServiceProvider.overrideWithValue(fakeSocket)],
          child: app,
        );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Settings sheet — presentation', () {
    testWidgets('opens as a bottom sheet on a narrow (mobile) width', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(width: 400));
      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      // A Dialog widget is NOT used for the narrow case.
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('opens as a centered dialog on a wide (desktop) width', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(width: 1200));
      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('close button dismisses the sheet', (tester) async {
      await tester.pumpWidget(_harness(width: 400));
      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);

      await tester.tap(find.byTooltip('Close settings'));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsNothing);
    });
  });

  group('Settings sheet — toggles', () {
    testWidgets(
      'music switch toggles musicMutedProvider independently of sfx',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MediaQuery(
              data: const MediaQueryData(size: Size(400, 800)),
              child: MaterialApp(
                home: Builder(
                  builder: (context) => Scaffold(
                    body: ElevatedButton(
                      onPressed: () => showSettingsSheet(context),
                      child: const Text('Open Settings'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open Settings'));
        await tester.pumpAndSettle();

        expect(container.read(musicMutedProvider), isFalse);
        expect(container.read(sfxMutedProvider), isFalse);

        // Tap the actual Switch, not its label — the label Text has no tap
        // handler of its own. Music is the first of the three switches in the
        // sheet (Music, Sound effects, Reduced motion, in that order).
        await tester.tap(find.byType(Switch).at(0));
        await tester.pumpAndSettle();

        expect(container.read(musicMutedProvider), isTrue);
        expect(
          container.read(sfxMutedProvider),
          isFalse,
          reason: 'toggling Music in the sheet must never affect Sound effects',
        );
      },
    );

    testWidgets('reduced motion switch toggles appPreferencesProvider', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(400, 800)),
            child: MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () => showSettingsSheet(context),
                    child: const Text('Open Settings'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();

      // Third switch: Music, Sound effects, then Reduced motion.
      await tester.tap(find.byType(Switch).at(2));
      await tester.pumpAndSettle();

      expect(container.read(appPreferencesProvider).reducedMotion, isTrue);
    });
  });

  group('Settings sheet — Leave Room', () {
    testWidgets('requires explicit confirmation before leaving', (
      tester,
    ) async {
      final fakeSocket = _RecordingSocketService();
      await tester.pumpWidget(_harness(fakeSocket: fakeSocket, width: 400));
      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Leave Room'));
      await tester.pumpAndSettle();

      // Confirmation surfaced, and nothing was sent to the server yet.
      expect(find.text('Leave this room?'), findsOneWidget);
      expect(fakeSocket.sentEvents, isEmpty);

      // "Stay" backs out without leaving.
      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();
      expect(find.text('Leave this room?'), findsNothing);
      expect(find.text('Settings'), findsOneWidget);
      expect(fakeSocket.sentEvents, isEmpty);
    });

    testWidgets('confirming sends exit_game_to_home and returns home', (
      tester,
    ) async {
      final fakeSocket = _RecordingSocketService();
      await tester.pumpWidget(_harness(fakeSocket: fakeSocket, width: 400));
      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Leave Room'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave Room').last);
      await tester.pumpAndSettle();

      expect(fakeSocket.sentEvents, contains('exit_game_to_home'));
      // Both overlays are gone and we're back on the home route.
      expect(find.text('Settings'), findsNothing);
      expect(find.text('Leave this room?'), findsNothing);
      expect(find.text('Open Settings'), findsOneWidget);
    });
  });

  group('Settings sheet — How to Play', () {
    testWidgets('navigates to the help route and closes the sheet', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(width: 400));
      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('How to Play'));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsNothing);
      expect(find.text('Help Screen'), findsOneWidget);
    });
  });
}
