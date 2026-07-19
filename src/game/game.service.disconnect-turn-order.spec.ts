import { GameService } from './game.service';
import { GameSession } from './interfaces/game-session.interface';
import { PitchSlot, Pitch } from './interfaces/pitch.interface';
import { BasePositionType, SlotLabel } from './interfaces/formation.interface';

/**
 * Turn-order-is-connection-agnostic behavior (originally "Task 6", since
 * reworked — see MULTIPLAYER_ROOMS_DESIGN.md / SESSION_LOG.md for the
 * product-behavior-change history).
 *
 * BACKGROUND, confirmed by reading the real code before writing any of this:
 * a mid-game socket disconnect (rooms.gateway.ts's handleDisconnect) only
 * ever flips GamePlayer.isConnected — it never removes the player from
 * baseTurnOrder/session.players (that's the SEPARATE, already-correct
 * removePlayer() path for a PERMANENT kick/leave).
 *
 * PRODUCT RULE (current): a temporary disconnect must never leave a
 * still-in-room player with fewer drafted cards than everyone else. Turn
 * order itself is therefore connection-agnostic — `_nextIndexInRound`
 * (game.service.ts) always lands the turn on the true next player in
 * `effectiveOrder`, connected or not. What happens once a disconnected
 * player holds the turn is entirely the GATEWAY's job: `_scheduleTurnTimer`
 * detects a disconnected active player and arms a short grace timer
 * (`_scheduleDisconnectedTurnResolution`, ACTIVE_TURN_DISCONNECT_GRACE_MS)
 * that auto-picks on their behalf if they don't reconnect in time (see
 * rooms.gateway.active-turn-skip.spec.ts for that end-to-end coverage —
 * this file only pins the SERVICE-layer turn-order computation itself).
 *
 * These tests exercise the turn-order-computation half of that guarantee:
 *   1. The turn is handed DIRECTLY to a disconnected player when the normal
 *      round-robin rotation reaches them (orderHiddenDeck / confirmHiddenReveal)
 *      — it is never skipped past them anymore.
 *   2. A round where every remaining picker is disconnected does NOT wrap
 *      early — each of them still gets a turn assigned in order (the
 *      gateway is responsible for resolving each one via auto-pick; from
 *      the service layer's perspective alone, nothing is skipped).
 *   3. Normal (nobody disconnected) behavior is provably unchanged.
 *
 * A DELIBERATE scope decision, not a bug: temporary disconnects — even ALL
 * but one player — never end the session or declare a forfeit. That mirrors
 * today's existing 2-player behavior exactly (a solo remaining connected
 * player just keeps waiting for reconnects, same as a 2-player game does
 * today) — MIN_ACTIVE_PLAYERS/_tryEndGame in rooms.gateway.ts only ever
 * applies to PERMANENT removal (kick/leave_permanently).
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

function emptyPitchSlots(): PitchSlot[] {
  return FORMATION_SLOTS.map((s, index) => ({ index, label: s.label, basePositionType: s.base, card: null }));
}

function pitch(playerId: string, slots: PitchSlot[]): Pitch {
  return { playerId, slots, filledCount: slots.filter((s) => s.card).length };
}

const PLAYER_IDS_4 = ['p1', 'p2', 'p3', 'p4'];

/** A 4-player mid-draft session — connected/disconnected state fully controlled per test. */
function baseSession4(
  connected: Record<string, boolean> = { p1: true, p2: true, p3: true, p4: true },
  overrides: Partial<GameSession> = {},
): GameSession {
  return {
    sessionId: 'sess-4p',
    roomCode: 'ROOM4P',
    createdAt: Date.now(),
    leagues: [],
    playerBonusCache: new Map(),
    userChallengeCache: new Map(),
    formation: { name: '4-3-3', slots: [] } as any,
    players: PLAYER_IDS_4.map((id, i) => ({
      id,
      displayName: `Player${i + 1}`,
      isHost: i === 0,
      isConnected: connected[id] ?? true,
    })) as any,
    pitches: Object.fromEntries(PLAYER_IDS_4.map((id) => [id, pitch(id, emptyPitchSlots())])),
    baseTurnOrder: [...PLAYER_IDS_4],
    currentRound: 1,
    totalRounds: 11,
    currentTurnIndex: 0,
    currentRoundSlotIndex: 0,
    draftedCardIds: new Set(),
    roundCandidates: [],
    orderedHiddenDeck: [],
    hiddenPicksTaken: new Set(),
    hiddenPicksMap: new Map(),
    hiddenPickReveal: null,
    turn: { turnId: 't1', phase: 'selecting_position', activePlayerId: 'p1', activeSlotIndex: null, candidates: [], turnStartedAt: null },
    turnTimeoutPolicy: { enabled: false, turnSeconds: null, onExpiry: null },
    status: 'drafting',
    abilityDraft: null,
    playerAbilities: {},
    abilityActivations: [],
    abilityActivationRevealed: false,
    subSwappedCardIds: new Set(),
    isFinished: false,
    subsPhase: null,
    subsTimerSeconds: null,
    subsDeadlineAt: null,
    abilityActivationDeadlineAt: null,
    result: null,
    tournamentEnabled: false,
    simulationSpeed: 'normal',
    tournament: null,
    ...overrides,
  } as GameSession;
}

