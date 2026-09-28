import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/widgets/team_chemistry_summary.dart';

PitchSlot _filled({
  required int index,
  required String label,
  String? club,
  String? league,
  String? nationality,
}) => PitchSlot(
  index: index,
  label: label,
  basePositionType: 'DEF',
  cardPlayerName: 'Player $index',
  cardRating: 80,
  cardId: 'card-$index',
  cardNaturalPositions: const ['CB'],
  cardClub: club,
  cardLeague: league,
  cardNationality: nationality,
);

List<PitchSlot> _clubTrio() => [
  for (var i = 0; i < 3; i++)
    _filled(index: i, label: ['CB', 'RB', 'LB'][i], club: 'Arsenal'),
];

Future<void> _pump(
  WidgetTester tester, {
  required List<PitchSlot> slots,
  required int total,
  double width = 360,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: TeamChemistrySummary(slots: slots, total: total),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('status word banding (presentation only)', () {
    // These bands never feed a score — they only choose which word prints
    // beside the server-computed total.
    test('maps totals to the three status words', () {
      expect(ChemistryStatus.forTotal(0), ChemistryStatus.needsWork);
      expect(ChemistryStatus.forTotal(9), ChemistryStatus.needsWork);
      expect(ChemistryStatus.forTotal(10), ChemistryStatus.balanced);
      expect(ChemistryStatus.forTotal(23), ChemistryStatus.balanced);
      expect(ChemistryStatus.forTotal(24), ChemistryStatus.strong);
      expect(ChemistryStatus.forTotal(99), ChemistryStatus.strong);
    });
  });

  testWidgets('shows the server-provided total and its status word', (
    tester,
  ) async {
    await _pump(tester, slots: _clubTrio(), total: 26);

    expect(find.text('26'), findsOneWidget);
    expect(find.text('Strong'), findsOneWidget);
    expect(find.text('TEAM CHEMISTRY'), findsOneWidget);
  });

  testWidgets('renders a chip per link type with C / L / N letter markers', (
    tester,
  ) async {
    await _pump(tester, slots: _clubTrio(), total: 12);

    // Letter markers — the non-colour signal, always present for all three
    // types so meaning never depends on colour alone.
    expect(find.text('C'), findsOneWidget);
    expect(find.text('L'), findsOneWidget);
    expect(find.text('N'), findsOneWidget);

    // The club trio is the only group, so club counts 3 and the others zero.
    expect(find.text('CLUB ×3'), findsOneWidget);
    expect(find.text('LEAGUE ×0'), findsOneWidget);
    expect(find.text('NATION ×0'), findsOneWidget);
  });

  testWidgets('"Why?" opens readable per-group details naming the players', (
    tester,
  ) async {
    await _pump(tester, slots: _clubTrio(), total: 12);

    expect(find.text('Why?'), findsOneWidget);
    await tester.tap(find.text('Why?'));
    await tester.pumpAndSettle();

    // The information the old aura encoded geometrically, now as text.
    expect(find.text('Arsenal'), findsOneWidget);
    expect(find.textContaining('Player 0'), findsOneWidget);
  });

  testWidgets('with no qualifying groups it still reads clearly and hides Why?',
      (tester) async {
    await _pump(
      tester,
      slots: [
        _filled(index: 0, label: 'CB', club: 'Arsenal'),
        _filled(index: 1, label: 'RB', club: 'Chelsea'),
      ],
      total: 0,
    );

    expect(find.text('0'), findsOneWidget);
    expect(find.text('Needs Work'), findsOneWidget);
    expect(find.text('CLUB ×0'), findsOneWidget);
    // Nothing to explain, so no affordance is offered.
    expect(find.text('Why?'), findsNothing);
  });

  testWidgets('announces total, status and link counts to screen readers', (
    tester,
  ) async {
    await _pump(tester, slots: _clubTrio(), total: 26);

    final semantics = tester.getSemantics(find.byType(TeamChemistrySummary));
    expect(semantics.label, contains('Team chemistry 26 points'));
    expect(semantics.label, contains('Strong'));
    expect(semantics.label, contains('CLUB 3 linked'));
  });

  testWidgets('does not overflow at narrow mobile width (360px and 270px)', (
    tester,
  ) async {
    for (final width in <double>[360, 270]) {
      await _pump(tester, slots: _clubTrio(), total: 26, width: width);
      expect(tester.takeException(), isNull, reason: 'overflow at ${width}px');
    }
  });
}
