import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/admin/models/admin_models.dart';
import 'package:hidden_eleven/features/host/host_room_screen.dart';

void main() {
  test(
    'AdminLeagueBundle.fromJson / ActiveLeagueBundle.fromJson round-trip',
    () {
      final bundle = AdminLeagueBundle.fromJson({
        'id': 'b1',
        'name': 'Top 5 Leagues',
        'description': 'Example',
        'leagueSlugs': ['premier-league', 'la-liga'],
        'active': true,
        'sortOrder': 2,
      });
      expect(bundle.leagueSlugs, ['premier-league', 'la-liga']);
      expect(bundle.toJson()['name'], 'Top 5 Leagues');

      final active = ActiveLeagueBundle.fromJson({
        'id': 'b1',
        'name': 'Top 5 Leagues',
        'description': 'Example',
        'sortOrder': 0,
        'leagues': [
          {'slug': 'premier-league', 'name': 'Premier League'},
          {'slug': 'la-liga', 'name': 'La Liga'},
        ],
      });
      expect(active.leagues.map((l) => l.name).toList(), [
        'Premier League',
        'La Liga',
      ]);
    },
  );

  testWidgets('host league section shows bundle and manual mode chips', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: HostRoomScreen(displayName: 'Alice')),
      ),
    );
    await tester.pump();

    expect(find.text('Use a bundle'), findsOneWidget);
    expect(find.text('Select manually'), findsOneWidget);
    expect(
      find.textContaining('leave none selected to use all allowed leagues'),
      findsOneWidget,
    );

    await tester.tap(find.text('Use a bundle'));
    await tester.pump();
    expect(find.textContaining('Choose one ready-made pack'), findsOneWidget);
    // Without a live API, empty-bundle copy appears.
    expect(find.textContaining('No active league bundles'), findsOneWidget);
  });
}
