import { GameService } from './game.service';
import { GameSession } from './interfaces/game-session.interface';
import { PitchSlot, Pitch } from './interfaces/pitch.interface';
import { DraftCard } from './interfaces/draft-card.interface';
import { BasePositionType, SlotLabel } from './interfaces/formation.interface';

/**
 * Track B Phase B1 — required regression coverage: Captain/Red must keep
 * applying correctly after a lineup_edit (step 4) swapRoster move, since
 * both are tracked by cardId (not slot index) precisely so they survive
 * rearrangement — see activateAbility's captain/red doc comments in
 * game.service.ts. These tests prove that through the REAL scoring engine
 * (computeChemistryScore), not just by inspecting internal fields.
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

function card(cardId: string, base: BasePositionType, rating = 75): DraftCard {
  return {
    cardId, playerName: cardId, basePositionType: base, rating,
    pace: rating, shooting: rating, passing: rating, dribbling: rating, defending: rating, physical: rating,
    nationality: 'England', club: 'Test FC', altPositions: [], naturalPositions: [base],
    chemistryBonuses: [],
  };
}

function fullLineup(prefix: string): PitchSlot[] {
  return FORMATION_SLOTS.map((s, index) => ({
    index, label: s.label, basePositionType: s.base, card: card(`${prefix}-${s.base}-${index}`, s.base),
  }));
}

function pitch(playerId: string, slots: PitchSlot[]): Pitch {
  return { playerId, slots, filledCount: slots.filter((s) => s.card).length };
}

function lineupEditSession(overrides: Partial<GameSession> = {}): GameSession {
  return {
    sessionId: 'sess-cr',
    roomCode: 'CAPRED1',
    createdAt: Date.now(),
    leagues: [],
    playerBonusCache: new Map(),
    userChallengeCache: new Map(),
    formation: { name: '4-3-3', slots: [] } as any,
    players: [
      { id: 'p1', displayName: 'Alice', isHost: true, isConnected: true } as any,
      { id: 'p2', displayName: 'Bob', isHost: false, isConnected: true } as any,
    ],
    pitches: { p1: pitch('p1', fullLineup('A')), p2: pitch('p2', fullLineup('B')) },
    baseTurnOrder: ['p1', 'p2'],
    currentRound: 12,
    totalRounds: 11,
    currentTurnIndex: 0,
    currentRoundSlotIndex: null,
    draftedCardIds: new Set(),
    roundCandidates: [],
    orderedHiddenDeck: [],
    hiddenPicksTaken: new Set(),
    hiddenPicksMap: new Map(),
    hiddenPickReveal: null,
    lastRoundLeftovers: [],
    turn: { turnId: 't1', phase: 'selecting_position', activePlayerId: 'p1', activeSlotIndex: null, candidates: [], turnStartedAt: null },
    turnTimeoutPolicy: { enabled: false, turnSeconds: null, onExpiry: null },
    status: 'lineup_edit',
    abilityDraft: null,
    playerAbilities: {},
    abilityActivations: [],
    subSwappedCardIds: new Set(),
    isFinished: false,
    subsPhase: {
      userSubs: {
        p1: { isComplete: true, lineupConfirmed: false, hasExtraBench: false },
        p2: { isComplete: true, lineupConfirmed: false, hasExtraBench: false },
      },
    },
    subsTimerSeconds: null,
    subsDeadlineAt: null,
    abilityActivationDeadlineAt: null,
    result: null,
    ...overrides,
  } as GameSession;
}

function inject(gameService: GameService, session: GameSession): void {
  (gameService as unknown as { sessions: Map<string, GameSession> }).sessions.set(session.sessionId, session);
  (gameService as unknown as { roomToSession: Map<string, string> }).roomToSession.set(session.roomCode, session.sessionId);
}

/**
 * computeCardChemTotal (scoring.ts) reads card chemistry from
 * `session.playerBonusCache` (keyed by cardId) — NOT from
 * `DraftCard.chemistryBonuses`, which the scoring engine never consults.
 * Every fixture card shares club 'Test FC', so a trivially-satisfied
 * SAME_CLUB bonus (count: 2) gives captain's doubling / red's nullification
 * a NONZERO effect to observe — without this, `playerBonusCache` starts
 * empty and captain/red would be a no-op regardless of whether persistence
 * actually works, making the test vacuous.
 */
function giveChemBonus(session: GameSession, cardId: string): void {
  session.playerBonusCache.set(cardId, [
    { tier: 'easy', reward: 2, type: 'SAME_CLUB', params: { club: 'Test FC', count: 2 }, label: 'test bonus' } as any,
  ]);
}

