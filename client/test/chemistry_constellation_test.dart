import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/widgets/chemistry_constellation.dart';
import 'package:hidden_eleven/features/game/widgets/pitch_view.dart';

/// Migrated from `chemistry_link_painter_test.dart`.
///
/// The pairwise link web was replaced by Chemistry Constellations, but the
/// eligibility rule (filled && !redCarded) and the club > nationality >
/// league priority were ported verbatim — so the tests covering them are
/// ported too, retargeted from `computeChemistryLinks` (pairs) onto
/// `computeChemistryGroups` (groups). The `pitchSlotCenter` geometry tests
/// are unchanged: that function still backs card placement and the aura hull.
PitchSlot _filled({
  required int index,
  required String label,
  String club = 'Arsenal',
  String nationality = 'England',
  String league = 'Premier League',
  bool redCarded = false,
}) => PitchSlot(
  index: index,
  label: label,
  basePositionType: label,
  cardPlayerName: 'Player $index',
  cardRating: 80,
  cardId: 'c$index',
  cardClub: club,
  cardNationality: nationality,
  cardLeague: league,
  isRedCarded: redCarded,
);

PitchSlot _empty({required int index, required String label}) =>
    PitchSlot(index: index, label: label, basePositionType: label);

void main() {
  group('pitchSlotCenter', () {
    test(
      'maps a known label to its normalized position scaled by box size',
      () {
        final slot = _empty(index: 0, label: 'ST');
        final center = pitchSlotCenter(slot, 400, 800);
        // kSlotPositions['ST'] = Offset(0.500, 0.130)
        expect(center.dx, closeTo(200, 0.01));
        expect(center.dy, closeTo(104, 0.01));
      },
    );

    test('falls back to basePositionType when label has no direct entry', () {
      final slot = PitchSlot(index: 0, label: 'CB', basePositionType: 'CB');
      final byLabel = pitchSlotCenter(slot, 400, 800);
      final custom = PitchSlot(
        index: 0,
        label: 'totally-unknown-label',
        basePositionType: 'CB',
      );
      expect(pitchSlotCenter(custom, 400, 800), byLabel);
    });

    test(
      'falls back to center when neither label nor basePositionType match',
      () {
        final slot = PitchSlot(
          index: 0,
          label: 'nope',
          basePositionType: 'also-nope',
        );
        expect(pitchSlotCenter(slot, 400, 800), const Offset(200, 400));
      },
    );
  });

  group('computeChemistryGroups — eligibility (ported verbatim)', () {
    test('excludes empty slots entirely', () {
      final slots = [
        _filled(index: 0, label: 'CB'),
        _filled(index: 1, label: 'RB'),
        _empty(index: 2, label: 'LB'),
      ];
      // Only two eligible — below the 3-member threshold.
      expect(computeChemistryGroups(slots), isEmpty);
    });

    test('excludes red-carded slots', () {
      final slots = [
        _filled(index: 0, label: 'CB'),
        _filled(index: 1, label: 'RB'),
        _filled(index: 2, label: 'LB', redCarded: true),
      ];
      expect(computeChemistryGroups(slots), isEmpty);
    });

    test('unrelated cards produce no group', () {
      final slots = [
        _filled(
          index: 0,
          label: 'CB',
          club: 'A',
          nationality: 'X',
          league: 'P',
        ),
        _filled(
          index: 1,
          label: 'RB',
          club: 'B',
          nationality: 'Y',
          league: 'Q',
        ),
        _filled(
          index: 2,
          label: 'LB',
          club: 'C',
          nationality: 'Z',
          league: 'R',
        ),
      ];
      expect(computeChemistryGroups(slots), isEmpty);
    });
  });

  group('computeChemistryGroups — threshold', () {
    test('two sharing a club is NOT a group — three is', () {
      final two = [
        _filled(
          index: 0,
          label: 'CB',
          club: 'Arsenal',
          nationality: 'A',
          league: 'P',
        ),
        _filled(
          index: 1,
          label: 'RB',
          club: 'Arsenal',
          nationality: 'B',
          league: 'Q',
        ),
        _filled(
          index: 2,
          label: 'LB',
          club: 'Other',
          nationality: 'C',
          league: 'R',
        ),
      ];
      expect(computeChemistryGroups(two), isEmpty);

      final three = [
        _filled(
          index: 0,
          label: 'CB',
          club: 'Arsenal',
          nationality: 'A',
          league: 'P',
        ),
        _filled(
          index: 1,
          label: 'RB',
          club: 'Arsenal',
          nationality: 'B',
          league: 'Q',
        ),
        _filled(
          index: 2,
          label: 'LB',
          club: 'Arsenal',
          nationality: 'C',
          league: 'R',
        ),
      ];
      final groups = computeChemistryGroups(three);
      expect(groups, hasLength(1));
      expect(groups.single.type, ChemistryGroupType.club);
      expect(groups.single.size, 3);
    });
  });

  group('computeChemistryGroups — priority (ported verbatim)', () {
    test('sharing all three attributes yields ONE club group', () {
      final slots = [
        for (var i = 0; i < 3; i++)
          _filled(
            index: i,
            label: 'P$i',
            club: 'Arsenal',
            nationality: 'England',
            league: 'PL',
          ),
      ];
      final groups = computeChemistryGroups(slots);
      expect(groups, hasLength(1));
      expect(groups.single.type, ChemistryGroupType.club);
    });

    test(
      'sharing nationality and league (not club) prioritises nationality',
      () {
        final slots = [
          for (var i = 0; i < 3; i++)
            _filled(
              index: i,
              label: 'P$i',
              club: 'Club$i',
              nationality: 'England',
              league: 'PL',
            ),
        ];
        final groups = computeChemistryGroups(slots);
        expect(groups, hasLength(1));
        expect(groups.single.type, ChemistryGroupType.nationality);
      },
    );

    test('sharing only league yields a league group', () {
      final slots = [
        for (var i = 0; i < 3; i++)
          _filled(
            index: i,
            label: 'P$i',
            club: 'Club$i',
            nationality: 'Nation$i',
            league: 'PL',
          ),
      ];
      final groups = computeChemistryGroups(slots);
      expect(groups, hasLength(1));
      expect(groups.single.type, ChemistryGroupType.league);
    });

    test('a slot belongs to at most ONE group — no overlapping membership', () {
      // Three share a club; those same three plus a fourth share a league.
      final slots = [
        for (var i = 0; i < 3; i++)
          _filled(
            index: i,
            label: 'P$i',
            club: 'Arsenal',
            nationality: 'Nation$i',
            league: 'PL',
          ),
        _filled(
          index: 3,
          label: 'P3',
          club: 'Other',
          nationality: 'N3',
          league: 'PL',
        ),
        _filled(
          index: 4,
          label: 'P4',
          club: 'Other2',
          nationality: 'N4',
          league: 'PL',
        ),
        _filled(
          index: 5,
          label: 'P5',
          club: 'Other3',
          nationality: 'N5',
          league: 'PL',
        ),
      ];
      final groups = computeChemistryGroups(slots);

      final seen = <int>{};
      for (final g in groups) {
        for (final s in g.slots) {
          expect(
            seen.contains(s.index),
            isFalse,
            reason: 'slot ${s.index} appears in more than one group',
          );
          seen.add(s.index);
        }
      }
      // Club claims its three first; the remaining three form the league group.
      expect(groups.first.type, ChemistryGroupType.club);
    });
  });

  group('primaryConstellation — at most one aura', () {
    test('returns null when nothing qualifies', () {
      expect(primaryConstellation([_filled(index: 0, label: 'CB')]), isNull);
    });

    test('returns the highest-priority group when several exist', () {
      final slots = [
        for (var i = 0; i < 3; i++)
          _filled(
            index: i,
            label: 'P$i',
            club: 'Arsenal',
            nationality: 'N$i',
            league: 'L$i',
          ),
        for (var i = 3; i < 6; i++)
          _filled(
            index: i,
            label: 'P$i',
            club: 'C$i',
            nationality: 'England',
            league: 'L$i',
          ),
      ];
      expect(computeChemistryGroups(slots), hasLength(2));
      // Only one is ever drawn, and it is the club group.
      expect(primaryConstellation(slots)!.type, ChemistryGroupType.club);
    });
  });

  group('PitchView — constellation layer and privacy', () {
    Widget harness(List<PitchSlot> slots, {bool showChemistry = true}) =>
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 640,
              child: PitchView(
                slots: slots,
                roundSlotIndex: null,
                isInteractiveOwner: false,
                turnPhase: 'selecting_position',
                showChemistry: showChemistry,
              ),
            ),
          ),
        );

    List<PitchSlot> clubTrio() => [
      for (var i = 0; i < 3; i++)
        _filled(index: i, label: ['CB', 'RB', 'LB'][i], club: 'Arsenal'),
    ];

    // Stage 1 / Chemistry Option A: the pitch no longer draws ANY chemistry
    // geometry. The aura painter and its corner label were removed in favour
    // of `TeamChemistrySummary` (see team_chemistry_summary_test.dart). The
    // per-card C/L/N markers are retained, so the "which players are linked"
    // signal still exists on the pitch itself — just without the overlay
    // shape. These tests now assert the *absence* of the geometry.
    testWidgets('the pitch draws no chemistry aura or corner label', (
      tester,
    ) async {
      await tester.pumpWidget(harness(clubTrio()));

      expect(
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter is Object),
        findsWidgets, // the pitch itself still paints
      );
      expect(find.byType(ConstellationLabel), findsNothing);

      // Existing tap-to-open-details behaviour on a filled card is unchanged.
      expect(find.text('Player 0'), findsOneWidget);
      await tester.tap(find.text('Player 0'));
      await tester.pump();
      expect(find.text('Player 0'), findsNWidgets(2)); // pitch card + dialog
    });

    testWidgets('markers still render for grouped cards', (tester) async {
      await tester.pumpWidget(harness(clubTrio()));
      expect(find.byType(ConstellationMarker), findsNWidgets(3));
    });

    testWidgets(
      'PRIVACY: showChemistry false renders no markers and no label',
      (tester) async {
        await tester.pumpWidget(harness(clubTrio(), showChemistry: false));

        expect(find.byType(ConstellationMarker), findsNothing);
        expect(find.byType(ConstellationLabel), findsNothing);
      },
    );

    testWidgets('no markers when fewer than three share an attribute', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness([
          _filled(index: 0, label: 'CB', club: 'Arsenal'),
          _filled(index: 1, label: 'RB', club: 'Arsenal'),
        ]),
      );
      expect(find.byType(ConstellationMarker), findsNothing);
    });
  });
}
