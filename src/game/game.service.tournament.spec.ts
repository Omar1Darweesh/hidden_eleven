import { GameService } from './game.service';
import { GameSession, TournamentState } from './interfaces/game-session.interface';
import { PitchSlot, Pitch } from './interfaces/pitch.interface';
import { DraftCard } from './interfaces/draft-card.interface';
import { BasePositionType, SlotLabel } from './interfaces/formation.interface';
import { DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1 } from './tournament-awards-config';

/**
 * Tournament mode (Phase 1) — bracket creation, ready check, phase transitions,
 * and the simulation stub. Sessions are injected directly into the service maps
 * (reaching 'tournament' status via the real flow would require completing a
 * full draft + subs phase). The simulation engine itself is a Phase 1 stub
 * (higher overallRating wins 2–0; equal ratings → participant A on penalties),
 * so the deterministic outcomes asserted below reflect that stub, not a real
 * football model.
 */

const DEF_SLOTS: { label: SlotLabel; base: BasePositionType }[] = [
  { label: 'GK', base: 'GK' },
  { label: 'LB', base: 'LB' },
  { label: 'LCB', base: 'CB' },
  { label: 'RCB', base: 'CB' },
  { label: 'RB', base: 'RB' },
];
const MID_SLOTS: { label: SlotLabel; base: BasePositionType }[] = [
  { label: 'CDM', base: 'CDM' },
  { label: 'CM', base: 'CM' },
  { label: 'CAM', base: 'CAM' },
];
const ATK_SLOTS: { label: SlotLabel; base: BasePositionType }[] = [
  { label: 'LW', base: 'LW' },
  { label: 'RW', base: 'RW' },
  { label: 'ST', base: 'ST' },
];
const FORMATION_SLOTS = [...DEF_SLOTS, ...MID_SLOTS, ...ATK_SLOTS];

function card(cardId: string, base: BasePositionType, rating: number): DraftCard {
  return {
    cardId, playerName: cardId, basePositionType: base, rating,
    pace: rating, shooting: rating, passing: rating, dribbling: rating, defending: rating, physical: rating,
    nationality: 'England', club: 'Test FC', altPositions: [], naturalPositions: [base],
    chemistryBonuses: [],
  };
}

function fullLineup(prefix: string, rating: number): PitchSlot[] {
  return FORMATION_SLOTS.map((s, index) => ({
    index, label: s.label, basePositionType: s.base, card: card(`${prefix}-${s.base}-${index}`, s.base, rating),
  }));
}

function pitch(playerId: string, slots: PitchSlot[]): Pitch {
  return { playerId, slots, filledCount: slots.filter((s) => s.card).length };
}

/**
 * A finished-subs, tournament-enabled session with `count` real players. Each
 * player's lineup is rated distinctly (p1 highest, p2 next, …) so the rating-
 * driven simulation stub produces a deterministic, predictable bracket winner.
 */
function tournamentSession(count: number, overrides: Partial<GameSession> = {}): GameSession {
  const ids = Array.from({ length: count }, (_, i) => `p${i + 1}`);
  const pitches: Record<string, Pitch> = {};
  const userSubs: Record<string, { isComplete: boolean; lineupConfirmed: boolean }> = {};
  ids.forEach((id, i) => {
    // Distinct ratings: p1=90, p2=88, p3=86, … keeps every matchup decisive.
    pitches[id] = pitch(id, fullLineup(id, 90 - i * 2));
    userSubs[id] = { isComplete: true, lineupConfirmed: true };
  });

  return {
    sessionId: 'sess-tourney',
    roomCode: 'TRNMT1',
    createdAt: Date.now(),
    leagues: [],
    playerBonusCache: new Map(),
    userChallengeCache: new Map(),
    formation: {
      name: '4-3-3',
      slug: '4-3-3',
      slots: FORMATION_SLOTS.map((s, index) => ({ index, label: s.label, basePositionType: s.base })),
    } as any,
    players: ids.map((id, i) => ({ id, displayName: id.toUpperCase(), isHost: i === 0, isConnected: true } as any)),
    pitches,
    baseTurnOrder: [...ids],
    currentRound: 12,
    totalRounds: 11,
    currentTurnIndex: 0,
    currentRoundSlotIndex: null,
    draftedCardIds: new Set(),
    roundCandidates: [],
    orderedHiddenDeck: [],
    hiddenPicksTaken: new Set(),
    lastRoundLeftovers: [],
    hiddenPicksMap: new Map(),
    hiddenPickReveal: null,
    turn: { turnId: 't1', phase: 'selecting_position', activePlayerId: 'p1', activeSlotIndex: null, candidates: [], turnStartedAt: null },
    turnTimeoutPolicy: { enabled: false, turnSeconds: null, onExpiry: null },
    status: 'lineup_edit',
    abilityDraft: null,
    playerAbilities: {},
    abilityActivations: [],
    subSwappedCardIds: new Set(),
    isFinished: false,
    subsPhase: { userSubs: userSubs as any },
    subsTimerSeconds: null,
    subsDeadlineAt: null,
    abilityActivationDeadlineAt: null,
    tournamentEnabled: true,
    tournament: null,
    result: null,
    ...overrides,
  } as GameSession;
}

