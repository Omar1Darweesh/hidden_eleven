import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/widgets/player_card.dart';
import 'package:hidden_eleven/features/lobby/models/server_event.dart';
import 'package:hidden_eleven/features/subs/subs_player_list.dart';

/// Regression coverage for the subs-picker redesign: replacing the eager
/// grid of full `PlayerCard`s (each with up to three `Image.network` calls)
/// with a lazy, text-only `ListView.builder` of rows. These tests pin: (a)
/// eligible players render as lightweight rows, never as full `PlayerCard`s,
/// (b) tapping a row opens the existing details modal, (c) picking from that
/// modal still invokes the caller's onPick with the right card.
void main() {
  const players = [
    CandidateCard(
      cardId: 'fc_1',
      playerName: 'Alpha Striker',
      basePositionType: 'ST',
      rating: 84,
      club: 'Arsenal',
      nationality: 'England',
      pace: 88,
      physical: 75,
    ),
    CandidateCard(
      cardId: 'fc_2',
      playerName: 'Beta Winger',
      basePositionType: 'RW',
      rating: 81,
      club: 'Arsenal',
      nationality: 'France',
      pace: 90,
      physical: 68,
    ),
  ];

  const result = SubSpinResult(
    positionGroup: 'att',
    clubName: 'Arsenal',
    players: players,
  );

  Future<void> pump(WidgetTester tester, void Function(CandidateCard) onPick) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubsPlayerListPicker(
            result: result,
            color: Colors.blue,
            lineup: const [],
            onPick: onPick,
          ),
        ),
      ),
    );
  }

  testWidgets(
    'renders eligible subs as lightweight list rows, never as full PlayerCard widgets',
    (tester) async {
      await pump(tester, (_) {});

      // The lazy, virtualized list — not an eager Wrap-of-cards.
      expect(find.byType(ListView), findsOneWidget);

      // No full visual PlayerCard anywhere in the picker.
      expect(find.byType(PlayerCard), findsNothing);

      // Lightweight text content is present per row: name, club and nation
      // each on their own line, and positions in the dedicated right area.
      expect(find.text('Alpha Striker'), findsOneWidget);
      expect(find.text('Beta Winger'), findsOneWidget);
      // Club line appears per row (plus once in the banner) — 3 total here
      // since both fixture players are at the spun club.
      expect(find.text('Arsenal'), findsNWidgets(3));
      // Nation lines, one per player (distinct nationalities).
      expect(find.text('England'), findsOneWidget);
      expect(find.text('France'), findsOneWidget);
      // Positions in the dedicated right area (primary only for these
      // fixtures, which have no alt positions).
      expect(find.text('ST'), findsOneWidget);
      expect(find.text('RW'), findsOneWidget);
    },
  );

  testWidgets('tapping a row opens the card details modal', (tester) async {
    await pump(tester, (_) {});

    expect(find.text('PICK'), findsNothing);

    await tester.tap(find.text('Alpha Striker'));
    await tester.pumpAndSettle();

    // The existing details modal opened, showing the full player info and
    // a Pick button — reused, not rebuilt.
    expect(find.text('PICK'), findsOneWidget);
    expect(find.text('Alpha Striker'), findsWidgets);
  });

  testWidgets(
    'selecting Pick from the details modal invokes onPick with the tapped card',
    (tester) async {
      CandidateCard? picked;
      await pump(tester, (c) => picked = c);

      await tester.tap(find.text('Beta Winger'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('PICK'));
      await tester.pumpAndSettle();

      expect(picked, isNotNull);
      expect(picked!.cardId, 'fc_2');
      // Modal closes back to the list after picking.
      expect(find.text('PICK'), findsNothing);
    },
  );

  testWidgets('shows an empty state when there are no eligible players', (
    tester,
  ) async {
    const emptyResult = SubSpinResult(
      positionGroup: 'att',
      clubName: 'Arsenal',
      players: [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubsPlayerListPicker(
            result: emptyResult,
            color: Colors.blue,
            lineup: const [],
            onPick: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('No eligible players for this club.'), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
  });
}
