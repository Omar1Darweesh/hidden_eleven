import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hidden_eleven/features/admin/tournament_awards/tournament_awards_tab.dart';
import 'package:hidden_eleven/features/admin/services/admin_api.dart'
    as admin_api;
import 'package:hidden_eleven/features/admin/services/admin_auth_service.dart';

// http.Response defaults to latin1 decoding unless the content-type header
// names utf-8 explicitly (see D2's abilities_tab_test.dart for the same fix).
const _jsonUtf8 = {'content-type': 'application/json; charset=utf-8'};

Map<String, dynamic> _valuesJson({
  int championPoints = 50,
  int runnerUpPoints = 20,
  int topScorerBonus = 15,
  int mostAssistsBonus = 10,
  int highestRatingBonus = 10,
}) => {
  'championPoints': championPoints,
  'runnerUpPoints': runnerUpPoints,
  'topScorerBonus': topScorerBonus,
  'mostAssistsBonus': mostAssistsBonus,
  'highestRatingBonus': highestRatingBonus,
};

Map<String, dynamic> _versionJson({
  required int version,
  required String status,
  String? publishedAt,
  String? note,
  Map<String, dynamic>? values,
}) => {
  'version': version,
  'status': status,
  'createdAt': '2026-01-01T00:00:00.000Z',
  if (publishedAt != null) 'publishedAt': publishedAt,
  if (note != null) 'note': note,
  'values': values ?? _valuesJson(),
};

Map<String, dynamic> _fileJson({
  required Map<String, dynamic> draft,
  required Map<String, dynamic> published,
  List<Map<String, dynamic>> history = const [],
}) => {'draft': draft, 'published': published, 'history': history};

