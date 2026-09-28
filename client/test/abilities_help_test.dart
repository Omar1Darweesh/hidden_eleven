import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hidden_eleven/features/admin/services/admin_api.dart'
    as admin_api;
import 'package:hidden_eleven/features/game/models/ability.dart';
import 'package:hidden_eleven/features/game/models/chemistry_vars.dart';
import 'package:hidden_eleven/features/game/widgets/abilities_help.dart';

void main() {
  setUp(() {
    AbilityMeta.debugOverrideConfigured(null);
    ChemistryVars.debugOverrideValues(null);
    // The dialog's own AdminApi.getContextHelp() call is unrelated to what
    // these tests cover (the "HOW IT WORKS" fallback, not "THE CARDS") — a
    // fast, deterministic failure here keeps the test from depending on the
    // sandbox's real (slow) network-unreachable timing.
    admin_api.debugHttpClient = MockClient(
      (request) async => http.Response('error', 500),
    );
  });

  tearDown(() {
    admin_api.debugHttpClient = null;
  });

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAbilitiesHelpDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'THE CARDS section shows the server-configured description, resolved through ChemistryVars',
    (tester) async {
      AbilityMeta.debugOverrideConfigured({
        AbilityType.yellow: (
          name: 'Yellow Card',
          description: 'Docks {yellowPenalty} points from a rival.',
          color: const Color(0xFFF2C037),
        ),
      });
      ChemistryVars.debugOverrideValues({'yellowPenalty': 45});

      await openDialog(tester);

      expect(find.text('Docks 45 points from a rival.'), findsOneWidget);
      // The old hardcoded tagline must not be the rendered source anymore.
      expect(find.text('Knock 20 points off a rival’s score.'), findsNothing);
    },
  );

  testWidgets(
    'falls back to the built-in description before ensureLoaded() ever resolves',
    (tester) async {
      // No debugOverrideConfigured call — simulates the pre-fetch state.
      await openDialog(tester);

      expect(find.text('Knock 20 points off a rival’s score.'), findsOneWidget);
    },
  );
}
