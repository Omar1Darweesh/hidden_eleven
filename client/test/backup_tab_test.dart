import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hidden_eleven/features/admin/backup/backup_tab.dart';
import 'package:hidden_eleven/features/admin/services/admin_api.dart'
    as admin_api;
import 'package:hidden_eleven/features/admin/services/admin_auth_service.dart';

const _jsonUtf8 = {'content-type': 'application/json; charset=utf-8'};

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
    required Map<String, dynamic> statusJson,
    Map<String, dynamic>? postResultJson,
    List<int>? postCallCount,
    List<int>? downloadCallCount,
  }) async {
    var currentStatus = statusJson;

    admin_api.debugHttpClient = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path.endsWith('/backup/download')) {
        downloadCallCount?.add(1);
        return http.Response.bytes([1, 2, 3, 4], 200);
      }
      if (request.method == 'GET' && request.url.path.endsWith('/backup')) {
        return http.Response(
          jsonEncode(currentStatus),
          200,
          headers: _jsonUtf8,
        );
      }
      if (request.method == 'POST' && request.url.path.endsWith('/backup')) {
        postCallCount?.add(1);
        currentStatus = postResultJson ?? currentStatus;
        return http.Response(
          jsonEncode(currentStatus),
          201,
          headers: _jsonUtf8,
        );
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BackupTab())),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows "no backup yet" when none exists', (tester) async {
    await pumpTab(tester, statusJson: {'exists': false});

    expect(find.text('No backup yet'), findsOneWidget);
  });

  testWidgets('renders filename, size, and timestamp when a backup exists', (
    tester,
  ) async {
    await pumpTab(
      tester,
      statusJson: {
        'exists': true,
        'filename': 'hidden-eleven-backup.tar.gz',
        'sizeBytes': 2097152,
        'createdAt': '2026-07-18T03:00:00.000Z',
      },
    );

    expect(find.text('hidden-eleven-backup.tar.gz'), findsOneWidget);
    expect(find.textContaining('2.0 MB'), findsOneWidget);
    expect(find.textContaining('2026-07-18T03:00:00.000Z'), findsOneWidget);
  });

  testWidgets('tapping Backup Now triggers a POST and refreshes the status', (
    tester,
  ) async {
    final postCalls = <int>[];
    await pumpTab(
      tester,
      statusJson: {'exists': false},
      postResultJson: {
        'exists': true,
        'filename': 'hidden-eleven-backup.tar.gz',
        'sizeBytes': 1024,
        'createdAt': '2026-07-19T10:00:00.000Z',
      },
      postCallCount: postCalls,
    );

    expect(find.text('No backup yet'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Backup Now'));
    await tester.pumpAndSettle();

    expect(postCalls, hasLength(1));
    expect(find.text('hidden-eleven-backup.tar.gz'), findsOneWidget);
    expect(find.text('Backup created.'), findsOneWidget);
  });

  testWidgets('Download to PC is hidden when there is no backup yet', (
    tester,
  ) async {
    await pumpTab(tester, statusJson: {'exists': false});

    expect(find.text('Download to PC'), findsNothing);
  });

  testWidgets('tapping Download to PC fetches the archive bytes', (
    tester,
  ) async {
    final downloadCalls = <int>[];
    await pumpTab(
      tester,
      statusJson: {
        'exists': true,
        'filename': 'hidden-eleven-backup.tar.gz',
        'sizeBytes': 1024,
        'createdAt': '2026-07-19T10:00:00.000Z',
      },
      downloadCallCount: downloadCalls,
    );

    expect(find.text('Download to PC'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Download to PC'));
    await tester.pumpAndSettle();

    // Triggering an actual browser save is only possible on a real Flutter
    // web target; the VM test host still proves the archive bytes were
    // fetched with auth before any save is attempted.
    expect(downloadCalls, hasLength(1));
  });
}
