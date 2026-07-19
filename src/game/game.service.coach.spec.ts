import { GameService } from './game.service';
import { GameSession } from './interfaces/game-session.interface';
import { PitchSlot, Pitch } from './interfaces/pitch.interface';
import { DraftCard } from './interfaces/draft-card.interface';
import { BasePositionType, SlotLabel } from './interfaces/formation.interface';
import { cardFitsSlot } from './scoring';

/**
 * Coach ability semantics. Coach adds ONE new non-GK position to one of the
 * caster's OWN non-GK players for the rest of the match; from then on that
 * player is treated exactly as if they naturally had it. Effect is deferred to
 * the reveal pass (like `sub`) and applied by pushing the position onto the
 * card's own `naturalPositions`/`altPositions`, so every downstream fit path
 * (scoring's `cardFitsSlot`, the service's swap/confirm validation, the client)
 * treats it as a real alt with no extra wiring. GK is excluded on both sides;
 * a card can be coached at most once (once per player).
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

function activationSession(overrides: Partial<GameSession> = {}): GameSession {
  return {
    sessionId: 'sess-coach',
    roomCode: 'COACH1',
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
    status: 'ability_activation',
    abilityDraft: null,
    playerAbilities: {
      p1: { type: 'coach', status: 'pending' },
      p2: { type: 'captain', status: 'pending' },
    },
    abilityActivations: [],
    abilityActivationRevealed: false,
    subSwappedCardIds: new Set(),
    coachedPositions: {},
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

/** Resolves p2's ability and runs the reveal pass so deferred effects apply. */
function resolveAndReveal(gameService: GameService): GameSession {
  gameService.discardAbility('COACH1', 'p2');
  const revealResult = gameService.revealAbilityActivations('COACH1');
  if ('error' in revealResult) throw new Error(revealResult.error);
  return revealResult.session;
}

