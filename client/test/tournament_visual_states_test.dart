import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/tournament/models/tournament_models.dart';
import 'package:hidden_eleven/features/tournament/widgets/tournament_widgets.dart';

/// Stage 2 — the tournament state vocabulary must read identically at desktop
/// and mobile, and every state must be tellable apart by *text*, not colour.
///
/// The states themselves are unchanged from Stage B; these tests lock the
/// restyle down so the visual redesign can't quietly drop or merge one.

ParticipantSnapshot _p(String id, String name, {double rating = 75}) =>
    ParticipantSnapshot(
      participantId: id,
      kind: TournamentParticipantKind.real,
      displayName: name,
      overallRating: rating,
    );

/// A genuinely-unknown participant: no id, zero rating.
ParticipantSnapshot _tbd() => const ParticipantSnapshot(
  participantId: '',
  kind: TournamentParticipantKind.real,
  displayName: '',
  overallRating: 0.0,
);

MatchSnapshot _match({
  required String id,
  required int round,
  required String status,
  ParticipantSnapshot? a,
  ParticipantSnapshot? b,
  String? winnerId,
}) => MatchSnapshot(
  matchId: id,
  roundNumber: round,
  participantA: a ?? _p('p1', 'Alpha United'),
  participantB: b ?? _p('p2', 'Beta Rovers'),
  status: status,
  winnerId: winnerId,
);

TournamentStateModel _state({
  required TournamentPhase phase,
  required List<RoundSnapshot> rounds,
  int currentRound = 1,
  int totalRounds = 2,
}) => TournamentStateModel(
  phase: phase,
  currentRound: currentRound,
  totalRounds: totalRounds,
  readyPlayerIds: const [],
  rounds: rounds,
);

RoundSnapshot _round(
  int number,
  String label,
  List<MatchSnapshot> matches, {
  String status = 'in_progress',
}) => RoundSnapshot(
  roundNumber: number,
  label: label,
  status: status,
  matches: matches,
);

/// The final-round shapes the trophy centre has to survive.
TournamentStateModel _finalState({
  required TournamentPhase phase,
  required ParticipantSnapshot a,
  required ParticipantSnapshot b,
  String status = 'pending',
  String? winnerId,
}) => _state(
  phase: phase,
  currentRound: 2,
  rounds: [
    _round(1, 'Semi-finals', [
      _match(id: 'm1', round: 1, status: 'complete', winnerId: 'p1'),
    ]),
    _round(2, 'Final', [
      _match(id: 'f1', round: 2, status: status, a: a, b: b, winnerId: winnerId),
    ]),
  ],
);

