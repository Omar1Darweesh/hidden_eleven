import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/tournament/models/tournament_models.dart';
import 'package:hidden_eleven/features/tournament/widgets/match_phase.dart';

ParticipantSnapshot _participant(String id, String name) => ParticipantSnapshot(
  participantId: id,
  kind: TournamentParticipantKind.real,
  displayName: name,
  overallRating: 80,
);

MatchSnapshot _match({
  required String status,
  CompletedMatchSnapshot? result,
}) => MatchSnapshot(
  matchId: 'm1',
  roundNumber: 1,
  participantA: _participant('a', 'Team A'),
  participantB: _participant('b', 'Team B'),
  status: status,
  result: result,
  winnerId: null,
);

LiveMatchEvent _event({
  required int minute,
  required String type,
  String teamParticipantId = 'a',
}) => LiveMatchEvent(
  matchId: 'm1',
  roundNumber: 1,
  minute: minute,
  type: type,
  teamParticipantId: teamParticipantId,
  playerName: 'Player',
  playerRating: 7.0,
  currentScoreA: 1,
  currentScoreB: 1,
);

void main() {
  group('computeMatchPhase', () {
    test('simulating with no events yet is a bare LIVE', () {
      final phase = computeMatchPhase(
        match: _match(status: 'simulating'),
        liveEvents: const [],
      );
      expect(phase.compact, 'LIVE');
    });

    test('first-half regulation event → 1H with real minute', () {
      final phase = computeMatchPhase(
        match: _match(status: 'simulating'),
        liveEvents: [_event(minute: 30, type: 'goal')],
      );
      expect(phase.compact, "1H · 30'");
    });

    test('second-half regulation event → 2H with real minute', () {
      final phase = computeMatchPhase(
        match: _match(status: 'simulating'),
        liveEvents: [_event(minute: 67, type: 'goal')],
      );
      expect(phase.compact, "2H · 67'");
    });

    test('minute 45 is still 1H, minute 46 is already 2H (boundary)', () {
      expect(
        computeMatchPhase(
          match: _match(status: 'simulating'),
          liveEvents: [_event(minute: 45, type: 'goal')],
        ).label,
        '1H',
      );
      expect(
        computeMatchPhase(
          match: _match(status: 'simulating'),
          liveEvents: [_event(minute: 46, type: 'goal')],
        ).label,
        '2H',
      );
    });

    test(
      'a penalty-shootout kick shows the LIVE tally, not a raw 120+ marker '
      '(the reported "LIVE · 128\'" bug) and updates kick to kick — the '
      'header must never look stuck at a single unchanging "Pens · Live"',
      () {
        final match = _match(status: 'simulating');

        final afterKick1 = computeMatchPhase(
          match: match,
          liveEvents: [
            _event(minute: 40, type: 'goal'),
            _event(minute: 121, type: 'penalty_scored', teamParticipantId: 'a'),
          ],
        );
        expect(afterKick1.compact, 'Pens · 1–0');
        expect(afterKick1.compact.contains('121'), isFalse);

        final afterKick2 = computeMatchPhase(
          match: match,
          liveEvents: [
            _event(minute: 40, type: 'goal'),
            _event(minute: 121, type: 'penalty_scored', teamParticipantId: 'a'),
            _event(minute: 122, type: 'penalty_scored', teamParticipantId: 'b'),
          ],
        );
        expect(afterKick2.compact, 'Pens · 1–1');

        // The header text actually changed between kicks — proves it is
        // reflecting live progress, not frozen on the same string.
        expect(afterKick1.compact, isNot(afterKick2.compact));
      },
    );

    test(
      'penalty_missed also counts as a shootout event but does not add to the tally',
      () {
        final phase = computeMatchPhase(
          match: _match(status: 'simulating'),
          liveEvents: [_event(minute: 122, type: 'penalty_missed')],
        );
        expect(phase.compact, 'Pens · 0–0');
      },
    );

    test('completed, decided in regulation → plain FT', () {
      final result = TournamentMatchResult(
        matchId: 'm1',
        roundNumber: 1,
        scoreA: 2,
        scoreB: 1,
        winnerId: 'a',
        explanation: 'a won 2-1',
        playerRatings: const {},
      );
      final phase = computeMatchPhase(
        match: _match(status: 'complete'),
        liveEvents: const [],
        completedResult: result,
      );
      expect(phase.compact, 'FT');
    });

    test(
      'completed and decided on penalties → FT · Pens with the final tally',
      () {
        final result = TournamentMatchResult(
          matchId: 'm1',
          roundNumber: 1,
          scoreA: 1,
          scoreB: 1,
          winnerId: 'a',
          penaltyScoreA: 4,
          penaltyScoreB: 3,
          explanation: 'a won on penalties',
          playerRatings: const {},
        );
        final phase = computeMatchPhase(
          match: _match(status: 'complete'),
          liveEvents: const [],
          completedResult: result,
        );
        expect(phase.compact, 'FT · Pens · 4–3');
        expect(phase.label, 'FT · Pens');
        expect(phase.minuteText, '4–3');
      },
    );

    test(
      'a non-simulating, non-complete status (e.g. ready_check) has no phase label',
      () {
        final phase = computeMatchPhase(
          match: _match(status: 'ready_check'),
          liveEvents: const [],
        );
        expect(phase.label, '');
        expect(phase.minuteText, isNull);
      },
    );
  });

  group('computeShootoutTally', () {
    test('empty when no shootout has happened', () {
      final tally = computeShootoutTally(
        liveEvents: [_event(minute: 30, type: 'goal')],
        participantAId: 'a',
        participantBId: 'b',
      );
      expect(tally.hasStarted, isFalse);
      expect(tally.scoreA, 0);
      expect(tally.scoreB, 0);
    });

    test('maps scored/missed kicks to the correct side, preserving order', () {
      final tally = computeShootoutTally(
        liveEvents: [
          _event(minute: 121, type: 'penalty_scored', teamParticipantId: 'a'),
          _event(minute: 122, type: 'penalty_missed', teamParticipantId: 'b'),
          _event(minute: 123, type: 'penalty_scored', teamParticipantId: 'a'),
          _event(minute: 124, type: 'penalty_scored', teamParticipantId: 'b'),
        ],
        participantAId: 'a',
        participantBId: 'b',
      );
      expect(tally.hasStarted, isTrue);
      expect(tally.kicksA, [true, true]);
      expect(tally.kicksB, [false, true]);
      expect(tally.scoreA, 2);
      expect(tally.scoreB, 1);
    });

    test(
      'ignores regulation goal events entirely (never conflates a goal with a penalty kick)',
      () {
        final tally = computeShootoutTally(
          liveEvents: [
            _event(minute: 10, type: 'goal', teamParticipantId: 'a'),
            _event(minute: 121, type: 'penalty_scored', teamParticipantId: 'a'),
          ],
          participantAId: 'a',
          participantBId: 'b',
        );
        expect(tally.kicksA, [true]);
        expect(tally.scoreA, 1);
      },
    );
  });
}
