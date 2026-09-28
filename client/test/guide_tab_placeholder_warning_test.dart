import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hidden_eleven/features/admin/guide/guide_tab.dart';
import 'package:hidden_eleven/features/admin/services/admin_api.dart'
    as admin_api;
import 'package:hidden_eleven/features/admin/services/admin_auth_service.dart';

// http.Response defaults to latin1 decoding unless the content-type header
// names utf-8 explicitly (see D2's abilities_tab_test.dart for the same fix).
const _jsonUtf8 = {'content-type': 'application/json; charset=utf-8'};

Map<String, dynamic> _tipJson({
  required String id,
  required String text,
  String? phase,
}) => {'id': id, 'text': text, 'phase': phase, 'order': 0, 'visible': true};

void main() {
  setUp(() {
    AdminAuthService.ensureTestStorage();
  });

  tearDown(() {
    admin_api.debugHttpClient = null;
    AdminAuthService.debugReset();
  });

  Future<void> pumpQuickTipsTab(
    WidgetTester tester, {
    required List<Map<String, dynamic>> tips,
    required Map<String, dynamic>? Function(
      String id,
      Map<String, dynamic> body,
    )
    onSave,
  }) async {
    admin_api.debugHttpClient = MockClient((request) async {
      if (request.method == 'GET' && request.url.path.endsWith('/quick-tips')) {
        return http.Response(jsonEncode(tips), 200, headers: _jsonUtf8);
      }
      if (request.method == 'PUT' &&
          request.url.path.contains('/quick-tips/')) {
        final id = request.url.pathSegments.last;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final updated = onSave(id, body);
        if (updated == null) return http.Response('not found', 404);
        return http.Response(jsonEncode(updated), 200, headers: _jsonUtf8);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: GuideTab())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quick Tips'));
    await tester.pumpAndSettle();
  }

  testWidgets('saving with only known placeholders shows no warning', (
    tester,
  ) async {
    final tips = [_tipJson(id: 't1', text: 'Original tip text.')];
    await pumpQuickTipsTab(
      tester,
      tips: tips,
      onSave: (id, body) => {...tips.first, ...body},
    );

    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Original tip text.'),
      'Line leaders earn +{lineLeaderBonus} each.',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('not a recognized chemistry placeholder'),
      findsNothing,
    );
  });

  testWidgets(
    'saving with a typo\'d placeholder shows a non-blocking warning naming the bad token',
    (tester) async {
      final tips = [_tipJson(id: 't1', text: 'Original tip text.')];
      await pumpQuickTipsTab(
        tester,
        tips: tips,
        onSave: (id, body) {
          final updated = {...tips.first, ...body};
          tips[0] = updated; // the post-save reload must see the new text
          return updated;
        },
      );

      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Original tip text.'),
        'Docks {yellowPenaltyy} points.',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      // Non-blocking: the save still succeeded and the dialog still closed
      // (the row now shows the saved text), the warning is purely additive.
      expect(find.text('Docks {yellowPenaltyy} points.'), findsOneWidget);
      expect(
        find.textContaining(
          'this isn\'t a recognized chemistry placeholder: {yellowPenaltyy}',
        ),
        findsOneWidget,
      );
    },
  );
}