function inject(gameService: GameService, session: GameSession): void {
  (gameService as unknown as { sessions: Map<string, GameSession> }).sessions.set(session.sessionId, session);
  (gameService as unknown as { roomToSession: Map<string, string> }).roomToSession.set(session.roomCode, session.sessionId);
}

/** Marks every match in the current round complete (the gateway normally does
 *  this as it finishes streaming each match's events). */
function completeCurrentRound(t: TournamentState): void {
  const round = t.bracket.rounds[t.currentRound - 1];
  for (const m of round.matches) m.status = 'complete';
}

describe('GameService — computeChemistryScore (Task 3)', () => {
  let gameService: GameService;
  beforeEach(() => { gameService = new GameService(); });

  it('returns a finite numeric chemistry score for a known lineup, with no session side effects', () => {
    const session = tournamentSession(2);
    inject(gameService, session);
    const statusBefore = session.status;

    const score = gameService.computeChemistryScore(session, 'p1');

    expect(typeof score).toBe('number');
    expect(Number.isFinite(score)).toBe(true);
    // Side-effect-free: calling it must not finalize or mutate the session.
    expect(session.status).toBe(statusBefore);
    expect(session.result).toBeNull();
  });
});

describe('GameService — beginTournament (Task 4)', () => {
  let gameService: GameService;
  beforeEach(() => { gameService = new GameService(); });

  it('4 real players → bracket size 4, 0 AI fillers, totalRounds 2', () => {
    const session = tournamentSession(4);
    inject(gameService, session);

    const t = gameService.beginTournament(session.roomCode);

    expect(t.bracket.size).toBe(4);
    expect(t.totalRounds).toBe(2);
    expect(t.phase).toBe('bracket_reveal');
    expect(session.status).toBe('tournament');
    const round1 = t.bracket.rounds[0];
    const allRound1 = round1.matches.flatMap((m) => [m.participantA, m.participantB]);
    expect(allRound1.filter((p) => p.kind === 'ai')).toHaveLength(0);
    expect(round1.matches).toHaveLength(2);
    expect(t.bracket.rounds[1].matches).toHaveLength(1); // final
  });

  it('3 real players → bracket size 4 with exactly 1 AI filler, a real generated club lineup', () => {
    const session = tournamentSession(3);
    inject(gameService, session);

    const t = gameService.beginTournament(session.roomCode);

    expect(t.bracket.size).toBe(4);
    const round1 = t.bracket.rounds[0];
    const all = round1.matches.flatMap((m) => [m.participantA, m.participantB]);
    expect(all.filter((p) => p.kind === 'ai')).toHaveLength(1);
    expect(all.filter((p) => p.kind === 'real')).toHaveLength(3);
    // The AI filler is a real club with a full generated XI, not the old
    // static "AI Club" placeholder with a null lineup.
    const ai = all.find((p) => p.kind === 'ai')!;
    expect(ai.displayName).not.toBe('AI Club');
    expect(ai.lineup).not.toBeNull();
    expect(ai.lineup!.pitchCards).toHaveLength(11);
    expect(ai.lineup!.overallRating).toBeGreaterThan(0);
    expect(ai.lineup!.pitchCards.every((c) => c.club === ai.displayName)).toBe(true);
    expect(ai.participantId).toMatch(/^ai_/);
  });

  it('5 real players → bracket size 8 with exactly 3 AI filler placeholders', () => {
    const session = tournamentSession(5);
    inject(gameService, session);

    const t = gameService.beginTournament(session.roomCode);

    expect(t.bracket.size).toBe(8);
    expect(t.totalRounds).toBe(3);
    const round1 = t.bracket.rounds[0];
    const all = round1.matches.flatMap((m) => [m.participantA, m.participantB]);
    expect(all.filter((p) => p.kind === 'ai')).toHaveLength(3);
    expect(all.filter((p) => p.kind === 'real')).toHaveLength(5);
  });
});

describe('GameService — recordTournamentReady (Task 5)', () => {
  let gameService: GameService;
  beforeEach(() => { gameService = new GameService(); });

  function readySession(): GameSession {
    const session = tournamentSession(4);
    inject(gameService, session);
    gameService.beginTournament(session.roomCode);
    gameService.advanceTournamentPhase(session.roomCode, 'ready_check');
    return session;
  }

  it('first player readying → allReady false', () => {
    const session = readySession();
    // Round 1 of a 4-bracket is p1 vs p2 and p3 vs p4 (join order).
    const res = gameService.recordTournamentReady(session.roomCode, 'p1');
    expect('error' in res).toBe(false);
    if ('error' in res) return;
    expect(res.state.readyPlayerIds).toContain('p1');
    expect(res.allReady).toBe(false);
  });

  it('all four players ready → allReady true', () => {
    const session = readySession();
    gameService.recordTournamentReady(session.roomCode, 'p1');
    gameService.recordTournamentReady(session.roomCode, 'p2');
    gameService.recordTournamentReady(session.roomCode, 'p3');
    const last = gameService.recordTournamentReady(session.roomCode, 'p4');
    if ('error' in last) throw new Error(last.error);
    expect(last.allReady).toBe(true);
  });

  it('double-ready is idempotent (no duplicate id) and not an error', () => {
    const session = readySession();
    gameService.recordTournamentReady(session.roomCode, 'p1');
    const again = gameService.recordTournamentReady(session.roomCode, 'p1');
    if ('error' in again) throw new Error(again.error);
    const count = again.state.readyPlayerIds.filter((id) => id === 'p1').length;
    expect(count).toBe(1);
    expect(again.allReady).toBe(false);
  });

  it('rejects a player who is not in the current round', () => {
    const session = readySession();
    const res = gameService.recordTournamentReady(session.roomCode, 'ghost');
    expect('error' in res && res.error).toBe('TOURNAMENT_NOT_YOUR_ROUND');
  });
});

