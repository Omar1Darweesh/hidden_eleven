import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hidden_eleven/features/game/models/chemistry_bonus.dart';
import 'package:hidden_eleven/features/game/services/chemistry_evaluator.dart';
import 'package:hidden_eleven/features/game/widgets/fit_note_card.dart';

ChemistryBonus _sameClub({
  required String club,
  required int count,
  required String label,
  required int reward,
  ChemistryTier tier = ChemistryTier.easy,
}) => ChemistryBonus(
  type: ChemistryBonusType.sameClub,
  params: {'club': club, 'count': count},
  label: label,
  tier: tier,
  reward: reward,
);

LineupCard _card({String? club, String? nationality, String? league}) =>
    LineupCard(
      club: club,
      nationality: nationality,
      league: league,
      slotPosition: 'CM',
    );

Widget _harness(Widget child) => MaterialApp(
  home: Scaffold(body: Material(child: child)),
);

/// Finds a [Semantics] widget by its exact label, without requiring the
/// semantics tree to be enabled (unlike `find.bySemanticsLabel`).
Finder _bySemanticsLabel(String label) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == label,
);

void main() {
  group('FitNoteCard — ranking', () {
    testWidgets('satisfied bonuses rank before unmet ones', (tester) async {
      final unmet = _sameClub(
        club: 'Arsenal',
        count: 3,
        label: 'Field 3 Arsenal players',
        reward: 6,
      );
      final met = _sameClub(
        club: 'Chelsea',
        count: 2,
        label: 'Field 2 Chelsea players',
        reward: 2,
      );
      final lineup = [_card(club: 'Chelsea'), _card(club: 'Chelsea')];

      await tester.pumpWidget(
        _harness(FitNoteCard(bonuses: [unmet, met], lineup: lineup)),
      );

      // Met bonus (lower reward) must render before the unmet, higher-reward one.
      final metPos = tester.getTopLeft(find.text('Field 2 Chelsea players'));
      final unmetPos = tester.getTopLeft(find.text('Field 3 Arsenal players'));
      expect(metPos.dy, lessThan(unmetPos.dy));
    });

    testWidgets('among satisfied bonuses, higher reward ranks first', (
      tester,
    ) async {
      final lowReward = _sameClub(
        club: 'Chelsea',
        count: 2,
        label: 'Low reward met',
        reward: 2,
      );
      final highReward = _sameClub(
        club: 'Arsenal',
        count: 2,
        label: 'High reward met',
        reward: 6,
      );
      final lineup = [
        _card(club: 'Chelsea'),
        _card(club: 'Chelsea'),
        _card(club: 'Arsenal'),
        _card(club: 'Arsenal'),
      ];

      await tester.pumpWidget(
        _harness(FitNoteCard(bonuses: [lowReward, highReward], lineup: lineup)),
      );

      final highPos = tester.getTopLeft(find.text('High reward met'));
      final lowPos = tester.getTopLeft(find.text('Low reward met'));
      expect(highPos.dy, lessThan(lowPos.dy));
    });

    testWidgets('among unmet bonuses, closer-to-complete ranks first', (
      tester,
    ) async {
      final almostThere = _sameClub(
        club: 'Chelsea',
        count: 3,
        label: 'Almost there',
        reward: 6,
      );
      final farOff = _sameClub(
        club: 'Arsenal',
        count: 3,
        label: 'Far off',
        reward: 6,
      );
      final lineup = [_card(club: 'Chelsea'), _card(club: 'Chelsea')];

      await tester.pumpWidget(
        _harness(FitNoteCard(bonuses: [farOff, almostThere], lineup: lineup)),
      );

      final closePos = tester.getTopLeft(find.text('Almost there'));
      final farPos = tester.getTopLeft(find.text('Far off'));
      expect(closePos.dy, lessThan(farPos.dy));
    });
  });

  group('FitNoteCard — states', () {
    testWidgets('empty state shown when there are no bonuses', (tester) async {
      await tester.pumpWidget(
        _harness(const FitNoteCard(bonuses: [], lineup: [])),
      );
      expect(
        find.text('No chemistry challenges on this card.'),
        findsOneWidget,
      );
    });

    testWidgets('loading state shown when isLoading is true', (tester) async {
      final bonus = _sameClub(
        club: 'Chelsea',
        count: 2,
        label: 'Field 2 Chelsea players',
        reward: 2,
      );
      await tester.pumpWidget(
        _harness(
          FitNoteCard(bonuses: [bonus], lineup: const [], isLoading: true),
        ),
      );
      expect(_bySemanticsLabel('Loading tactical fit'), findsOneWidget);
      expect(find.text('Field 2 Chelsea players'), findsNothing);
    });
  });

  group('FitNoteCard — exemption', () {
    testWidgets('Icons/Heroes owner club treats every bonus as satisfied', (
      tester,
    ) async {
      final unmet = _sameClub(
        club: 'Arsenal',
        count: 3,
        label: 'Field 3 Arsenal players',
        reward: 6,
      );
      await tester.pumpWidget(
        _harness(
          FitNoteCard(bonuses: [unmet], lineup: const [], ownerClub: 'Icons'),
        ),
      );

      expect(
        _bySemanticsLabel('Field 3 Arsenal players. Met. Worth 6 points.'),
        findsOneWidget,
      );
      expect(find.text('0 of 3 so far'), findsNothing);
    });
  });

  group('FitNoteCard — semantics', () {
    testWidgets('row exposes label with status and reward', (tester) async {
      final met = _sameClub(
        club: 'Chelsea',
        count: 2,
        label: 'Field 2 Chelsea players',
        reward: 2,
      );
      final lineup = [_card(club: 'Chelsea'), _card(club: 'Chelsea')];

      await tester.pumpWidget(
        _harness(FitNoteCard(bonuses: [met], lineup: lineup)),
      );

      expect(
        _bySemanticsLabel('Field 2 Chelsea players. Met. Worth 2 points.'),
        findsOneWidget,
      );
    });

    testWidgets('container exposes an overall met-count summary', (
      tester,
    ) async {
      final met = _sameClub(
        club: 'Chelsea',
        count: 2,
        label: 'Met one',
        reward: 2,
      );
      final unmet = _sameClub(
        club: 'Arsenal',
        count: 3,
        label: 'Unmet one',
        reward: 6,
      );
      final lineup = [_card(club: 'Chelsea'), _card(club: 'Chelsea')];

      await tester.pumpWidget(
        _harness(FitNoteCard(bonuses: [met, unmet], lineup: lineup)),
      );

      expect(
        _bySemanticsLabel('Tactical fit: 1 of 2 challenges met'),
        findsOneWidget,
      );
    });
  });
}