function inject(gameService: GameService, session: GameSession): void {
  (gameService as unknown as { sessions: Map<string, GameSession> }).sessions.set(session.sessionId, session);
  (gameService as unknown as { roomToSession: Map<string, string> }).roomToSession.set(session.roomCode, session.sessionId);
}

describe('GameService — turn order is connection-agnostic', () => {
  let gameService: GameService;
  beforeEach(() => { gameService = new GameService(); });

  it('orderHiddenDeck hands the turn DIRECTLY to a disconnected first hidden picker — it is not skipped past anymore', () => {
    const session = baseSession4({ p1: true, p2: false, p3: true, p4: true }, {
      turn: { turnId: 't1', phase: 'first_player_order', activePlayerId: 'p1', activeSlotIndex: 0, candidates: [], turnStartedAt: null },
      roundCandidates: [
        { cardId: 'c1', playerName: 'c1', basePositionType: 'GK', rating: 75 } as any,
      ],
    });
    inject(gameService, session);

    const result = gameService.orderHiddenDeck('ROOM4P', 'p1', 't1', ['c1']);

    expect('error' in result).toBe(false);
    if ('error' in result) return;
    // effectiveOrder for round 1 is [p1,p2,p3,p4]; currentTurnIndex becomes 1
    // (p2) and STAYS there even though p2 is disconnected — the gateway
    // (not this service call) is responsible for auto-picking on p2's
    // behalf if they don't reconnect in time.
    expect(result.session.currentTurnIndex).toBe(1);
    expect(result.session.turn.activePlayerId).toBe('p2');
    expect(result.session.turn.phase).toBe('hidden_pick');
    expect(result.availableSlots).toBeDefined();
  });

  it('confirmHiddenReveal hands the turn DIRECTLY to a disconnected next hidden picker mid-round', () => {
    const session = baseSession4({ p1: true, p2: true, p3: false, p4: true }, {
      currentTurnIndex: 1, // p2 just picked (index 1); p3 (index 2) is next, and disconnected
      orderedHiddenDeck: [
        { cardId: 'h0', playerName: 'h0', basePositionType: 'GK', rating: 70 } as any,
        { cardId: 'h1', playerName: 'h1', basePositionType: 'GK', rating: 70 } as any,
        { cardId: 'h2', playerName: 'h2', basePositionType: 'GK', rating: 70 } as any,
      ],
      hiddenPicksTaken: new Set([0]),
      turn: { turnId: 't2', phase: 'hidden_pick_reveal', activePlayerId: 'p2', activeSlotIndex: 0, candidates: [], turnStartedAt: null },
      hiddenPickReveal: { pickerPlayerId: 'p2', timeoutAt: Date.now() + 5000 },
    });
    inject(gameService, session);

    const result = gameService.confirmHiddenReveal('ROOM4P', 't2', 'p2');

    expect('error' in result).toBe(false);
    if ('error' in result) return;
    // currentTurnIndex increments to 2 (p3) and stays there — p3 is
    // disconnected, but that's the gateway's problem to resolve, not this
    // service call's.
    expect(result.session.currentTurnIndex).toBe(2);
    expect(result.session.turn.activePlayerId).toBe('p3');
    expect(result.session.turn.phase).toBe('hidden_pick');
    expect(result.nextAvailableSlots).toBeDefined();
  });

  it('a round where every remaining hidden picker is disconnected does NOT wrap early — each one still gets a turn assigned in order', () => {
    const session = baseSession4({ p1: true, p2: true, p3: false, p4: false }, {
      currentTurnIndex: 1, // p2 just picked; p3 and p4 (indices 2,3) are both disconnected
      currentRound: 1,
      totalRounds: 11,
      orderedHiddenDeck: [
        { cardId: 'h0', playerName: 'h0', basePositionType: 'GK', rating: 70 } as any,
      ],
      hiddenPicksTaken: new Set([0]),
      turn: { turnId: 't2', phase: 'hidden_pick_reveal', activePlayerId: 'p2', activeSlotIndex: 0, candidates: [], turnStartedAt: null },
      hiddenPickReveal: { pickerPlayerId: 'p2', timeoutAt: Date.now() + 5000 },
    });
    inject(gameService, session);

    const result = gameService.confirmHiddenReveal('ROOM4P', 't2', 'p2');

    expect('error' in result).toBe(false);
    if ('error' in result) return;
    // Still round 1 — the turn goes to p3 (index 2) instead of wrapping to
    // round 2, exactly as it would if p3 were connected. The gateway now
    // owns getting p3 (then p4) actually resolved via auto-pick.
    expect(session.currentRound).toBe(1);
    expect(result.session.turn.activePlayerId).toBe('p3');
    expect(result.session.currentTurnIndex).toBe(2);
    expect(result.nextAvailableSlots).toBeDefined();
  });

  it('behavior is unchanged when nobody is disconnected — a normal round wrap still lands on the correct next picker', () => {
    const session = baseSession4({ p1: true, p2: true, p3: true, p4: true }, {
      baseTurnOrder: ['p1', 'p2'],
      currentTurnIndex: 1, // 2-player game: p2 is the only hidden picker
      pitches: { p1: pitch('p1', emptyPitchSlots()), p2: pitch('p2', emptyPitchSlots()) },
      players: [
        { id: 'p1', displayName: 'Alice', isHost: true, isConnected: true } as any,
        { id: 'p2', displayName: 'Bob', isHost: false, isConnected: true } as any,
      ],
      orderedHiddenDeck: [{ cardId: 'h0', playerName: 'h0', basePositionType: 'GK', rating: 70 } as any],
      hiddenPicksTaken: new Set([0]),
      turn: { turnId: 't2', phase: 'hidden_pick_reveal', activePlayerId: 'p2', activeSlotIndex: 0, candidates: [], turnStartedAt: null },
      hiddenPickReveal: { pickerPlayerId: 'p2', timeoutAt: Date.now() + 5000 },
    });
    inject(gameService, session);

    const result = gameService.confirmHiddenReveal('ROOM4P', 't2', 'p2');

    expect('error' in result).toBe(false);
    if ('error' in result) return;
    // Exactly the pre-existing 2-player behavior: currentTurnIndex(1)+1 >= n(2) → round wraps.
    expect(session.currentRound).toBe(2);
    expect(result.session.turn.phase).toBe('selecting_position');
    expect(result.session.turn.activePlayerId).toBe('p2'); // round 2 rotates to start at p2
  });

  it('with only one player still connected, the sole survivor still gets assigned turns in order (no new forfeit rule for temporary disconnects)', () => {
    const session = baseSession4({ p1: true, p2: false, p3: false, p4: false }, {
      currentTurnIndex: 1,
      orderedHiddenDeck: [{ cardId: 'h0', playerName: 'h0', basePositionType: 'GK', rating: 70 } as any],
      turn: { turnId: 't2', phase: 'hidden_pick_reveal', activePlayerId: 'p2', activeSlotIndex: 0, candidates: [], turnStartedAt: null },
      hiddenPickReveal: { pickerPlayerId: 'p2', timeoutAt: Date.now() + 5000 },
      hiddenPicksTaken: new Set(),
    });
    inject(gameService, session);

    const result = gameService.confirmHiddenReveal('ROOM4P', 't2', 'p2');

    expect('error' in result).toBe(false);
    if ('error' in result) return;
    // Turn goes to p3 next (index 2), disconnected or not — the gateway
    // will chain through p3 then p4 via auto-pick before finally reaching
    // the connected p1 again. Session never force-ends or declares a
    // forfeit for this.
    expect(result.session.isFinished).toBe(false);
    expect(result.session.status).toBe('drafting');
    expect(result.session.turn.activePlayerId).toBe('p3');
    expect(result.session.currentTurnIndex).toBe(2);
  });
});