describe('GameService — Coach ability', () => {
  let gameService: GameService;

  beforeEach(() => {
    gameService = new GameService();
  });

  it('commits by tracking the targeted OWN card id + new position, without touching the board yet (hidden until reveal)', () => {
    const session = activationSession();
    inject(gameService, session);
    const lbCardId = session.pitches.p1.slots[1].card!.cardId; // A-LB-1

    const result = gameService.activateAbility('COACH1', 'p1', { ownSlotIndex: 1, coachedPosition: 'RB' });

    expect('error' in result).toBe(false);
    if ('error' in result) return;
    expect(session.playerAbilities.p1.status).toBe('used');
    expect(session.playerAbilities.p1.sourceSlotIndex).toBe(1);
    expect(session.playerAbilities.p1.targetPlayerId).toBe(lbCardId);
    expect(session.playerAbilities.p1.coachedPosition).toBe('RB');
    // Deferred: the position is NOT on the card yet, and nothing is logged.
    expect(session.pitches.p1.slots[1].card!.naturalPositions).toEqual(['LB']);
    expect(session.coachedPositions[lbCardId]).toBeUndefined();
    expect(session.abilityActivations).toHaveLength(0);
  });

  it('at reveal, adds the new position to the card so it is treated exactly like a natural alt (naturalPositions + altPositions + scoring cardFitsSlot)', () => {
    const session = activationSession();
    inject(gameService, session);
    const lbCardId = session.pitches.p1.slots[1].card!.cardId;

    gameService.activateAbility('COACH1', 'p1', { ownSlotIndex: 1, coachedPosition: 'RB' });
    const revealed = resolveAndReveal(gameService);

    const coachedCard = revealed.pitches.p1.slots[1].card!;
    expect(coachedCard.naturalPositions).toEqual(['LB', 'RB']);
    expect(coachedCard.altPositions).toEqual(['RB']);
    expect(revealed.coachedPositions[lbCardId]).toBe('RB');
    // Scoring treats the coached player as legally fitting an RB slot.
    expect(cardFitsSlot({ index: 99, label: 'RB', basePositionType: 'RB', card: coachedCard })).toBe(true);
    // The public log records the coach (no board swap, unlike sub).
    const log = revealed.abilityActivations.find((a) => a.byPlayerId === 'p1');
    expect(log).toMatchObject({ type: 'coach' });
    expect(revealed.subSwappedCardIds.size).toBe(0);
  });

  it('the coached position FOLLOWS THE CARD through a subs-phase swap (card identity, not slot)', () => {
    const session = activationSession();
    inject(gameService, session);
    const coachedCardId = session.pitches.p1.slots[1].card!.cardId; // A-LB-1

    // Coach the LB, adding LW.
    gameService.activateAbility('COACH1', 'p1', { ownSlotIndex: 1, coachedPosition: 'LW' });
    resolveAndReveal(gameService);
    // Sanity: the LB card now has LW.
    expect(session.pitches.p1.slots[1].card!.naturalPositions).toContain('LW');

    // Transition into lineup_edit and swap the coached LB (slot 1) with the
    // LW starter (slot 8) — a pitch↔pitch move of that same card object.
    session.status = 'lineup_edit';
    session.subsPhase = {
      userSubs: {
        p1: { isComplete: false, lineupConfirmed: false, hasExtraBench: false },
        p2: { isComplete: false, lineupConfirmed: false, hasExtraBench: false },
      },
    } as any;

    const swap = gameService.swapRoster(
      'COACH1', 'p1',
      { kind: 'pitch', index: 1 },
      { kind: 'pitch', index: 8 }, // LW slot
    );
    expect('error' in swap).toBe(false);

    // The coached card is now in the LW slot — and it STILL carries LW (and its
    // coachedPositions record is unchanged, keyed by card id).
    const movedSlot = session.pitches.p1.slots[8];
    expect(movedSlot.card!.cardId).toBe(coachedCardId);
    expect(movedSlot.card!.naturalPositions).toContain('LW');
    expect(cardFitsSlot(movedSlot)).toBe(true); // legally fits its new LW slot
    expect(session.coachedPositions[coachedCardId]).toBe('LW');
  });

  it('still applies (position follows the card) when an EARLIER sub in the same reveal pass moved the coached card to another pitch', () => {
    // baseTurnOrder [p2, p1] → p2's sub reveals BEFORE p1's coach. p2 subs its
    // own LB (slot 1) with p1's LB (slot 1) — moving p1's coached card onto
    // p2's pitch. Coach must then find that card by id wherever it landed.
    const session = activationSession({
      baseTurnOrder: ['p2', 'p1'],
      playerAbilities: {
        p1: { type: 'coach', status: 'pending' },
        p2: { type: 'sub', status: 'pending' },
      },
    });
    inject(gameService, session);
    const coachedCardId = session.pitches.p1.slots[1].card!.cardId; // p1's LB

    gameService.activateAbility('COACH1', 'p1', { ownSlotIndex: 1, coachedPosition: 'LW' });
    gameService.activateAbility('COACH1', 'p2', { ownSlotIndex: 1, targetUserId: 'p1', targetSlotIndex: 1 });
    const revealResult = gameService.revealAbilityActivations('COACH1');
    if ('error' in revealResult) throw new Error(revealResult.error);
    const revealed = revealResult.session;

    // The coached card is now on p2's pitch (moved by the sub) — and it STILL
    // received LW: coach found it by id across pitches rather than fizzling.
    const moved = revealed.pitches.p2.slots.find((s) => s.card?.cardId === coachedCardId);
    expect(moved).toBeDefined();
    expect(moved!.card!.naturalPositions).toContain('LW');
    expect(revealed.coachedPositions[coachedCardId]).toBe('LW');
  });

  it('rejects coaching a GK (CANNOT_COACH_GK) — GK excluded on the target side', () => {
    const session = activationSession();
    inject(gameService, session);
    // slot 0 is the GK.
    const result = gameService.activateAbility('COACH1', 'p1', { ownSlotIndex: 0, coachedPosition: 'CB' });
    expect(result).toEqual({ error: 'CANNOT_COACH_GK' });
    expect(session.playerAbilities.p1.status).toBe('pending');
  });

  it('rejects adding GK as the new position (INVALID_COACH_POSITION) — GK excluded on the added side', () => {
    const session = activationSession();
    inject(gameService, session);
    const result = gameService.activateAbility('COACH1', 'p1', { ownSlotIndex: 1, coachedPosition: 'GK' });
    expect(result).toEqual({ error: 'INVALID_COACH_POSITION' });
  });

  it('rejects a non-existent / malformed new position (INVALID_COACH_POSITION)', () => {
    const session = activationSession();
    inject(gameService, session);
    const result = gameService.activateAbility('COACH1', 'p1', { ownSlotIndex: 1, coachedPosition: 'ZZ' });
    expect(result).toEqual({ error: 'INVALID_COACH_POSITION' });
  });

  it('rejects a position the player already has in primary or alt (POSITION_ALREADY_OWNED)', () => {
    const session = activationSession();
    // Give the LB card an existing alt of RM.
    session.pitches.p1.slots[1].card!.naturalPositions = ['LB', 'RM'];
    session.pitches.p1.slots[1].card!.altPositions = ['RM'];
    inject(gameService, session);
    // Primary is owned.
    expect(gameService.activateAbility('COACH1', 'p1', { ownSlotIndex: 1, coachedPosition: 'LB' }))
      .toEqual({ error: 'POSITION_ALREADY_OWNED' });
    // Existing alt is owned too.
    expect(gameService.activateAbility('COACH1', 'p1', { ownSlotIndex: 1, coachedPosition: 'RM' }))
      .toEqual({ error: 'POSITION_ALREADY_OWNED' });
  });

  it('rejects coaching a card that is already coached — once per player (POSITION_ALREADY_OWNED)', () => {
    const session = activationSession();
    const lbCardId = session.pitches.p1.slots[1].card!.cardId;
    session.coachedPositions[lbCardId] = 'RB'; // already coached earlier
    inject(gameService, session);
    const result = gameService.activateAbility('COACH1', 'p1', { ownSlotIndex: 1, coachedPosition: 'CM' });
    expect(result).toEqual({ error: 'POSITION_ALREADY_OWNED' });
  });

  it('rejects an empty own slot (INVALID_TARGET)', () => {
    const session = activationSession();
    session.pitches.p1.slots[1] = { ...session.pitches.p1.slots[1], card: null };
    inject(gameService, session);
    const result = gameService.activateAbility('COACH1', 'p1', { ownSlotIndex: 1, coachedPosition: 'RB' });
    expect(result).toEqual({ error: 'INVALID_TARGET' });
  });

  it('does NOT shield the coached player from other effects — the coached card can still be red-carded (coach only adds a position, never protection)', () => {
    const session = activationSession({
      playerAbilities: {
        p1: { type: 'coach', status: 'pending' },
        p2: { type: 'red', status: 'pending' },
      },
    });
    inject(gameService, session);
    const coachedCardId = session.pitches.p1.slots[1].card!.cardId;

    gameService.activateAbility('COACH1', 'p1', { ownSlotIndex: 1, coachedPosition: 'RB' });
    // p2 red-cards the very card p1 just coached.
    gameService.activateAbility('COACH1', 'p2', { targetUserId: 'p1', targetSlotIndex: 1 });
    const revealResult = gameService.revealAbilityActivations('COACH1');
    if ('error' in revealResult) throw new Error(revealResult.error);
    const revealed = revealResult.session;

    // Red still tracks the coached card (no immunity granted by coach).
    expect(revealed.playerAbilities.p2.targetPlayerId).toBe(coachedCardId);
    // And the coaching still applied (both effects coexist).
    expect(revealed.pitches.p1.slots[1].card!.naturalPositions).toContain('RB');
    expect(revealed.coachedPositions[coachedCardId]).toBe('RB');
  });

  it('exposes coachedPositions + the coached card\'s new naturalPositions in the snapshot so the client can render fit correctly', () => {
    const session = activationSession();
    inject(gameService, session);
    const lbCardId = session.pitches.p1.slots[1].card!.cardId;

    gameService.activateAbility('COACH1', 'p1', { ownSlotIndex: 1, coachedPosition: 'RB' });
    resolveAndReveal(gameService);

    const snap = gameService.buildSnapshot(session, 'p1') as any;
    expect(snap.coachedPositions[lbCardId]).toBe('RB');
    expect(snap.pitches.p1.slots[1].card.naturalPositions).toEqual(['LB', 'RB']);
  });
});