describe('GameService — autoReadyRemainingPlayers (Task 6)', () => {
  let gameService: GameService;
  beforeEach(() => { gameService = new GameService(); });

  it('readies every remaining real player and clears the deadline', () => {
    const session = tournamentSession(4);
    inject(gameService, session);
    gameService.beginTournament(session.roomCode);
    gameService.advanceTournamentPhase(session.roomCode, 'ready_check');
    gameService.recordTournamentReady(session.roomCode, 'p1');

    const t = gameService.autoReadyRemainingPlayers(session.roomCode);

    for (const id of ['p1', 'p2', 'p3', 'p4']) expect(t.readyPlayerIds).toContain(id);
    expect(t.readyDeadlineAt).toBeNull();
  });
});

/**
 * removePlayer's tournament-phase awareness (Phase 7 audit). Before this
 * fix, removePlayer had NO handling at all for status === 'tournament' — a
 * removed real participant's ready_check id (session.tournament.
 * readyPlayerIds, keyed by the FROZEN bracket's participantId, entirely
 * independent of session.players) could never become ready again, since
 * nobody remains who can act for them. This didn't permanently soft-lock
 * the room the way the equivalent subs-phase gap did (the ready_check
 * phase always has a hardcoded 60s auto-ready timeout, unlike the subs
 * timer which can be left unconfigured), but it needlessly stalled every
 * OTHER real participant in the room for the full 60 seconds on every
 * departure, instead of the round proceeding the instant everyone actually
 * remaining is ready. Read removePlayer's new tournament block in full
 * before writing any of these, not from memory.
 */
describe('GameService — removePlayer tournament-phase awareness (Phase 7)', () => {
  let gameService: GameService;
  beforeEach(() => { gameService = new GameService(); });

  function readySession(count: number): GameSession {
    const session = tournamentSession(count);
    inject(gameService, session);
    gameService.beginTournament(session.roomCode);
    gameService.advanceTournamentPhase(session.roomCode, 'ready_check');
    return session;
  }

  it('removing the LAST unready real participant in the current round auto-readies them and reports tournamentAllReadyAfterRemoval: true', () => {
    const session = readySession(4);
    // Round 1 of a 4-bracket is p1 vs p2, p3 vs p4 (join order) — ready up
    // three of the four, leaving p4 as the sole holdout.
    gameService.recordTournamentReady(session.roomCode, 'p1');
    gameService.recordTournamentReady(session.roomCode, 'p2');
    gameService.recordTournamentReady(session.roomCode, 'p3');

    const result = gameService.removePlayer(session.roomCode, 'p4');

    expect(result).not.toBeNull();
    expect(result!.tournamentAllReadyAfterRemoval).toBe(true);
    expect(session.tournament!.readyPlayerIds).toContain('p4'); // auto-readied, not dropped
    expect(session.status).toBe('tournament'); // removePlayer itself doesn't advance the phase
  });

  it('removing a real participant while OTHERS in the round still haven\'t readied reports tournamentAllReadyAfterRemoval: false — does not falsely complete the round', () => {
    const session = readySession(4);
    // Nobody has readied yet — removing p4 auto-readies only p4; p1/p2/p3
    // (all still real, still-in-room participants) remain unready.
    const result = gameService.removePlayer(session.roomCode, 'p4');

    expect(result).not.toBeNull();
    expect(result!.tournamentAllReadyAfterRemoval).toBe(false);
    expect(session.tournament!.readyPlayerIds).toEqual(['p4']);
  });

  it('removing a player who is NOT a real participant in the CURRENT round leaves tournamentAllReadyAfterRemoval undefined and readyPlayerIds untouched', () => {
    const session = readySession(4);
    // Advance the round counter to round 2 WITHOUT resolving round 1's
    // matches — _buildBracket seeds every round after the first with TBD
    // placeholder participants (empty participantId, not yet a real winner
    // from round 1), so _currentRoundRealParticipantIds(round 2) is
    // deterministically empty regardless of who's asked about — a clean,
    // reliable way to exercise "removed player isn't part of the round
    // currently being waited on" without needing to simulate a real match
    // to determine an actual round-2 winner.
    session.tournament!.currentRound = 2;
    gameService.advanceTournamentPhase(session.roomCode, 'ready_check');

    const result = gameService.removePlayer(session.roomCode, 'p1');

    expect(result).not.toBeNull();
    expect(result!.tournamentAllReadyAfterRemoval).toBeUndefined();
    expect(session.tournament!.readyPlayerIds).toEqual([]);
  });

  it('removing a player when the tournament is NOT in ready_check (e.g. bracket_reveal) leaves tournamentAllReadyAfterRemoval undefined', () => {
    const session = tournamentSession(4);
    inject(gameService, session);
    gameService.beginTournament(session.roomCode); // phase: bracket_reveal, not ready_check

    const result = gameService.removePlayer(session.roomCode, 'p4');

    expect(result).not.toBeNull();
    expect(result!.tournamentAllReadyAfterRemoval).toBeUndefined();
    expect(session.tournament!.readyPlayerIds).toEqual([]);
  });
});

