import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hidden_eleven/features/admin/abilities/abilities_tab.dart';
import 'package:hidden_eleven/features/admin/services/admin_api.dart'
    as admin_api;
import 'package:hidden_eleven/features/admin/services/admin_auth_service.dart';

// http.Response defaults to latin1 decoding unless the content-type header
// names utf-8 explicitly — without this, any non-ASCII character in a fixture
// (e.g. the curly apostrophes in these ability descriptions) throws.
const _jsonUtf8 = {'content-type': 'application/json; charset=utf-8'};

Map<String, dynamic> _abilityJson({
  required String type,
  required String name,
  required bool enabled,
  required String color,
  required String description,
}) => {
  'type': type,
  'name': name,
  'enabled': enabled,
  'color': color,
  'description': description,
};

void main() {
  setUp(() {
    AdminAuthService.ensureTestStorage();
  });

  tearDown(() {
    admin_api.debugHttpClient = null;
    AdminAuthService.debugReset();
  });

  testWidgets(
    'edit dialog pre-populates name/color/description and saves all three together',
    (tester) async {
      final abilities = [
        _abilityJson(
          type: 'yellow',
          name: 'Yellow Card',
          enabled: true,
          color: '#F2C037',
          description: 'Knock {yellowPenalty} points off a rival’s score.',
        ),
      ];

      Map<String, dynamic>? capturedPutBody;
      admin_api.debugHttpClient = MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path.endsWith('/abilities')) {
          return http.Response(jsonEncode(abilities), 200, headers: _jsonUtf8);
        }
        if (request.method == 'PUT' &&
            request.url.path.contains('/abilities/yellow')) {
          capturedPutBody = jsonDecode(request.body) as Map<String, dynamic>;
          final updated = {...abilities.first, ...capturedPutBody!};
          abilities[0] =
              updated; // subsequent GETs (the post-save reload) see it
          return http.Response(jsonEncode(updated), 200, headers: _jsonUtf8);
        }
        return http.Response('not found', 404);
      });

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AbilitiesTab())),
      );
      await tester.pumpAndSettle();

      // Row renders the loaded name/description (not a hardcoded fallback).
      expect(find.text('Yellow Card'), findsOneWidget);
      expect(
        find.text('Knock {yellowPenalty} points off a rival’s score.'),
        findsOneWidget,
      );

      // Open the edit dialog.
      await tester.tap(find.byTooltip('Edit name, colour & description'));
      await tester.pumpAndSettle();

      // Pre-populated fields (widgetWithText also matches the row's read-only
      // Text behind the dialog, so scope these to TextFormField specifically).
      expect(find.widgetWithText(TextFormField, 'Yellow Card'), findsOneWidget);
      expect(
        find.widgetWithText(
          TextFormField,
          'Knock {yellowPenalty} points off a rival’s score.',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextFormField, '#F2C037'), findsOneWidget);

      // Edit all three fields.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Yellow Card'),
        'Caution Card',
      );
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          'Knock {yellowPenalty} points off a rival’s score.',
        ),
        'Docks {yellowPenalty} points from a rival.',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '#F2C037'),
        '#ABCDEF',
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      // All three fields were sent together in the SAME request.
      expect(capturedPutBody, isNotNull);
      expect(capturedPutBody!['name'], 'Caution Card');
      expect(
        capturedPutBody!['description'],
        'Docks {yellowPenalty} points from a rival.',
      );
      expect(capturedPutBody!['color'], '#ABCDEF');

      // Dialog closed and the row reflects the save.
      expect(find.text('Caution Card'), findsOneWidget);
    },
  );

  testWidgets('toggling enabled does not touch name/color/description', (
    tester,
  ) async {
    final abilities = [
      _abilityJson(
        type: 'coach',
        name: 'Coach Card',
        enabled: true,
        color: '#A55CFF',
        description: 'Add a new position to one of your players.',
      ),
    ];

    Map<String, dynamic>? capturedPutBody;
    admin_api.debugHttpClient = MockClient((request) async {
      if (request.method == 'GET' && request.url.path.endsWith('/abilities')) {
        return http.Response(jsonEncode(abilities), 200, headers: _jsonUtf8);
      }
      if (request.method == 'PUT' &&
          request.url.path.contains('/abilities/coach')) {
        capturedPutBody = jsonDecode(request.body) as Map<String, dynamic>;
        final updated = {...abilities.first, ...capturedPutBody!};
        return http.Response(jsonEncode(updated), 200, headers: _jsonUtf8);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AbilitiesTab())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(capturedPutBody, {'enabled': false});
  });
}