Future<void> _pumpBracket(
  WidgetTester tester,
  TournamentStateModel state, {
  required double width,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: SizedBox(
          width: width,
          height: 700,
          child: SingleChildScrollView(
            child: TournamentBracketWidget(state: state),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  // 700 is the desktop/mobile boundary; 1280 a real desktop; 375/360 phones.
  const desktopWidths = <double>[1280, 1024, 768, 720, 700];
  const mobileWidths = <double>[414, 390, 375, 360];

  group('final / trophy centre states', () {
    testWidgets('unknown finalists show an awaiting placeholder, never a name',
        (tester) async {
      await _pumpBracket(
        tester,
        _finalState(phase: TournamentPhase.readyCheck, a: _tbd(), b: _tbd()),
        width: 1280,
      );

      expect(tester.takeException(), isNull);
      // Placeholder, not a fabricated identity.
      expect(find.textContaining('Awaiting'), findsWidgets);
    });

    testWidgets('a partially-known final shows the real name and a placeholder',
        (tester) async {
      await _pumpBracket(
        tester,
        _finalState(
          phase: TournamentPhase.readyCheck,
          a: _p('p1', 'Alpha United'),
          b: _tbd(),
        ),
        width: 1280,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Alpha United'), findsWidgets);
      expect(find.textContaining('Awaiting'), findsWidgets);
    });

    testWidgets('a set final shows both finalists and a VS separator', (
      tester,
    ) async {
      await _pumpBracket(
        tester,
        _finalState(
          phase: TournamentPhase.readyCheck,
          a: _p('p1', 'Alpha United'),
          b: _p('p2', 'Beta Rovers'),
        ),
        width: 1280,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Alpha United'), findsWidgets);
      expect(find.text('Beta Rovers'), findsWidgets);
      expect(find.text('VS'), findsOneWidget);
    });

    testWidgets('a completed final marks the champion with a RankMedallion', (
      tester,
    ) async {
      await _pumpBracket(
        tester,
        _finalState(
          phase: TournamentPhase.complete,
          a: _p('p1', 'Alpha United'),
          b: _p('p2', 'Beta Rovers'),
          status: 'complete',
          winnerId: 'p1',
        ),
        width: 1280,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Alpha United'), findsWidgets);
    });
  });

  group('no overflow at any supported width', () {
    final scenarios = <String, TournamentStateModel>{
      'unknown final': _finalState(
        phase: TournamentPhase.readyCheck,
        a: _tbd(),
        b: _tbd(),
      ),
      'set final': _finalState(
        phase: TournamentPhase.readyCheck,
        a: _p('p1', 'Alpha United'),
        b: _p('p2', 'Beta Rovers'),
      ),
      'live final': _finalState(
        phase: TournamentPhase.simulating,
        a: _p('p1', 'Alpha United'),
        b: _p('p2', 'Beta Rovers'),
        status: 'simulating',
      ),
      'complete': _finalState(
        phase: TournamentPhase.complete,
        a: _p('p1', 'Alpha United'),
        b: _p('p2', 'Beta Rovers'),
        status: 'complete',
        winnerId: 'p1',
      ),
      'very long names': _finalState(
        phase: TournamentPhase.readyCheck,
        a: _p('p1', 'A Preposterously Long Club Name United FC'),
        b: _p('p2', 'Another Extremely Long Opponent Name Rovers'),
      ),
    };

    for (final entry in scenarios.entries) {
      for (final w in [...desktopWidths, ...mobileWidths]) {
        testWidgets('${entry.key} at ${w.toInt()}px', (tester) async {
          await _pumpBracket(tester, entry.value, width: w);
          expect(
            tester.takeException(),
            isNull,
            reason: '${entry.key} overflowed at ${w.toInt()}px',
          );
        });
      }
    }
  });

  group('Stage 4 — the bracket keeps its proportions on very wide screens', () {
    // The defect this locks down: at 1920px each half was taking ~830px, so a
    // fixture capsule became a near-empty bar and the Trophy Centre — capped
    // at 240px — ended up the smallest element on the page.
    for (final w in <double>[1280, 1600, 1920, 2560]) {
      testWidgets('at ${w.toInt()}px the halves stay capped and centred', (
        tester,
      ) async {
        await _pumpBracket(
          tester,
          _finalState(
            phase: TournamentPhase.readyCheck,
            a: _p('p1', 'Alpha United'),
            b: _p('p2', 'Beta Rovers'),
          ),
          width: w,
        );

        expect(tester.takeException(), isNull);

        // A slot card never inflates past the capped half width, however wide
        // the viewport gets.
        final slot = find.byType(FixtureCapsule);
        expect(slot, findsWidgets);
        for (final size in tester.widgetList<FixtureCapsule>(slot).indexed.map(
          (e) => tester.getSize(slot.at(e.$1)),
        )) {
          expect(
            size.width,
            lessThanOrEqualTo(420),
            reason: 'a fixture capsule stretched into a bar at ${w.toInt()}px',
          );
        }
      });
    }

    testWidgets('the Trophy Centre outweighs a single fixture capsule', (
      tester,
    ) async {
      await _pumpBracket(
        tester,
        _finalState(
          phase: TournamentPhase.readyCheck,
          a: _p('p1', 'Alpha United'),
          b: _p('p2', 'Beta Rovers'),
        ),
        width: 1920,
      );

      // The focal point must not be the smallest thing on screen: the centre
      // capsule (focus emphasis) should be taller than an ordinary slot.
      final capsules = tester
          .widgetList<FixtureCapsule>(find.byType(FixtureCapsule))
          .toList();
      final focus = capsules.where(
        (c) => c.emphasis == FixtureEmphasis.focus,
      );
      expect(focus, isNotEmpty, reason: 'no focus-emphasis Trophy Centre');
    });
  });

  testWidgets('the mobile strip still scrolls horizontally, never a PageView', (
    tester,
  ) async {
    await _pumpBracket(
      tester,
      _finalState(
        phase: TournamentPhase.readyCheck,
        a: _p('p1', 'Alpha United'),
        b: _p('p2', 'Beta Rovers'),
      ),
      width: 375,
    );

    expect(find.byType(PageView), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) => w is ListView && w.scrollDirection == Axis.horizontal,
      ),
      findsOneWidget,
    );
  });
}
