import { GameService } from './game.service';
import { GameSession } from './interfaces/game-session.interface';
import { PitchSlot, Pitch } from './interfaces/pitch.interface';
import { DraftCard } from './interfaces/draft-card.interface';
import { BasePositionType, SlotLabel } from './interfaces/formation.interface';

/**
 * Player-draft protocol tests (Task 3.1) — the longest, most complex
 * stateful flow in the game, exercised by every real game that reaches a
 * natural finish, and previously untested. Read pickSlot/pickCard/
 * orderHiddenDeck/pickHiddenSlot/confirmHiddenReveal/_enterActivationPhase
 * in game.service.ts in full before writing any of these (not from memory).
 *
 * Key facts confirmed by that reading, not assumed:
 * - pickSlot's "position already filled" rejection (scenario 3) is actually
 *   "this exact slot index already has a card" (SLOT_ALREADY_FILLED), not a
 *   broader "you already have a player in this position group" rule — there
 *   is no such broader rule in the code.
 * - For a MULTI-player game, pickCard does not advance the turn to the next
 *   player directly — it hands the turn to 'first_player_order' (still the
 *   SAME picker), who must then order the leftover candidates into a hidden
 *   deck via orderHiddenDeck. Only orderHiddenDeck actually advances
 *   currentTurnIndex to the next player (who enters 'hidden_pick').
 * - pickHiddenSlot does NOT advance the turn itself — it enters
 *   'hidden_pick_reveal' (same picker, a reveal window) and only
 *   confirmHiddenReveal (a separate call) actually advances currentTurnIndex
 *   and decides round-wrap vs. next-hidden-picker vs. draft-complete.
 * - Round-wrap math: currentTurnIndex increments on both orderHiddenDeck
 *   (once, for the very first turn-index step of the round) and on every
 *   confirmHiddenReveal (once per hidden picker). The round wraps once
 *   currentTurnIndex >= baseTurnOrder.length.
 * - generateCandidates() (called by pickSlot) reads the real, cached (Task
 *   2.2) admin-data player pool with internal random shuffling — candidate
 *   IDENTITY can't be asserted deterministically, only structural properties
 *   (count, position-correctness). pickCard's own tests inject
 *   session.turn.candidates directly instead, to fully control which cards
 *   are "available" without depending on the real pool's random contents.
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

/** An EMPTY 11-slot pitch — every slot present, no cards. */
function emptyPitchSlots(): PitchSlot[] {
  return FORMATION_SLOTS.map((s, index) => ({ index, label: s.label, basePositionType: s.base, card: null }));
}

function pitch(playerId: string, slots: PitchSlot[]): Pitch {
  return { playerId, slots, filledCount: slots.filter((s) => s.card).length };
}