void main() {
  setUp(() {
    AdminAuthService.ensureTestStorage();
  });

  tearDown(() {
    admin_api.debugHttpClient = null;
    AdminAuthService.debugReset();
  });

  Future<void> pumpTab(
    WidgetTester tester, {
    required Map<String, dynamic> fileJson,
    Map<String, dynamic>? publishResultFileJson,
    int publishStatusCode = 201,
    Object? publishErrorBody,
    List<Map<String, dynamic>>? capturedDraftPuts,
    List<Map<String, dynamic>>? capturedPublishes,
  }) async {
    // A mutable "on disk" copy — GET must reflect whatever the most recent
    // PUT/POST wrote (the widget reloads via GET right after each save), the
    // same gotcha documented for D2/D5's admin tab tests.
    var currentFile = fileJson;

    admin_api.debugHttpClient = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path.endsWith('/tournament-awards-config')) {
        return http.Response(jsonEncode(currentFile), 200, headers: _jsonUtf8);
      }
      if (request.method == 'PUT' &&
          request.url.path.endsWith('/tournament-awards-config/draft')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        capturedDraftPuts?.add(body);
        final newDraft = _versionJson(
          version: ((currentFile['published'] as Map)['version'] as int) + 1,
          status: 'draft',
          values: body,
        );
        currentFile = {...currentFile, 'draft': newDraft};
        return http.Response(jsonEncode(newDraft), 200, headers: _jsonUtf8);
      }
      if (request.method == 'POST' &&
          request.url.path.endsWith('/tournament-awards-config/publish')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        capturedPublishes?.add(body);
        if (publishStatusCode != 201) {
          return http.Response(
            jsonEncode(publishErrorBody),
            publishStatusCode,
            headers: _jsonUtf8,
          );
        }
        currentFile = publishResultFileJson ?? currentFile;
        return http.Response(jsonEncode(currentFile), 201, headers: _jsonUtf8);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TournamentAwardsTab())),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('loads and renders draft and published values', (tester) async {
    final published = _versionJson(
      version: 3,
      status: 'published',
      publishedAt: '2026-01-05T00:00:00.000Z',
      values: _valuesJson(championPoints: 50, runnerUpPoints: 20),
    );
    final draft = _versionJson(
      version: 4,
      status: 'draft',
      values: _valuesJson(championPoints: 75, runnerUpPoints: 20),
    );
    await pumpTab(
      tester,
      fileJson: _fileJson(draft: draft, published: published),
    );

    // Text fields are pre-populated from the DRAFT values (matches
    // ScoringTab's _load()/_initControllers() convention).
    expect(find.widgetWithText(TextFormField, '75'), findsOneWidget);
    // The status banner shows the PUBLISHED version.
    expect(find.textContaining('Published: v3'), findsOneWidget);
    expect(find.textContaining('will become v4'), findsOneWidget);
  });

  testWidgets('editing a field and saving draft sends the full values object', (
    tester,
  ) async {
    final capturedDraftPuts = <Map<String, dynamic>>[];
    final published = _versionJson(version: 1, status: 'published');
    final draft = _versionJson(version: 2, status: 'draft');
    await pumpTab(
      tester,
      fileJson: _fileJson(draft: draft, published: published),
      capturedDraftPuts: capturedDraftPuts,
    );

    await tester.enterText(find.widgetWithText(TextFormField, '50'), '999');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Save Draft'));
    await tester.pumpAndSettle();

    expect(capturedDraftPuts, hasLength(1));
    expect(capturedDraftPuts.first['championPoints'], 999);
    expect(capturedDraftPuts.first['runnerUpPoints'], 20);
    expect(find.text('Draft saved.'), findsOneWidget);
  });

  testWidgets('publish flow saves the draft, sends the note, and reloads', (
    tester,
  ) async {
    final capturedDraftPuts = <Map<String, dynamic>>[];
    final capturedPublishes = <Map<String, dynamic>>[];
    final published = _versionJson(version: 1, status: 'published');
    final draft = _versionJson(version: 2, status: 'draft');
    final republished = _versionJson(
      version: 2,
      status: 'published',
      publishedAt: '2026-01-06T00:00:00.000Z',
      note: 'season 2 bump',
    );
    await pumpTab(
      tester,
      fileJson: _fileJson(draft: draft, published: published),
      publishResultFileJson: _fileJson(
        draft: _versionJson(version: 3, status: 'draft'),
        published: republished,
      ),
      capturedDraftPuts: capturedDraftPuts,
      capturedPublishes: capturedPublishes,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Publish note (optional)'),
      'season 2 bump',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Publish'));
    await tester.pumpAndSettle();

    // Publish saves the draft first (so the note flow round-trips the
    // on-screen values, not a stale server copy), then publishes with note.
    expect(capturedDraftPuts, hasLength(1));
    expect(capturedPublishes, hasLength(1));
    expect(capturedPublishes.first['note'], 'season 2 bump');
    expect(find.text('Published.'), findsOneWidget);
    // Reloaded — the new published version is now shown.
    expect(find.textContaining('Published: v2'), findsOneWidget);
  });

  testWidgets(
    'a publish validation error (400) shows a non-blocking dialog naming the bad field',
    (tester) async {
      final published = _versionJson(version: 1, status: 'published');
      final draft = _versionJson(version: 2, status: 'draft');
      await pumpTab(
        tester,
        fileJson: _fileJson(draft: draft, published: published),
        publishStatusCode: 400,
        publishErrorBody: {
          'error': ['Champion points must be between 0 and 999.'],
        },
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Publish'));
      await tester.pumpAndSettle();

      expect(find.text('Cannot publish'), findsOneWidget);
      expect(
        find.textContaining('Champion points must be between 0 and 999.'),
        findsOneWidget,
      );

      // Dismissing the dialog leaves the tab usable, still on the old
      // published version (publish never went through).
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Published: v1'), findsOneWidget);
    },
  );

  testWidgets('the future-tournaments note is visible', (tester) async {
    final published = _versionJson(version: 1, status: 'published');
    final draft = _versionJson(version: 2, status: 'draft');
    await pumpTab(
      tester,
      fileJson: _fileJson(draft: draft, published: published),
    );

    expect(
      find.textContaining('apply only to tournaments started after publishing'),
      findsOneWidget,
    );
  });
}
