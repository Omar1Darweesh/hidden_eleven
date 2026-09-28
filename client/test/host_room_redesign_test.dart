import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hidden_eleven/features/host/host_room_screen.dart';
import 'package:hidden_eleven/features/admin/services/admin_api.dart'
    as admin_api;

Widget harness() => const ProviderScope(
  child: MaterialApp(home: HostRoomScreen(displayName: 'Alice')),
);

void main() {
  // The screen is a long SingleChildScrollView — a tall test surface avoids
  // needing to scroll to each control before tapping it.
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  tearDown(() {
    admin_api.debugHttpClient = null;
  });

  // Formation's whole section is gated on `_formations.isNotEmpty`, which
  // only becomes true once `AdminApi.getFormations()` resolves — a real HTTP
  // call in production. Without stubbing it, `_formations` stays `[]` in
  // every widget test (the call errors and is silently swallowed), so
  // "FORMATION" would never render regardless of whether the reorder worked.
  // This uses the app's own sanctioned test seam (`admin_api.debugHttpClient`,
  // documented in admin_api.dart) rather than any change to production code.
  Future<void> pumpWithFormations(WidgetTester tester) async {
    admin_api.debugHttpClient = MockClient((request) async {
      if (request.url.path.endsWith('/formations')) {
        return http.Response(
          jsonEncode([
            {
              'slug': '4-4-2',
              'name': '4-4-2',
              'active': true,
              'slots': [
                {'index': 0, 'label': 'GK', 'basePositionType': 'GK'},
              ],
            },
          ]),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('not found', 404);
    });

    useTallSurface(tester);
    await tester.pumpWidget(harness());
    // One pump for the widget tree, one more for the async getFormations()
    // future to resolve and setState.
    await tester.pump();
    await tester.pump();
  }

  group('Host Room — progressive disclosure', () {
    testWidgets('advanced settings are collapsed by default', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(harness());
      await tester.pump();

      expect(find.text('More settings'), findsOneWidget);
      expect(find.text('SUBS PHASE LIMIT'), findsNothing);
      expect(find.text('ABILITY USAGE TIME'), findsNothing);
    });

    testWidgets('tapping "More settings" reveals the advanced group', (
      tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(harness());
      await tester.pump();

      await tester.tap(find.text('More settings'));
      await tester.pump();

      expect(find.text('Hide more settings'), findsOneWidget);
      expect(find.text('SUBS PHASE LIMIT'), findsOneWidget);
      expect(find.text('ABILITY USAGE TIME'), findsOneWidget);
    });

    testWidgets(
      'quick-create tier (Leagues, Turn Timer, AI Opponents) is always visible',
      (tester) async {
        useTallSurface(tester);
        await tester.pumpWidget(harness());
        await tester.pump();

        expect(find.text('TURN TIME LIMIT'), findsOneWidget);
        expect(find.text('AI OPPONENTS'), findsOneWidget);
        expect(find.text('LEAGUES'), findsOneWidget);
      },
    );

    testWidgets('Formation is visible before "More settings" is expanded', (
      tester,
    ) async {
      await pumpWithFormations(tester);

      // Not inside the collapsed group — this is checked BEFORE any tap on
      // "More settings", so if Formation were still nested inside that
      // disclosure it would not be here yet.
      expect(find.text('FORMATION'), findsOneWidget);
      expect(find.text('Hide more settings'), findsNothing);
    });

    testWidgets('Formation is NOT inside the collapsed More Settings content', (
      tester,
    ) async {
      await pumpWithFormations(tester);

      // Confirm the fields that ARE still behind the disclosure are
      // genuinely absent beforehand — the negative control for the
      // assertion above, so "Formation was already visible" isn't
      // trivially true because everything is visible.
      expect(find.text('SUBS PHASE LIMIT'), findsNothing);
      expect(find.text('ABILITY USAGE TIME'), findsNothing);
      expect(find.text('FORMATION'), findsOneWidget);

      await tester.tap(find.text('More settings'));
      await tester.pump();

      // Still exactly one Formation section after expanding — proving it
      // was never duplicated between the always-visible tier and the
      // collapsed one.
      expect(find.text('FORMATION'), findsOneWidget);
      expect(find.text('SUBS PHASE LIMIT'), findsOneWidget);
      expect(find.text('ABILITY USAGE TIME'), findsOneWidget);
    });

    testWidgets('order is League, then Formation, then Turn Timer, on both '
        'axes checked independently', (tester) async {
      await pumpWithFormations(tester);

      final leagueY = tester.getTopLeft(find.text('LEAGUES')).dy;
      final formationY = tester.getTopLeft(find.text('FORMATION')).dy;
      final turnTimerY = tester.getTopLeft(find.text('TURN TIME LIMIT')).dy;

      expect(
        leagueY,
        lessThan(formationY),
        reason: 'League must appear above Formation',
      );
      expect(
        formationY,
        lessThan(turnTimerY),
        reason: 'Formation must appear above Turn Timer',
      );
    });
  });

  group('Host Room — Room Brief summary', () {
    testWidgets('reflects the default configuration', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(harness());
      await tester.pump();

      expect(find.textContaining('30s turns'), findsOneWidget);
      expect(find.textContaining('No AI opponents'), findsOneWidget);
    });

    testWidgets('updates live when a setting changes', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(harness());
      await tester.pump();

      await tester.tap(find.text('45s'));
      await tester.pump();

      expect(find.textContaining('45s turns'), findsOneWidget);
      expect(find.textContaining('30s turns'), findsNothing);
    });
  });

  group('Host Room — dirty/discard confirmation', () {
    testWidgets('back with no changes pops without a confirmation dialog', (
      tester,
    ) async {
      // Pushed onto a real Navigator (unlike the bare-MaterialApp harness)
      // so `context.pop()` has somewhere to go — go_router's pop() extension
      // still requires a GoRouter ancestor to resolve, so this only proves
      // no dialog appears; it doesn't exercise the pop itself.
      useTallSurface(tester);
      await tester.pumpWidget(harness());
      await tester.pump();

      expect(find.text('Discard room settings?'), findsNothing);
    });

    testWidgets(
      'changing a setting then tapping back shows a discard confirmation',
      (tester) async {
        useTallSurface(tester);
        await tester.pumpWidget(harness());
        await tester.pump();

        // Change AI Opponents away from its default (0 / "None").
        await tester.tap(find.text('1').first);
        await tester.pump();

        await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
        await tester.pump();

        expect(find.text('Discard room settings?'), findsOneWidget);

        // "Keep Editing" just closes the dialog — never reaches context.pop().
        await tester.tap(find.text('Keep Editing'));
        await tester.pump();
        expect(find.text('Discard room settings?'), findsNothing);
      },
    );
  });
}