function baseSession(overrides: Partial<GameSession> = {}): GameSession {
  return {
    sessionId: 'sess-draft',
    roomCode: 'DRAFT1',
    createdAt: Date.now(),
    leagues: [],
    playerBonusCache: new Map(),
    userChallengeCache: new Map(),
    formation: { name: '4-3-3', slots: [] } as any,
    players: [
      { id: 'p1', displayName: 'Alice', isHost: true, isConnected: true } as any,
      { id: 'p2', displayName: 'Bob', isHost: false, isConnected: true } as any,
    ],
    pitches: { p1: pitch('p1', emptyPitchSlots()), p2: pitch('p2', emptyPitchSlots()) },
    baseTurnOrder: ['p1', 'p2'],
    currentRound: 5, // mid-draft, not round 1 — per the established injection technique
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
    status: 'drafting',
    abilityDraft: null,
    playerAbilities: {},
    abilityActivations: [],
    subSwappedCardIds: new Set(),
    isFinished: false,
    subsPhase: null,
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

describe('GameService — player draft: slot selection & candidate offer (Task 3.1)', () => {
  let gameService: GameService;
  beforeEach(() => { gameService = new GameService(); });

  it('pickSlot with a valid empty position records the pick and returns position-matching candidates', () => {
    const session = baseSession();
    inject(gameService, session);

    const result = gameService.pickSlot('DRAFT1', 'p1', 't1', 0); // GK slot

    expect('error' in result).toBe(false);
    if ('error' in result) return;
    expect(session.currentRoundSlotIndex).toBe(0);
    expect(session.turn.phase).toBe('selecting_card');
    expect(result.candidates.length).toBeGreaterThan(0);
    expect(result.candidates.every((c) => c.basePositionType === 'GK')).toBe(true);
  });

  it('pickSlot when it is not your turn is rejected with NOT_YOUR_TURN', () => {
    const session = baseSession(); // activePlayerId is p1
    inject(gameService, session);

    const result = gameService.pickSlot('DRAFT1', 'p2', 't1', 0);

    expect(result).toEqual({ error: 'NOT_YOUR_TURN' });
    expect(session.currentRoundSlotIndex).toBeNull();
  });

  it('pickSlot for a slot index that already has a card is rejected with SLOT_ALREADY_FILLED', () => {
    const slots = emptyPitchSlots();
    slots[0] = { ...slots[0], card: card('existing-gk', 'GK') };
    const session = baseSession({ pitches: { p1: pitch('p1', slots), p2: pitch('p2', emptyPitchSlots()) } });
    inject(gameService, session);

    const result = gameService.pickSlot('DRAFT1', 'p1', 't1', 0);

    expect(result).toEqual({ error: 'SLOT_ALREADY_FILLED' });
  });

  it('pickSlot is rejected with ROUND_SLOT_ALREADY_CHOSEN if a slot was already chosen this round', () => {
    const session = baseSession({ currentRoundSlotIndex: 3 });
    inject(gameService, session);

    const result = gameService.pickSlot('DRAFT1', 'p1', 't1', 0);

    expect(result).toEqual({ error: 'ROUND_SLOT_ALREADY_CHOSEN' });
  });
});

describe('GameService — player draft: card pick (Task 3.1)', () => {
  let gameService: GameService;
  beforeEach(() => { gameService = new GameService(); });

  function sessionAtSelectingCard(overrides: Partial<GameSession> = {}): GameSession {
    const offered = [card('offered-1', 'GK'), card('offered-2', 'GK'), card('offered-3', 'GK')];
    return baseSession({
      currentRoundSlotIndex: 0,
      roundCandidates: offered,
      turn: { turnId: 't1', phase: 'selecting_card', activePlayerId: 'p1', activeSlotIndex: 0, candidates: offered, turnStartedAt: null },
      ...overrides,
    });
  }

  it('pickCard with a valid candidate assigns the card, removes it from the pool, and (multi-player) hands the SAME picker the ordering turn', () => {
    const session = sessionAtSelectingCard();
    inject(gameService, session);

    const result = gameService.pickCard('DRAFT1', 'p1', 't1', 'offered-1');

    expect('error' in result).toBe(false);
    if ('error' in result) return;
    expect(session.pitches.p1.slots[0].card?.cardId).toBe('offered-1');
    expect(session.draftedCardIds.has('offered-1')).toBe(true);
    expect(session.roundCandidates.map((c) => c.cardId)).toEqual(['offered-2', 'offered-3']); // picked card removed
    expect(result.orderPromptCards?.map((c) => c.cardId)).toEqual(['offered-2', 'offered-3']);
    // Multi-player: turn does NOT advance to p2 yet — same picker orders next.
    expect(session.turn.phase).toBe('first_player_order');
    expect(session.turn.activePlayerId).toBe('p1');
  });

  it('pickCard with a cardId not in the current candidates is rejected with INVALID_CARD', () => {
    const session = sessionAtSelectingCard();
    inject(gameService, session);

    const result = gameService.pickCard('DRAFT1', 'p1', 't1', 'not-a-real-card');

    expect(result).toEqual({ error: 'INVALID_CARD' });
    expect(session.pitches.p1.slots[0].card).toBeNull();
  });

  it('pickCard out of turn is rejected with NOT_YOUR_TURN', () => {
    const session = sessionAtSelectingCard();
    inject(gameService, session);

    const result = gameService.pickCard('DRAFT1', 'p2', 't1', 'offered-1');

    expect(result).toEqual({ error: 'NOT_YOUR_TURN' });
  });
});

describe('GameService — player draft: hidden-deck flow (Task 3.1)', () => {
  let gameService: GameService;
  beforeEach(() => { gameService = new GameService(); });

  function sessionAtFirstPlayerOrder(overrides: Partial<GameSession> = {}): GameSession {
    const leftovers = [card('leftover-1', 'GK'), card('leftover-2', 'GK')];
    return baseSession({
      currentRoundSlotIndex: 0,
      roundCandidates: leftovers,
      turn: { turnId: 't1', phase: 'first_player_order', activePlayerId: 'p1', activeSlotIndex: 0, candidates: [], turnStartedAt: null },
      ...overrides,
    });
  }

  it('orderHiddenDeck with a valid ordering stores it and hands the turn to the NEXT player for hidden_pick', () => {
    const session = sessionAtFirstPlayerOrder();
    inject(gameService, session);

    const result = gameService.orderHiddenDeck('DRAFT1', 'p1', 't1', ['leftover-2', 'leftover-1']); // reversed order

    expect('error' in result).toBe(false);
    if ('error' in result) return;
    expect(session.orderedHiddenDeck.map((c) => c.cardId)).toEqual(['leftover-2', 'leftover-1']);
    expect(result.availableSlots).toEqual([0, 1]);
    expect(session.currentTurnIndex).toBe(1);
    expect(session.turn.phase).toBe('hidden_pick');
    expect(session.turn.activePlayerId).toBe('p2'); // next player in turn order
  });

  it('orderHiddenDeck with the wrong length is rejected with INVALID_ORDER_LENGTH', () => {
    const session = sessionAtFirstPlayerOrder();
    inject(gameService, session);

    const result = gameService.orderHiddenDeck('DRAFT1', 'p1', 't1', ['leftover-1']); // only 1, expected 2

    expect(result).toEqual({ error: 'INVALID_ORDER_LENGTH' });
  });

  it('orderHiddenDeck with an unknown cardId is rejected with INVALID_ORDER_IDS', () => {
    const session = sessionAtFirstPlayerOrder();
    inject(gameService, session);

    const result = gameService.orderHiddenDeck('DRAFT1', 'p1', 't1', ['leftover-1', 'not-a-real-card']);

    expect(result).toEqual({ error: 'INVALID_ORDER_IDS' });
  });

  it('orderHiddenDeck with a repeated cardId is rejected with INVALID_ORDER_IDS instead of silently dropping a real card and letting two players draft the same one', () => {
    const session = sessionAtFirstPlayerOrder();
    inject(gameService, session);

    // Same length as the real pool (2), every id individually valid — but
    // 'leftover-1' appears twice and 'leftover-2' is missing entirely. A
    // length/membership-only check would accept this and silently place
    // 'leftover-1' at BOTH hidden slots, letting two different players end
    // up drafting the exact same card — the no-duplication guarantee.
    const result = gameService.orderHiddenDeck('DRAFT1', 'p1', 't1', ['leftover-1', 'leftover-1']);

    expect(result).toEqual({ error: 'INVALID_ORDER_IDS' });
    // Nothing was mutated by the rejected call.
    expect(session.orderedHiddenDeck).toEqual([]);
  });

  function sessionAtHiddenPick(overrides: Partial<GameSession> = {}): GameSession {
    const deck = [card('hidden-1', 'GK'), card('hidden-2', 'GK')];
    return baseSession({
      currentRoundSlotIndex: 0,
      orderedHiddenDeck: deck,
      currentTurnIndex: 1,
      turn: { turnId: 't2', phase: 'hidden_pick', activePlayerId: 'p2', activeSlotIndex: 0, candidates: [], turnStartedAt: null },
      ...overrides,
    });
  }

  it('pickHiddenSlot with a valid blind pick assigns the card to the picker and reveals it ONLY to them (via the return value, not a broadcast)', () => {
    const session = sessionAtHiddenPick();
    inject(gameService, session);

    const result = gameService.pickHiddenSlot('DRAFT1', 'p2', 't2', 1); // picks index 1 → 'hidden-2'

    expect('error' in result).toBe(false);
    if ('error' in result) return;
    expect(result.revealedCard.cardId).toBe('hidden-2');
    expect(session.pitches.p2.slots[0].card?.cardId).toBe('hidden-2');
    expect(session.hiddenPicksTaken.has(1)).toBe(true);
    // Turn does NOT advance yet — enters a reveal window for the SAME picker.
    expect(session.turn.phase).toBe('hidden_pick_reveal');
    expect(session.turn.activePlayerId).toBe('p2');
    expect(session.hiddenPickReveal?.pickerPlayerId).toBe('p2');
  });

  it('pickHiddenSlot on an already-taken slot is rejected with SLOT_ALREADY_TAKEN', () => {
    const session = sessionAtHiddenPick({ hiddenPicksTaken: new Set([1]) });
    inject(gameService, session);

    const result = gameService.pickHiddenSlot('DRAFT1', 'p2', 't2', 1);

    expect(result).toEqual({ error: 'SLOT_ALREADY_TAKEN' });
  });

  it('the hidden deck is consumed in pick order — each picker gets exactly the slot index they chose, not a reassigned one', () => {
    // 3-player round: p1 ordered the deck, p2 and p3 pick in sequence.
    const deck = [card('h0', 'GK'), card('h1', 'GK'), card('h2', 'GK')];
    const session = baseSession({
      players: [
        { id: 'p1', displayName: 'Alice', isHost: true, isConnected: true } as any,
        { id: 'p2', displayName: 'Bob', isHost: false, isConnected: true } as any,
        { id: 'p3', displayName: 'Cara', isHost: false, isConnected: true } as any,
      ],
      pitches: { p1: pitch('p1', emptyPitchSlots()), p2: pitch('p2', emptyPitchSlots()), p3: pitch('p3', emptyPitchSlots()) },
      baseTurnOrder: ['p1', 'p2', 'p3'],
      // currentRound: 1 → computeEffectiveTurnOrder's rotation offset
      // ((round-1) % n) is 0, so effectiveOrder === baseTurnOrder exactly —
      // keeps this test's turn-order assertions simple and unambiguous.
      currentRound: 1,
      currentRoundSlotIndex: 0,
      orderedHiddenDeck: deck,
      currentTurnIndex: 1,
      turn: { turnId: 't2', phase: 'hidden_pick', activePlayerId: 'p2', activeSlotIndex: 0, candidates: [], turnStartedAt: null },
    });
    inject(gameService, session);

    // p2 deliberately picks slot index 2 (not the "next available" default).
    const p2Result = gameService.pickHiddenSlot('DRAFT1', 'p2', 't2', 2);
    expect('error' in p2Result).toBe(false);
    expect(session.pitches.p2.slots[0].card?.cardId).toBe('h2');

    // Confirm reveal, advance to p3's hidden_pick turn.
    const confirmResult = gameService.confirmHiddenReveal('DRAFT1', session.turn.turnId, 'p2');
    expect('error' in confirmResult).toBe(false);
    expect(session.turn.activePlayerId).toBe('p3');

    // p3 picks the only slot left (index 0).
    const p3Result = gameService.pickHiddenSlot('DRAFT1', 'p3', session.turn.turnId, 0);
    expect('error' in p3Result).toBe(false);
    expect(session.pitches.p3.slots[0].card?.cardId).toBe('h0'); // got exactly the slot they chose, index 0
  });

  it('confirmHiddenReveal mid-round (not the last hidden picker) advances to the next picker, same round', () => {
    // 3-player round, p2 just picked — confirming should hand off to p3, not wrap the round.
    const session = baseSession({
      players: [
        { id: 'p1', displayName: 'Alice', isHost: true, isConnected: true } as any,
        { id: 'p2', displayName: 'Bob', isHost: false, isConnected: true } as any,
        { id: 'p3', displayName: 'Cara', isHost: false, isConnected: true } as any,
      ],
      pitches: { p1: pitch('p1', emptyPitchSlots()), p2: pitch('p2', emptyPitchSlots()), p3: pitch('p3', emptyPitchSlots()) },
      baseTurnOrder: ['p1', 'p2', 'p3'],
      currentRoundSlotIndex: 0,
      orderedHiddenDeck: [card('h0', 'GK'), card('h1', 'GK')],
      hiddenPicksTaken: new Set([1]),
      currentTurnIndex: 1,
      turn: { turnId: 't3', phase: 'hidden_pick_reveal', activePlayerId: 'p2', activeSlotIndex: 0, candidates: [], turnStartedAt: null },
      hiddenPickReveal: { pickerPlayerId: 'p2', timeoutAt: Date.now() + 5000 },
    });
    inject(gameService, session);

    const result = gameService.confirmHiddenReveal('DRAFT1', 't3', 'p2');

    expect('error' in result).toBe(false);
    if ('error' in result) return;
    expect(session.currentTurnIndex).toBe(2);
    expect(session.currentRound).toBe(5); // unchanged — round has not wrapped
    expect(session.turn.phase).toBe('hidden_pick');
    // computeEffectiveTurnOrder rotates baseTurnOrder by (currentRound-1) % n —
    // at round 5 with 3 players, offset=1, so effectiveOrder is
    // ['p2','p3','p1'], and index 2 (the new currentTurnIndex) is 'p1', not
    // a naive "next in baseTurnOrder" 'p3'. Asserting the actual rotated
    // result here, computed by hand and cross-checked against
    // computeEffectiveTurnOrder's own documented formula, not assumed.
    expect(session.turn.activePlayerId).toBe('p1');
  });

  it('confirmHiddenReveal by someone other than the picker is rejected with NOT_THE_PICKER', () => {
    const session = baseSession({
      turn: { turnId: 't3', phase: 'hidden_pick_reveal', activePlayerId: 'p2', activeSlotIndex: 0, candidates: [], turnStartedAt: null },
      hiddenPickReveal: { pickerPlayerId: 'p2', timeoutAt: Date.now() + 5000 },
    });
    inject(gameService, session);

    const result = gameService.confirmHiddenReveal('DRAFT1', 't3', 'p1');

    expect(result).toEqual({ error: 'NOT_THE_PICKER' });
  });
});

describe('GameService — player draft: round wrap & draft completion (Task 3.1)', () => {
  let gameService: GameService;
  beforeEach(() => { gameService = new GameService(); });

  function sessionAtLastHiddenPickReveal(overrides: Partial<GameSession> = {}): GameSession {
    return baseSession({
      currentRoundSlotIndex: 0,
      orderedHiddenDeck: [card('h0', 'GK'), card('h1', 'GK')],
      hiddenPicksTaken: new Set([0, 1]),
      currentTurnIndex: 1, // about to become 2 — wraps for a 2-player game
      turn: { turnId: 't4', phase: 'hidden_pick_reveal', activePlayerId: 'p2', activeSlotIndex: 0, candidates: [], turnStartedAt: null },
      hiddenPickReveal: { pickerPlayerId: 'p2', timeoutAt: Date.now() + 5000 },
      ...overrides,
    });
  }

  it('confirmHiddenReveal as the last hidden picker (round < totalRounds) wraps to a new round, selecting_position', () => {
    const session = sessionAtLastHiddenPickReveal({ currentRound: 5 });
    inject(gameService, session);

    const result = gameService.confirmHiddenReveal('DRAFT1', 't4', 'p2');

    expect('error' in result).toBe(false);
    if ('error' in result) return;
    expect(session.currentRound).toBe(6);
    expect(session.currentTurnIndex).toBe(0);
    expect(session.turn.phase).toBe('selecting_position');
    expect(session.currentRoundSlotIndex).toBeNull(); // cleared for the new round
  });

  it('confirmHiddenReveal completing round 11 transitions the session OUT of drafting into bench_selection (Track B step 2, regardless of pending abilities)', () => {
    const session = sessionAtLastHiddenPickReveal({ currentRound: 11, totalRounds: 11 });
    inject(gameService, session);

    const result = gameService.confirmHiddenReveal('DRAFT1', 't4', 'p2');

    expect('error' in result).toBe(false);
    if ('error' in result) return;
    expect(session.status).not.toBe('drafting');
    // Track B: drafting always advances into bench_selection first — abilities
    // (whether pending or not) only get resolved AFTER bench selection
    // completes, not immediately after drafting like the pre-Track-B flow.
    expect(session.status).toBe('bench_selection');
  });

  it('exact transition: round-11 completion always goes to bench_selection first, regardless of pending abilities — ability_activation only begins once bench selection itself completes', () => {
    const session = sessionAtLastHiddenPickReveal({
      currentRound: 11,
      totalRounds: 11,
      playerAbilities: { p1: { type: 'captain', status: 'pending' }, p2: { type: 'yellow', status: 'pending' } },
    });
    inject(gameService, session);

    gameService.confirmHiddenReveal('DRAFT1', 't4', 'p2');

    expect(session.status).toBe('bench_selection');
    // The ability-activation deadline isn't armed yet — that phase hasn't
    // started (see game.service.subs.spec.ts's "Track B phase gating"
    // describe block for the bench_selection -> ability_activation transition).
    expect(session.abilityActivationDeadlineAt).toBeNull();
  });

  it('exact transition: with NO pending abilities at all (abilities disabled), round-11 completion STILL goes to bench_selection first, not straight to lineup_edit', () => {
    const session = sessionAtLastHiddenPickReveal({
      currentRound: 11,
      totalRounds: 11,
      playerAbilities: {}, // nobody holds an ability — the disabled-abilities case
    });
    inject(gameService, session);

    gameService.confirmHiddenReveal('DRAFT1', 't4', 'p2');

    // Track B: bench_selection (step 2) always runs, even when nothing is
    // pending for ability_activation — the "skip if nothing pending" logic
    // only applies at the bench_selection -> ability_activation boundary,
    // not at the drafting -> bench_selection boundary.
    expect(session.status).toBe('bench_selection');
    expect(session.subsPhase).not.toBeNull();
  });
});

/**
 * Privacy-contract tests for buildSnapshot during the player draft — the
 * task's explicit focus is "the active player sees only what they should
 * see, and non-active players do not gain access to private draft
 * choices/order." No prior test anywhere asserted this for the draft phase
 * specifically (the ability-draft phase got the equivalent coverage in
 * game.service.ability.spec.ts). Confirmed by reading buildSnapshot's
 * `turn.candidates` field: it's personalized to whoever
 * `session.turn.activePlayerId` is, regardless of phase — these tests prove
 * that promise actually holds for 'selecting_card' (the active picker's full
 * candidate pool) and that the hidden deck (session.orderedHiddenDeck) is
 * NEVER exposed to any viewer via buildSnapshot at all, only its public,
 * card-free metadata (hiddenSlots/hiddenDeckSize/hiddenSlotsTaken).
 */
describe('GameService — player draft: buildSnapshot privacy (Task 3.1)', () => {
  let gameService: GameService;
  beforeEach(() => { gameService = new GameService(); });

  it('selecting_card: only the active picker\'s snapshot includes the candidate pool — every other viewer (and no-viewer) gets an empty array', () => {
    const pool = [card('c1', 'GK'), card('c2', 'GK')];
    const session = baseSession({
      currentRoundSlotIndex: 0,
      turn: { turnId: 't1', phase: 'selecting_card', activePlayerId: 'p1', activeSlotIndex: 0, candidates: pool, turnStartedAt: null },
    });
    inject(gameService, session);

    const activeView = gameService.buildSnapshot(session, 'p1') as any;
    expect(activeView.turn.candidates.map((c: any) => c.cardId)).toEqual(['c1', 'c2']);

    const rivalView = gameService.buildSnapshot(session, 'p2') as any;
    expect(rivalView.turn.candidates).toEqual([]);

    const publicView = gameService.buildSnapshot(session) as any;
    expect(publicView.turn.candidates).toEqual([]);
  });

  it('hidden_pick: the ordered hidden deck\'s actual cards are never present in ANY viewer\'s snapshot for untaken slots — only public, card-free slot metadata', () => {
    const deck = [card('h0', 'GK'), card('h1', 'GK')];
    const session = baseSession({
      currentRoundSlotIndex: 0,
      orderedHiddenDeck: deck,
      currentTurnIndex: 1,
      turn: { turnId: 't2', phase: 'hidden_pick', activePlayerId: 'p2', activeSlotIndex: 0, candidates: [], turnStartedAt: null },
    });
    inject(gameService, session);

    for (const viewer of ['p1', 'p2', undefined]) {
      const snap = gameService.buildSnapshot(session, viewer) as any;
      expect(snap.hiddenDeckSize).toBe(2);
      expect(snap.hiddenSlots).toHaveLength(2);
      // Untaken slots: no card data leaks to anyone, including the active
      // picker themself (they haven't picked yet — it's genuinely hidden).
      expect(snap.hiddenSlots.every((s: any) => s.card === null && !s.taken)).toBe(true);
    }
  });

  it('hidden_pick: once a slot is picked, the revealed card becomes visible to EVERY viewer (by design — hidden only until picked) while still-untaken slots stay hidden', () => {
    const deck = [card('h0', 'GK'), card('h1', 'GK')];
    const session = baseSession({
      currentRoundSlotIndex: 0,
      orderedHiddenDeck: deck,
      currentTurnIndex: 1,
      turn: { turnId: 't2', phase: 'hidden_pick', activePlayerId: 'p2', activeSlotIndex: 0, candidates: [], turnStartedAt: null },
    });
    inject(gameService, session);

    const pickResult = gameService.pickHiddenSlot('DRAFT1', 'p2', 't2', 0);
    expect('error' in pickResult).toBe(false);

    for (const viewer of ['p1', 'p2', undefined]) {
      const snap = gameService.buildSnapshot(session, viewer) as any;
      const takenSlot = snap.hiddenSlots.find((s: any) => s.slotIndex === 0);
      const untakenSlot = snap.hiddenSlots.find((s: any) => s.slotIndex === 1);
      expect(takenSlot.taken).toBe(true);
      expect(takenSlot.card.cardId).toBe('h0');
      expect(takenSlot.pickedByPlayerId).toBe('p2');
      expect(untakenSlot.taken).toBe(false);
      expect(untakenSlot.card).toBeNull();
    }
  });
});