describe('GameService — advanceTournamentPhase (Task 7)', () => {
  let gameService: GameService;
  beforeEach(() => { gameService = new GameService(); });

  function started(count = 4): GameSession {
    const session = tournamentSession(count);
    inject(gameService, session);
    gameService.beginTournament(session.roomCode);
    return session;
  }

  it('→ ready_check: arms the deadline and flips matches to ready_check', () => {
    const session = started();
    const t = gameService.advanceTournamentPhase(session.roomCode, 'ready_check');
    expect(t.phase).toBe('ready_check');
    expect(t.readyDeadlineAt).toBeGreaterThan(Date.now());
    expect(t.bracket.rounds[0].matches.every((m) => m.status === 'ready_check')).toBe(true);
  });

  it('→ simulating: every current-round match gets ≥3 events, a result, a winner', () => {
    const session = started();
    gameService.advanceTournamentPhase(session.roomCode, 'ready_check');
    const t = gameService.advanceTournamentPhase(session.roomCode, 'simulating');
    expect(t.phase).toBe('simulating');
    for (const m of t.bracket.rounds[0].matches) {
      expect(m.simulationEvents.length).toBeGreaterThanOrEqual(3);
      expect(m.nextEventIndex).toBe(0);
      expect(m.result).not.toBeNull();
      expect(m.winnerId).not.toBeNull();
      expect(m.status).toBe('simulating');
    }
  });

  it('→ round_result: seeds the next round from this round\'s winners', () => {
    const session = started();
    gameService.advanceTournamentPhase(session.roomCode, 'ready_check');
    gameService.advanceTournamentPhase(session.roomCode, 'simulating');
    const t = session.tournament!;
    completeCurrentRound(t);
    const round1Winners = t.bracket.rounds[0].matches.map((m) => m.winnerId);

    gameService.advanceTournamentPhase(session.roomCode, 'round_result');

    expect(t.phase).toBe('round_result');
    expect(t.bracket.rounds[0].status).toBe('complete');
    const final = t.bracket.rounds[1].matches[0];
    expect(final.participantA.participantId).toBe(round1Winners[0]);
    expect(final.participantB.participantId).toBe(round1Winners[1]);
  });

  it('→ complete: sets awards, finishes the session, awards points, attaches to result', () => {
    const session = started();
    // Round 1
    gameService.advanceTournamentPhase(session.roomCode, 'ready_check');
    gameService.advanceTournamentPhase(session.roomCode, 'simulating');
    completeCurrentRound(session.tournament!);
    gameService.advanceTournamentPhase(session.roomCode, 'round_result');
    session.tournament!.currentRound += 1;
    // Final
    gameService.advanceTournamentPhase(session.roomCode, 'ready_check');
    gameService.advanceTournamentPhase(session.roomCode, 'simulating');
    completeCurrentRound(session.tournament!);
    const t = gameService.advanceTournamentPhase(session.roomCode, 'complete');

    expect(t.phase).toBe('complete');
    expect(t.awards).not.toBeNull();
    // The champion is whichever finalist won under the (seeded, probabilistic)
    // simulation engine — a real participant. Award-category winners are also
    // decided by that same simulation (and the bracket draw is now randomized,
    // see beginTournament), so rather than hardcode point totals, recompute
    // the expected breakdown from the awards fields themselves — this is
    // exactly the rule _computeTournamentAwards implements (champion 50 +
    // runner-up 20 + top scorer 15 + most assists 10 + highest rating 10,
    // stacking additively per participant; a tied category SHARES its bonus,
    // split equally and rounded up).
    const champId = t.awards!.champion.participantId;
    expect(['p1', 'p2', 'p3', 'p4']).toContain(champId);
    const expected: Record<string, number> = {};
    const add = (id: string, amount: number) => { expected[id] = (expected[id] ?? 0) + amount; };
    const addShared = (leaders: { participantId: string }[], pool: number) => {
      if (leaders.length === 0) return;
      const perWinner = Math.ceil(pool / leaders.length);
      for (const l of leaders) add(l.participantId, perWinner);
    };
    add(champId, 50);
    add(t.awards!.runnerUp.participantId, 20);
    addShared(t.awards!.topScorer, 15);
    addShared(t.awards!.mostAssists, 10);
    addShared(t.awards!.highestAvgRating, 10);
    expect(t.awards!.pointsAwarded).toEqual(expected);
    // The session is finished and the result carries the tournament awards.
    expect(session.status).toBe('finished');
    expect(session.result).not.toBeNull();
    expect(session.result!.tournament).toBe(t.awards);
  });
});

