import '../models/tournament_models.dart';

/// Single source of truth for "what phase is this match really in" — shared
/// by the compact match-card header and the full details panel so the two
/// can never contradict each other.
///
/// Reflects only phases the simulation engine actually produces: regulation
/// time (minutes 1–90, split into two on-screen halves at the 45' mark) and,
/// only when the score is level after 90', a penalty shootout (kicks are
/// delivered as `penalty_scored`/`penalty_missed` events with a sortable
/// marker minute of 120+kick-number, never a real elapsed minute). The
/// engine has no extra-time phase — a level match goes straight to
/// penalties — so no ET/AET state is fabricated here.
class MatchPhaseInfo {
  const MatchPhaseInfo(this.label, {this.minuteText});

  /// Short phase label, e.g. "1H", "2H", "Pens", "FT", "FT · Pens".
  final String label;

  /// Optional trailing minute/marker/tally text, e.g. "62'", "3–2".
  final String? minuteText;

  /// The combined compact string, e.g. "1H · 62'" or "Pens · 3–2".
  String get compact => minuteText != null ? '$label · $minuteText' : label;
}

bool isPenaltyShootoutEvent(LiveMatchEvent e) =>
    e.type == 'penalty_scored' || e.type == 'penalty_missed';

/// A penalty shootout's tally and per-team kick sequence, computed only from
/// real `penalty_scored`/`penalty_missed` events — never a fabricated or
/// assumed kick count. Kicks alternate strictly A/B/A/B… per the simulation
/// engine (`GameService._runPenaltyShootout`), so grouping by
/// `teamParticipantId` and preserving arrival order reconstructs each side's
/// own sequence exactly.
class PenaltyShootoutTally {
  const PenaltyShootoutTally({
    required this.scoreA,
    required this.scoreB,
    required this.kicksA,
    required this.kicksB,
  });

  static const empty = PenaltyShootoutTally(
    scoreA: 0,
    scoreB: 0,
    kicksA: [],
    kicksB: [],
  );

  final int scoreA;
  final int scoreB;

  /// Chronological scored (true) / missed (false) flags for this side's own
  /// kicks only — sudden death is open-ended, so this is never padded to a
  /// fixed length.
  final List<bool> kicksA;
  final List<bool> kicksB;

  bool get hasStarted => kicksA.isNotEmpty || kicksB.isNotEmpty;
}

/// Reconstructs the shootout tally from the real event stream — the single
/// source of truth for both the live "Pens · 3–2" header text and the
/// kick-by-kick dot strip on the match card.
PenaltyShootoutTally computeShootoutTally({
  required List<LiveMatchEvent> liveEvents,
  required String participantAId,
  required String participantBId,
}) {
  final kicksA = <bool>[];
  final kicksB = <bool>[];
  for (final e in liveEvents) {
    if (!isPenaltyShootoutEvent(e)) continue;
    final scored = e.type == 'penalty_scored';
    if (e.teamParticipantId == participantAId) {
      kicksA.add(scored);
    } else if (e.teamParticipantId == participantBId) {
      kicksB.add(scored);
    }
  }
  if (kicksA.isEmpty && kicksB.isEmpty) return PenaltyShootoutTally.empty;
  return PenaltyShootoutTally(
    scoreA: kicksA.where((s) => s).length,
    scoreB: kicksB.where((s) => s).length,
    kicksA: kicksA,
    kicksB: kicksB,
  );
}

/// Computes the real match phase for a match card/details panel.
///
/// - `status == 'complete'`: "FT", or "FT · Pens 4–3" when the result was
///   decided by a shootout (`completedResult.wasDecidedByPenalties`).
/// - `status == 'simulating'`, no events yet: bare "LIVE" (kickoff pending).
/// - `status == 'simulating'`, last event is a shootout kick: "Pens · 3–2" —
///   the live tally, so the header visibly progresses with every kick
///   instead of showing an unchanging "Live" the whole shootout.
/// - `status == 'simulating'`, last event is a regulation event: "1H"/"2H"
///   (split at the 45' mark) with the real minute.
/// - Any other status (e.g. `ready_check`, `pending`): an empty label —
///   callers show their own status wording for those.
MatchPhaseInfo computeMatchPhase({
  required MatchSnapshot match,
  required List<LiveMatchEvent> liveEvents,
  TournamentMatchResult? completedResult,
}) {
  if (match.status == 'complete') {
    final decided = completedResult?.wasDecidedByPenalties ?? false;
    if (!decided) return const MatchPhaseInfo('FT');
    final penA = completedResult!.penaltyScoreA;
    final penB = completedResult.penaltyScoreB;
    return MatchPhaseInfo('FT · Pens', minuteText: '$penA–$penB');
  }
  if (match.status != 'simulating') return const MatchPhaseInfo('');
  if (liveEvents.isEmpty) return const MatchPhaseInfo('LIVE');

  final last = liveEvents.last;
  if (isPenaltyShootoutEvent(last)) {
    final tally = computeShootoutTally(
      liveEvents: liveEvents,
      participantAId: match.participantA.participantId,
      participantBId: match.participantB.participantId,
    );
    return MatchPhaseInfo(
      'Pens',
      minuteText: '${tally.scoreA}–${tally.scoreB}',
    );
  }
  final half = last.minute <= 45 ? '1H' : '2H';
  return MatchPhaseInfo(half, minuteText: "${last.minute}'");
}