describe('GameService — Captain/Red persistence through lineup_edit swaps (Track B step 4)', () => {
  let gameService: GameService;
  beforeEach(() => { gameService = new GameService(); });

  it('a captained card keeps earning its bonus after being moved to a DIFFERENT pitch slot via swapRoster', () => {
    // Both defensive slots are basePositionType 'CB' (LCB index 2, RCB index
    // 3) — swapping between them keeps the card legally positioned either
    // way, isolating this test to captain persistence specifically, not
    // position-fit (an illegal placement would independently zero the card's
    // own line/chemistry contribution regardless of captain status).
    const captainedCardId = 'A-CB-2';
    const session = lineupEditSession({
      playerAbilities: {
        p1: { type: 'captain', status: 'used', targetPlayerId: captainedCardId } as any,
      },
    });
    inject(gameService, session);
    giveChemBonus(session, captainedCardId);

    const scoreBefore = gameService.computeChemistryScore(session, 'p1');

    const cbSlotA = session.pitches.p1.slots.find((s) => s.card!.cardId === captainedCardId)!;
    const cbSlotB = session.pitches.p1.slots.find(
      (s) => s.basePositionType === 'CB' && s.card!.cardId !== captainedCardId,
    )!;
    const swap = gameService.swapRoster(
      'CAPRED1', 'p1',
      { kind: 'pitch', index: cbSlotA.index },
      { kind: 'pitch', index: cbSlotB.index },
    );
    expect('error' in swap).toBe(false);
    // The card genuinely moved.
    expect(session.pitches.p1.slots.find((s) => s.index === cbSlotB.index)!.card!.cardId).toBe(captainedCardId);

    const scoreAfter = gameService.computeChemistryScore(session, 'p1');

    // Same 11 cards, same captain target, just rearranged — the bonus must
    // still be counted, so the total score is unchanged.
    expect(scoreAfter).toBe(scoreBefore);
  });

  it('a captained card STOPS earning its bonus once benched via swapRoster — scoring only reads the pitch, never the bench', () => {
    const captainedCardId = 'A-CM-6';
    const session = lineupEditSession({
      playerAbilities: {
        p1: { type: 'captain', status: 'used', targetPlayerId: captainedCardId } as any,
      },
      subsPhase: {
        userSubs: {
          p1: {
            isComplete: true,
            lineupConfirmed: false,
            hasExtraBench: false,
            mid: { positionGroup: 'mid', chosenCard: card('BENCH-MID', 'CM', 75) },
          },
          p2: { isComplete: true, lineupConfirmed: false, hasExtraBench: false },
        },
      },
    });
    inject(gameService, session);
    giveChemBonus(session, captainedCardId);

    const scoreBefore = gameService.computeChemistryScore(session, 'p1');

    const cmSlot = session.pitches.p1.slots.find((s) => s.card!.cardId === captainedCardId)!;
    const swap = gameService.swapRoster(
      'CAPRED1', 'p1',
      { kind: 'pitch', index: cmSlot.index },
      { kind: 'bench', group: 'mid' },
    );
    expect('error' in swap).toBe(false);
    // The captained card is now on the bench, not the pitch.
    expect(session.pitches.p1.slots.some((s) => s.card?.cardId === captainedCardId)).toBe(false);

    const scoreAfter = gameService.computeChemistryScore(session, 'p1');

    // The captain bonus is gone (benched cards never score) — the total
    // must be lower, not merely unchanged.
    expect(scoreAfter).toBeLessThan(scoreBefore);
  });

  it('a red-carded card keeps having its chemistry nullified after being moved to a DIFFERENT pitch slot via swapRoster', () => {
    // Same CB↔CB legal-swap technique as the captain persistence test above.
    const redCardedId = 'B-CB-2'; // one of p2's own CB cards, red-carded by p1
    const session = lineupEditSession({
      playerAbilities: {
        p1: { type: 'red', status: 'used', targetUserId: 'p2', targetPlayerId: redCardedId } as any,
      },
    });
    inject(gameService, session);
    giveChemBonus(session, redCardedId);

    // Sanity: red is actually suppressing something (not a vacuous "nothing
    // changed because red never worked" pass) — a sibling session with the
    // SAME bonus but NO red card scores strictly higher.
    const noRedSession = lineupEditSession({ playerAbilities: {} });
    giveChemBonus(noRedSession, redCardedId);
    const noRedGameService = new GameService();
    inject(noRedGameService, noRedSession);
    const scoreWithoutRed = noRedGameService.computeChemistryScore(noRedSession, 'p2');

    const scoreBefore = gameService.computeChemistryScore(session, 'p2');
    expect(scoreBefore).toBeLessThan(scoreWithoutRed);

    const cbSlotA = session.pitches.p2.slots.find((s) => s.card!.cardId === redCardedId)!;
    const cbSlotB = session.pitches.p2.slots.find(
      (s) => s.basePositionType === 'CB' && s.card!.cardId !== redCardedId,
    )!;
    const swap = gameService.swapRoster(
      'CAPRED1', 'p2',
      { kind: 'pitch', index: cbSlotA.index },
      { kind: 'pitch', index: cbSlotB.index },
    );
    expect('error' in swap).toBe(false);
    expect(session.pitches.p2.slots.find((s) => s.index === cbSlotB.index)!.card!.cardId).toBe(redCardedId);

    const scoreAfter = gameService.computeChemistryScore(session, 'p2');

    // Same 11 cards, same red target, just rearranged — the nullification
    // must still apply, so the total score is unchanged (not restored).
    expect(scoreAfter).toBe(scoreBefore);
  });
});