describe('GameService — shared-award tie rules (goals/assists/rating)', () => {
  // Deterministic tie scenarios, bypassing the probabilistic simulation
  // engine entirely — calls the private awards computation directly against
  // a hand-built two-match bracket so the tie conditions are exact and
  // reproducible (unlike the seeded-but-probabilistic full-lifecycle tests).
  function makeBracket(matches: any[]): TournamentState {
    return {
      phase: 'complete',
      bracket: { size: 4, rounds: [{ roundNumber: 1, label: 'Semi-finals', matches, status: 'complete' }] },
      currentRound: 1,
      totalRounds: 2,
      readyPlayerIds: [],
      readyDeadlineAt: null,
      bracketRevealAt: 0,
      awards: null,
    } as unknown as TournamentState;
  }

  /** Recomputes the expected pointsAwarded from the awards' own leader
   *  arrays, so assertions never have to hand-guess which categories tied
   *  (e.g. ratings happening to tie too in a fixture) — self-consistent with
   *  whatever _computeTournamentAwards actually decided. `aiIds` lists any
   *  participantId that is AI — champion/runner-up bonuses require that
   *  exact participant to be real, and a shared-category bonus pays out only
   *  when EVERY (possibly tied) leader is real; AI never receives points and
   *  never causes a silent hand-down to a human co-leader. */
  function expectedPoints(awards: any, aiIds: Set<string> = new Set()): Record<string, number> {
    const expected: Record<string, number> = {};
    const add = (id: string, amount: number) => { expected[id] = (expected[id] ?? 0) + amount; };
    const addShared = (leaders: { participantId: string }[], pool: number) => {
      if (leaders.length === 0) return;
      if (leaders.some((l) => aiIds.has(l.participantId))) return;
      const perWinner = Math.ceil(pool / leaders.length);
      for (const l of leaders) add(l.participantId, perWinner);
    };
    if (!aiIds.has(awards.champion.participantId)) add(awards.champion.participantId, 50);
    if (!aiIds.has(awards.runnerUp.participantId)) add(awards.runnerUp.participantId, 20);
    addShared(awards.topScorer, 15);
    addShared(awards.mostAssists, 10);
    addShared(awards.highestAvgRating, 10);
    return expected;
  }

  function participant(id: string, playerNames: string[], kind: 'real' | 'ai' = 'real'): any {
    return {
      kind,
      participantId: id,
      displayName: id.toUpperCase(),
      lineup: {
        formationSlug: '4-3-3',
        pitchCards: playerNames.map((name, i) => ({
          cardId: `${id}-${i}`, playerName: name, rating: 80,
          basePositionType: 'ST', slotLabel: 'ST', nationality: 'England', club: 'Test FC', league: '', chemistryBonuses: [],
        })),
        benchCards: [], overallRating: 80, chemistryScore: 0, captainCardId: null, activeAbilityTypes: [],
      },
    };
  }

  it('two players tied on goals with EQUAL minutes → award is shared, bonus split and rounded up', () => {
    const gameService = new GameService();
    const a = participant('a', ['a_scorer', 'a_other']);
    const b = participant('b', ['b_scorer', 'b_other']);
    const match = {
      matchId: 'r1_m1', roundNumber: 1, participantA: a, participantB: b, status: 'complete', winnerId: 'a',
      simulationEvents: [
        { minute: 10, type: 'goal', teamParticipantId: 'a', playerName: 'a_scorer', playerRating: 8 },
        { minute: 20, type: 'goal', teamParticipantId: 'b', playerName: 'b_scorer', playerRating: 8 },
      ],
      nextEventIndex: 0,
      result: {
        matchId: 'r1_m1', scoreA: 1, scoreB: 1, winnerId: 'a', penaltyScoreA: 4, penaltyScoreB: 3,
        stats: { possessionA: 50, shotsA: 3, shotsOnTargetA: 2, bigChancesA: 1, shotsB: 3, shotsOnTargetB: 2, bigChancesB: 1 },
        playerRatings: { a_scorer: 7.5, a_other: 6.5, b_scorer: 7.5, b_other: 6.5 },
        explanation: 'a won on penalties',
      },
    };
    const t = makeBracket([match]);

    const awards = (gameService as any)._computeTournamentAwards(t, a, b, DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1);

    // Neither player was sent off, both played the full 90 → equal minutes →
    // genuinely tied → shared.
    expect(awards.topScorer).toHaveLength(2);
    expect(awards.topScorer.map((s: any) => s.playerName).sort()).toEqual(['a_scorer', 'b_scorer']);
    expect(awards.topScorer.every((s: any) => s.minutesPlayed === 90)).toBe(true);

    // 15 split 2 ways, rounded up → 8 each — confirmed directly (not just via
    // the whole-object comparison below) since this is the exact rule under
    // test: never one tied winner receiving less than another.
    const perWinner = Math.ceil(15 / awards.topScorer.length);
    expect(perWinner).toBe(8);

    expect(awards.pointsAwarded).toEqual(expectedPoints(awards));
  });

  it('two players tied on goals but DIFFERENT minutes → fewer minutes played wins outright (not shared)', () => {
    const gameService = new GameService();
    const a = participant('a', ['a_scorer', 'a_other']);
    const b = participant('b', ['b_scorer', 'b_other']);
    const match = {
      matchId: 'r1_m1', roundNumber: 1, participantA: a, participantB: b, status: 'complete', winnerId: 'a',
      simulationEvents: [
        // b_scorer is sent off at minute 30 — but scored their goal at minute
        // 10, BEFORE the dismissal, so the goal itself is still legitimate.
        { minute: 10, type: 'goal', teamParticipantId: 'b', playerName: 'b_scorer', playerRating: 8 },
        { minute: 30, type: 'red_card', teamParticipantId: 'b', playerName: 'b_scorer', playerRating: 8 },
        { minute: 40, type: 'goal', teamParticipantId: 'a', playerName: 'a_scorer', playerRating: 8 },
      ],
      nextEventIndex: 0,
      result: {
        matchId: 'r1_m1', scoreA: 1, scoreB: 1, winnerId: 'a', penaltyScoreA: 4, penaltyScoreB: 3,
        stats: { possessionA: 50, shotsA: 3, shotsOnTargetA: 2, bigChancesA: 1, shotsB: 3, shotsOnTargetB: 2, bigChancesB: 1 },
        playerRatings: { a_scorer: 7.5, a_other: 6.5, b_scorer: 7.5, b_other: 6.5 },
        explanation: 'a won on penalties',
      },
    };
    const t = makeBracket([match]);

    const awards = (gameService as any)._computeTournamentAwards(t, a, b, DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1);

    // Both scored exactly 1 goal, but b_scorer played only 30 minutes
    // (sent off) vs a_scorer's full 90 — fewer minutes played wins outright,
    // no sharing.
    expect(awards.topScorer).toHaveLength(1);
    expect(awards.topScorer[0].playerName).toBe('b_scorer');
    expect(awards.topScorer[0].minutesPlayed).toBe(30);

    expect(awards.pointsAwarded).toEqual(expectedPoints(awards));
  });

  it('topContributions ranks by goals+assists and carries no bonus points of its own', () => {
    const gameService = new GameService();
    const a = participant('a', ['a_playmaker', 'a_finisher']);
    const b = participant('b', ['b_scorer']);
    const match = {
      matchId: 'r1_m1', roundNumber: 1, participantA: a, participantB: b, status: 'complete', winnerId: 'a',
      simulationEvents: [
        { minute: 10, type: 'goal', teamParticipantId: 'a', playerName: 'a_finisher', playerRating: 8, assistPlayerName: 'a_playmaker' },
        { minute: 20, type: 'goal', teamParticipantId: 'a', playerName: 'a_finisher', playerRating: 8, assistPlayerName: 'a_playmaker' },
        { minute: 30, type: 'goal', teamParticipantId: 'b', playerName: 'b_scorer', playerRating: 8 },
      ],
      nextEventIndex: 0,
      result: {
        matchId: 'r1_m1', scoreA: 2, scoreB: 1, winnerId: 'a', penaltyScoreA: null, penaltyScoreB: null,
        stats: { possessionA: 50, shotsA: 3, shotsOnTargetA: 2, bigChancesA: 1, shotsB: 3, shotsOnTargetB: 2, bigChancesB: 1 },
        playerRatings: { a_playmaker: 7.5, a_finisher: 8.0, b_scorer: 6.5 },
        explanation: 'a won 2-1',
      },
    };
    const t = makeBracket([match]);

    const awards = (gameService as any)._computeTournamentAwards(t, a, b, DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1);

    // a_finisher (2 goals + 0 assists) and a_playmaker (0 goals + 2 assists)
    // both total 2 contributions with equal (90) minutes — a genuine,
    // correct tie, shared between them rather than picking the scorer over
    // the provider (or vice versa).
    expect(awards.topContributions).toHaveLength(2);
    const byName = Object.fromEntries(awards.topContributions.map((c: any) => [c.playerName, c]));
    expect(byName['a_finisher']).toMatchObject({ contributions: 2, goals: 2, assists: 0 });
    expect(byName['a_playmaker']).toMatchObject({ contributions: 2, goals: 0, assists: 2 });

    // Top Contributions is a leaderboard/stat only — no bonus points of its
    // own. Whatever pointsAwarded contains must be fully explained by
    // champion/runner-up + topScorer/mostAssists/highestAvgRating alone.
    expect(awards.pointsAwarded).toEqual(expectedPoints(awards));
  });

  it('highestAvgRating (Best Rating) resolves to the individual player, not the participant/team display name', () => {
    const gameService = new GameService();
    const a = participant('a', ['a_star', 'a_other']);
    const b = participant('b', ['b_star', 'b_other']);
    const match = {
      matchId: 'r1_m1', roundNumber: 1, participantA: a, participantB: b, status: 'complete', winnerId: 'a',
      simulationEvents: [],
      nextEventIndex: 0,
      result: {
        matchId: 'r1_m1', scoreA: 1, scoreB: 0, winnerId: 'a', penaltyScoreA: null, penaltyScoreB: null,
        stats: { possessionA: 50, shotsA: 3, shotsOnTargetA: 2, bigChancesA: 1, shotsB: 3, shotsOnTargetB: 2, bigChancesB: 1 },
        // a_star is the standout individual performer — well above every
        // other player in the match, including their own teammate.
        playerRatings: { a_star: 9.2, a_other: 6.0, b_star: 6.5, b_other: 6.0 },
        explanation: 'a won 1-0',
      },
    };
    const t = makeBracket([match]);

    const awards = (gameService as any)._computeTournamentAwards(t, a, b, DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1);

    expect(awards.highestAvgRating).toHaveLength(1);
    // Must be the real footballer's name — never a participant/team label
    // like "A" or "B" (the old, buggy team-level behaviour).
    expect(awards.highestAvgRating[0].playerName).toBe('a_star');
    expect(awards.highestAvgRating[0].playerName).not.toBe(a.displayName);
    expect(awards.highestAvgRating[0].avgRating).toBe(9.2);
    expect(awards.highestAvgRating[0].participantId).toBe('a');

    expect(awards.pointsAwarded).toEqual(expectedPoints(awards));
  });

  it('cleanSheets credits the actual goalkeeper, not the participant/team display name', () => {
    const gameService = new GameService();
    // Give each side an explicit GK card (slotLabel 'GK') alongside an
    // outfield card, so the fix's `slotLabel === 'GK'` lookup has something
    // real to find.
    const a = {
      ...participant('a', ['a_keeper']),
      lineup: {
        ...participant('a', ['a_keeper']).lineup,
        pitchCards: [
          { cardId: 'a-gk', playerName: 'a_keeper', rating: 80, basePositionType: 'GK', slotLabel: 'GK', nationality: 'England', club: 'Test FC', league: '', chemistryBonuses: [] },
          { cardId: 'a-st', playerName: 'a_striker', rating: 80, basePositionType: 'ST', slotLabel: 'ST', nationality: 'England', club: 'Test FC', league: '', chemistryBonuses: [] },
        ],
      },
    };
    const b = {
      ...participant('b', ['b_keeper']),
      lineup: {
        ...participant('b', ['b_keeper']).lineup,
        pitchCards: [
          { cardId: 'b-gk', playerName: 'b_keeper', rating: 80, basePositionType: 'GK', slotLabel: 'GK', nationality: 'England', club: 'Test FC', league: '', chemistryBonuses: [] },
          { cardId: 'b-st', playerName: 'b_striker', rating: 80, basePositionType: 'ST', slotLabel: 'ST', nationality: 'England', club: 'Test FC', league: '', chemistryBonuses: [] },
        ],
      },
    };
    const match = {
      matchId: 'r1_m1', roundNumber: 1, participantA: a, participantB: b, status: 'complete', winnerId: 'a',
      simulationEvents: [
        { minute: 40, type: 'goal', teamParticipantId: 'a', playerName: 'a_striker', playerRating: 7.5 },
      ],
      nextEventIndex: 0,
      result: {
        // a wins 1-0 — b conceded, but a's side kept a clean sheet.
        matchId: 'r1_m1', scoreA: 1, scoreB: 0, winnerId: 'a', penaltyScoreA: null, penaltyScoreB: null,
        stats: { possessionA: 50, shotsA: 3, shotsOnTargetA: 2, bigChancesA: 1, shotsB: 3, shotsOnTargetB: 2, bigChancesB: 1 },
        playerRatings: { a_keeper: 7.0, a_striker: 7.5, b_keeper: 6.0, b_striker: 6.0 },
        explanation: 'a won 1-0',
      },
    };
    const t = makeBracket([match]);

    const awards = (gameService as any)._computeTournamentAwards(t, a, b, DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1);

    expect(awards.cleanSheets).toHaveLength(1);
    // Must be the actual goalkeeper's name — never the participant/team
    // label like "A" (the old, buggy behaviour keyed on match.participantA.displayName).
    expect(awards.cleanSheets[0].playerName).toBe('a_keeper');
    expect(awards.cleanSheets[0].playerName).not.toBe(a.displayName);
    expect(awards.cleanSheets[0].cleanSheets).toBe(1);
    expect(awards.cleanSheets[0].participantId).toBe('a');
  });

  it('an AI player outright leading Top Scorer is shown as the real leader but pays NO user points', () => {
    const gameService = new GameService();
    const human = participant('human', ['human_scorer']);
    const ai = participant('ai_bot', ['ai_striker'], 'ai');
    const match = {
      matchId: 'r1_m1', roundNumber: 1, participantA: human, participantB: ai, status: 'complete', winnerId: 'ai_bot',
      simulationEvents: [
        { minute: 20, type: 'goal', teamParticipantId: 'human', playerName: 'human_scorer', playerRating: 7.0 },
        { minute: 30, type: 'goal', teamParticipantId: 'ai_bot', playerName: 'ai_striker', playerRating: 7.5 },
        { minute: 50, type: 'goal', teamParticipantId: 'ai_bot', playerName: 'ai_striker', playerRating: 7.5 },
      ],
      nextEventIndex: 0,
      result: {
        matchId: 'r1_m1', scoreA: 1, scoreB: 2, winnerId: 'ai_bot', penaltyScoreA: null, penaltyScoreB: null,
        stats: { possessionA: 50, shotsA: 3, shotsOnTargetA: 2, bigChancesA: 1, shotsB: 3, shotsOnTargetB: 2, bigChancesB: 1 },
        playerRatings: { human_scorer: 7.0, ai_striker: 7.5 },
        explanation: 'ai_bot won 2-1',
      },
    };
    const t = makeBracket([match]);

    // The AI club is the champion here — also a real, valid outcome; the
    // human is the runner-up.
    const awards = (gameService as any)._computeTournamentAwards(t, ai, human, DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1);

    // Leaderboard: the AI player IS shown as the true Top Scorer (2 goals
    // beats the human's 1) — never hidden or skipped for being non-human.
    expect(awards.topScorer).toHaveLength(1);
    expect(awards.topScorer[0].playerName).toBe('ai_striker');
    expect(awards.topScorer[0].participantId).toBe('ai_bot');

    // Points: since the sole Top Scorer leader is AI, NO human receives the
    // Top Scorer bonus — not even the human runner-up scorer, and it is not
    // silently handed down to them either.
    // Champion bonus is also correctly withheld — the champion itself is AI
    // — and the human runner-up does not earn a runner-up bonus in this
    // fixture either (runnerUp is 'real' but the runner-up placement bonus
    // only pays a real participant; here that IS the human, so verify the
    // exact expected total explicitly).
    expect(awards.pointsAwarded).toEqual(expectedPoints(awards, new Set(['ai_bot'])));
    expect(awards.pointsAwarded['ai_bot']).toBeUndefined();
    expect(awards.pointsAwarded['human']).toBe(20); // runner-up bonus only

    // The blocked categories are surfaced explicitly so clients can explain
    // the human's missing bonus rather than leaving it unexplained. Best
    // Rating is also AI-led here (ai_striker outrates human_scorer), so both
    // categories are blocked in this fixture.
    expect(awards.blockedCategories).toEqual(['Top Scorer', 'Best Rating']);
  });

  it('an AI player tied with a human for Best Rating blocks the WHOLE category — no partial payout to the human', () => {
    const gameService = new GameService();
    const human = participant('human2', ['human_star']);
    const ai = participant('ai_bot2', ['ai_star'], 'ai');
    const match = {
      matchId: 'r1_m1', roundNumber: 1, participantA: human, participantB: ai, status: 'complete', winnerId: 'human2',
      simulationEvents: [],
      nextEventIndex: 0,
      result: {
        matchId: 'r1_m1', scoreA: 1, scoreB: 0, winnerId: 'human2', penaltyScoreA: null, penaltyScoreB: null,
        stats: { possessionA: 50, shotsA: 3, shotsOnTargetA: 2, bigChancesA: 1, shotsB: 3, shotsOnTargetB: 2, bigChancesB: 1 },
        // Exact tie at 2dp between the human's player and the AI's player.
        playerRatings: { human_star: 8.4, ai_star: 8.4 },
        explanation: 'human2 won 1-0',
      },
    };
    const t = makeBracket([match]);

    const awards = (gameService as any)._computeTournamentAwards(t, human, ai, DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1);

    // Both are shown as genuinely tied leaders on the leaderboard.
    expect(awards.highestAvgRating).toHaveLength(2);
    expect(awards.highestAvgRating.map((r: any) => r.playerName).sort()).toEqual(['ai_star', 'human_star']);

    // But because an AI is among the tied leaders, the category pays NO
    // user points at all — the human does not receive even a partial/solo
    // share just because the AI can't be paid. Only the champion bonus (a
    // separate category, unaffected by this rule) shows up for the human.
    expect(awards.pointsAwarded).toEqual({ human2: 50 });
    expect(awards.pointsAwarded).toEqual(expectedPoints(awards, new Set(['ai_bot2'])));
    expect(awards.blockedCategories).toEqual(['Best Rating']);
  });
});

describe('GameService — full tournament lifecycle (Acceptance #5)', () => {
  it('drives a 4-player tournament from bracket_reveal through to a finished session', () => {
    const gameService = new GameService();
    const session = tournamentSession(4);
    inject(gameService, session);

    const t = gameService.beginTournament(session.roomCode);
    expect(t.phase).toBe('bracket_reveal');

    // Round 1 (Semi-finals for a 4-bracket).
    gameService.advanceTournamentPhase(session.roomCode, 'ready_check');
    expect(session.tournament!.phase).toBe('ready_check');
    gameService.advanceTournamentPhase(session.roomCode, 'simulating');
    expect(session.tournament!.phase).toBe('simulating');
    completeCurrentRound(session.tournament!);
    gameService.advanceTournamentPhase(session.roomCode, 'round_result');
    session.tournament!.currentRound += 1;

    // Round 2 (Final).
    gameService.advanceTournamentPhase(session.roomCode, 'ready_check');
    gameService.advanceTournamentPhase(session.roomCode, 'simulating');
    completeCurrentRound(session.tournament!);
    gameService.advanceTournamentPhase(session.roomCode, 'complete');

    expect(session.status).toBe('finished');
    // Champion is a real participant (the seeded engine decides who wins).
    expect(['p1', 'p2', 'p3', 'p4'])
        .toContain(session.tournament!.awards!.champion.participantId);
  });
});
