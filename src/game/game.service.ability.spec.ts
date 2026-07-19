import { GameService } from './game.service';
import { GameSession } from './interfaces/game-session.interface';
import { PitchSlot, Pitch } from './interfaces/pitch.interface';
import { DraftCard } from './interfaces/draft-card.interface';
import { BasePositionType, SlotLabel } from './interfaces/formation.interface';

/**
 * Ability state machine tests (Task 2.5) — the most complex stateful logic
 * in the game. Read pickAbilityCard/beginPlayerDraft/activateAbility/
 * discardAbility/_maybeFinishActivation in game.service.ts in full before
 * writing any of these (not from memory). Two real findings from that
 * reading directly shaped the test structure below, not assumptions:
 *
 * - pickAbilityCard() does NOT transition the session out of ability_draft
 *   itself, even for the final picker — it only returns `allPicked: true`.
 *   The actual transition is a SEPARATE method, beginPlayerDraft(roomCode),
 *   called later by the gateway after a 3.5s reveal-window timer (see
 *   rooms.gateway.ts's `_afterAbilityPick`/`_abilityRevealTimers`, already
 *   covered by rooms.gateway.spec.ts's Phase-0-era timer tests). So "session
 *   transitions to drafting after the reveal window" is tested here as two
 *   separate, precise steps: pickAbilityCard leaves status unchanged, then
 *   beginPlayerDraft (the real transition function) flips it.
 * - Auto-pick via the timer (`_autoPickAbilityDraft` in rooms.gateway.ts) is
 *   a thin wrapper that just selects a random remaining card and calls this
 *   same pickAbilityCard() — already covered, including the "final picker,
 *   no error" case, by rooms.gateway.spec.ts's existing
 *   "RoomsGateway — ability-draft timeout" describe block. Not duplicated
 *   here; one complementary case (auto-pick for a NON-final picker, which
 *   that existing suite doesn't cover) is added there isn't needed again at
 *   this layer since the picking logic itself (pickAbilityCard) is exactly
 *   what's under test in this file regardless of who calls it.
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

function baseSession(overrides: Partial<GameSession> = {}): GameSession {
  return {
    sessionId: 'sess-ability',
    roomCode: 'ABLTY1',
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
    status: 'ability_draft',
    abilityDraft: { pool: [{ id: 0, type: 'captain', pickedBy: null }, { id: 1, type: 'yellow', pickedBy: null }], pickOrder: ['p1', 'p2'], currentPickIndex: 0 },
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
    ...overrides,
  } as GameSession;
}

function inject(gameService: GameService, session: GameSession): void {
  (gameService as unknown as { sessions: Map<string, GameSession> }).sessions.set(session.sessionId, session);
  (gameService as unknown as { roomToSession: Map<string, string> }).roomToSession.set(session.roomCode, session.sessionId);
}

describe('GameService — ability draft state machine (Task 2.5)', () => {
  let gameService: GameService;

  beforeEach(() => {
    gameService = new GameService();
  });

  it('pickAbilityCard with a valid card on your turn records the pick and advances the turn index', () => {
    const session = baseSession();
    inject(gameService, session);

    const result = gameService.pickAbilityCard('ABLTY1', 'p1', 0);

    expect('error' in result).toBe(false);
    if ('error' in result) return;
    expect(result.allPicked).toBe(false);
    expect(session.playerAbilities.p1).toEqual({ type: 'captain', status: 'pending' });
    expect(session.abilityDraft!.pool[0].pickedBy).toBe('p1');
    expect(session.abilityDraft!.currentPickIndex).toBe(1);
  });

  it('pickAbilityCard out of turn is rejected with NOT_YOUR_TURN, and nothing changes', () => {
    const session = baseSession(); // currentPickIndex 0 → p1's turn
    inject(gameService, session);

    const result = gameService.pickAbilityCard('ABLTY1', 'p2', 1);

    expect(result).toEqual({ error: 'NOT_YOUR_TURN' });
    expect(session.abilityDraft!.currentPickIndex).toBe(0);
    expect(session.playerAbilities.p2).toBeUndefined();
  });

  it('pickAbilityCard for a card already picked by another player is rejected with INVALID_CARD', () => {
    const session = baseSession({
      abilityDraft: { pool: [{ id: 0, type: 'captain', pickedBy: 'p1' }, { id: 1, type: 'yellow', pickedBy: null }], pickOrder: ['p1', 'p2'], currentPickIndex: 1 },
    });
    inject(gameService, session);

    const result = gameService.pickAbilityCard('ABLTY1', 'p2', 0); // card 0 already taken

    expect(result).toEqual({ error: 'INVALID_CARD' });
  });

  it('pickAbilityCard as the last player reports allPicked but does NOT itself transition status — beginPlayerDraft does, separately', () => {
    const session = baseSession({
      abilityDraft: { pool: [{ id: 0, type: 'captain', pickedBy: 'p1' }, { id: 1, type: 'yellow', pickedBy: null }], pickOrder: ['p1', 'p2'], currentPickIndex: 1 },
    });
    inject(gameService, session);

    const pickResult = gameService.pickAbilityCard('ABLTY1', 'p2', 1);
    expect('error' in pickResult).toBe(false);
    if ('error' in pickResult) return;
    expect(pickResult.allPicked).toBe(true);
    expect(session.status).toBe('ability_draft'); // not yet transitioned

    const beginResult = gameService.beginPlayerDraft('ABLTY1');
    expect('error' in beginResult).toBe(false);
    if ('error' in beginResult) return;
    expect(beginResult.session.status).toBe('drafting');
    expect(beginResult.session.abilityDraft).toBeNull();
  });

  it('beginPlayerDraft is rejected if called when the session is not actually in ability_draft', () => {
    const session = baseSession({ status: 'drafting', abilityDraft: null });
    inject(gameService, session);

    expect(gameService.beginPlayerDraft('ABLTY1')).toEqual({ error: 'NOT_ABILITY_DRAFT' });
  });
});

/**
 * buildSnapshot's per-viewer privacy contract during ability_draft — the
 * single most safety-critical guarantee in this phase (hidden ability info
 * must never leak to the wrong player) had ZERO direct test coverage before
 * this pass, despite `_buildAbilityDraftSnapshot`'s doc comment explicitly
 * promising it. Every case below is verified against the actual current
 * `buildSnapshot`/`_buildAbilityDraftSnapshot` source, not assumed from the
 * doc comment alone: `pickedBy` (WHO picked a card) is intentionally public
 * on every card regardless of viewer — the client needs it to render
 * "waiting for X to choose"/dim already-taken cards — only `type` (WHAT
 * they picked) and the top-level `myAbility` field are viewer-scoped.
 */
describe('GameService — ability draft snapshot privacy (buildSnapshot)', () => {
  let gameService: GameService;

  beforeEach(() => {
    gameService = new GameService();
  });

  it('before anyone has picked, no card reveals a type to anyone — own view or otherwise', () => {
    const session = baseSession(); // untouched: both cards pickedBy: null
    inject(gameService, session);

    for (const viewer of ['p1', 'p2', undefined]) {
      const snap = gameService.buildSnapshot(session, viewer) as any;
      expect(snap.abilityDraft.cards.every((c: any) => c.type === null)).toBe(true);
      expect(snap.myAbility).toBeNull();
    }
  });

  it("a player's own snapshot reveals their own picked card's type", () => {
    const session = baseSession();
    inject(gameService, session);
    gameService.pickAbilityCard('ABLTY1', 'p1', 0); // captain

    const own = gameService.buildSnapshot(session, 'p1') as any;
    const myCard = own.abilityDraft.cards.find((c: any) => c.id === 0);
    expect(myCard.pickedBy).toBe('p1'); // public: who picked it
    expect(myCard.type).toBe('captain'); // private-but-mine: what it is
    expect(own.myAbility).toEqual({ type: 'captain', status: 'pending' });
  });

  it("another player's snapshot of the SAME session shows who picked it but never what it is", () => {
    const session = baseSession();
    inject(gameService, session);
    gameService.pickAbilityCard('ABLTY1', 'p1', 0); // captain

    const rival = gameService.buildSnapshot(session, 'p2') as any;
    const p1Card = rival.abilityDraft.cards.find((c: any) => c.id === 0);
    expect(p1Card.pickedBy).toBe('p1'); // public — p2 can see p1 has chosen
    expect(p1Card.type).toBeNull(); // private — p2 must never see WHAT p1 chose
    // p2's own field is unaffected by p1's pick — still nothing to show them.
    expect(rival.myAbility).toBeNull();
  });

  it('once BOTH players have picked, each snapshot reveals only the viewer\'s own card — never the other\'s', () => {
    const session = baseSession();
    inject(gameService, session);
    gameService.pickAbilityCard('ABLTY1', 'p1', 0); // captain
    gameService.pickAbilityCard('ABLTY1', 'p2', 1); // yellow

    const p1View = gameService.buildSnapshot(session, 'p1') as any;
    expect(p1View.myAbility).toEqual({ type: 'captain', status: 'pending' });
    expect(p1View.abilityDraft.cards.find((c: any) => c.id === 0).type).toBe('captain');
    expect(p1View.abilityDraft.cards.find((c: any) => c.id === 1).type).toBeNull();

    const p2View = gameService.buildSnapshot(session, 'p2') as any;
    expect(p2View.myAbility).toEqual({ type: 'yellow', status: 'pending' });
    expect(p2View.abilityDraft.cards.find((c: any) => c.id === 1).type).toBe('yellow');
    expect(p2View.abilityDraft.cards.find((c: any) => c.id === 0).type).toBeNull();
  });

  it('a snapshot with no localPlayerId (e.g. an unauthenticated/public broadcast context) reveals nothing private for anyone', () => {
    const session = baseSession();
    inject(gameService, session);
    gameService.pickAbilityCard('ABLTY1', 'p1', 0);
    gameService.pickAbilityCard('ABLTY1', 'p2', 1);

    const publicView = gameService.buildSnapshot(session) as any;
    expect(publicView.myAbility).toBeNull();
    expect(publicView.abilityDraft.cards.every((c: any) => c.type === null)).toBe(true);
    // Public info (who picked what slot) is still present — this isn't a
    // blanket redaction of the whole draft, only of card identity/type.
    expect(publicView.abilityDraft.cards.find((c: any) => c.id === 0).pickedBy).toBe('p1');
    expect(publicView.abilityDraft.cards.find((c: any) => c.id === 1).pickedBy).toBe('p2');
  });

  it('a resolved (used/discarded) ability in playerAbilities is still never exposed as myAbility to anyone but its owner', () => {
    const session = baseSession();
    inject(gameService, session);
    gameService.pickAbilityCard('ABLTY1', 'p1', 0);
    session.playerAbilities['p1'].status = 'used'; // simulate activation resolving it

    expect((gameService.buildSnapshot(session, 'p1') as any).myAbility).toEqual({
      type: 'captain',
      status: 'used',
    });
    expect((gameService.buildSnapshot(session, 'p2') as any).myAbility).toBeNull();
  });
});

describe('GameService — ability activation state machine (Task 2.5)', () => {
  let gameService: GameService;

  function activationSession(overrides: Partial<GameSession> = {}): GameSession {
    return baseSession({
      status: 'ability_activation',
      abilityDraft: null,
      playerAbilities: {
        p1: { type: 'yellow', status: 'pending' },
        p2: { type: 'captain', status: 'pending' },
      },
      ...overrides,
    });
  }

  beforeEach(() => {
    gameService = new GameService();
  });

  it('activateAbility (yellow) with a valid target marks it used and freezes a pendingSummary, but does NOT publish an activation log entry yet — hidden until every player commits and reveal runs', () => {
    const session = activationSession();
    inject(gameService, session);

    const result = gameService.activateAbility('ABLTY1', 'p1', { targetUserId: 'p2' });

    expect('error' in result).toBe(false);
    if ('error' in result) return;
    expect(session.playerAbilities.p1.status).toBe('used');
    expect(session.playerAbilities.p1.targetUserId).toBe('p2');
    expect(typeof session.playerAbilities.p1.pendingSummary).toBe('string');
    expect(session.abilityActivations).toHaveLength(0);
    expect(result.allResolved).toBe(false); // p2 still pending
  });

  it('discardAbility marks the ability discarded and resolves the player without an activation log entry', () => {
    const session = activationSession();
    inject(gameService, session);

    const result = gameService.discardAbility('ABLTY1', 'p1');

    expect('error' in result).toBe(false);
    if ('error' in result) return;
    expect(session.playerAbilities.p1.status).toBe('discarded');
    expect(session.abilityActivations).toHaveLength(0);
    expect(result.allResolved).toBe(false); // p2 still pending
  });

  it('activateAbility (yellow) with an invalid target (targeting yourself) is rejected with INVALID_TARGET, ability stays pending', () => {
    const session = activationSession();
    inject(gameService, session);

    const result = gameService.activateAbility('ABLTY1', 'p1', { targetUserId: 'p1' });

    expect(result).toEqual({ error: 'INVALID_TARGET' });
    expect(session.playerAbilities.p1.status).toBe('pending');
  });

  it('activateAbility (yellow) targeting a playerId not in the room is rejected with INVALID_TARGET', () => {
    const session = activationSession();
    inject(gameService, session);

    const result = gameService.activateAbility('ABLTY1', 'p1', { targetUserId: 'not-a-real-player' });

    expect(result).toEqual({ error: 'INVALID_TARGET' });
  });

  it('activateAbility (captain) with an empty own slot is rejected with INVALID_TARGET', () => {
    const session = activationSession();
    session.pitches.p2.slots[0] = { ...session.pitches.p2.slots[0], card: null }; // empty the GK slot
    inject(gameService, session);

    const result = gameService.activateAbility('ABLTY1', 'p2', { ownSlotIndex: 0 });

    expect(result).toEqual({ error: 'INVALID_TARGET' });
  });

  it('activateAbility after the ability already resolved (used) is rejected with NO_PENDING_ABILITY', () => {
    const session = activationSession();
    inject(gameService, session);

    const first = gameService.activateAbility('ABLTY1', 'p1', { targetUserId: 'p2' });
    expect('error' in first).toBe(false);

    const second = gameService.activateAbility('ABLTY1', 'p1', { targetUserId: 'p2' });
    expect(second).toEqual({ error: 'NO_PENDING_ABILITY' });
  });

  it('discardAbility after the ability already resolved (discarded) is rejected with NO_PENDING_ABILITY', () => {
    const session = activationSession();
    inject(gameService, session);

    gameService.discardAbility('ABLTY1', 'p1');
    const second = gameService.discardAbility('ABLTY1', 'p1');

    expect(second).toEqual({ error: 'NO_PENDING_ABILITY' });
  });

  // ── Cross-cutting: hidden commit → reveal → finish is three explicit
  // steps now, not one auto-transition. `allResolved` flips true once the
  // LAST player commits, but status stays `ability_activation` — and
  // abilityActivations stays empty — until revealAbilityActivations runs,
  // and status only flips to `subs` once finishAbilityActivation runs. ────
  it('the session stays in ability_activation (log hidden) after only SOME players resolve; allResolved flips true once the LAST one does, but nothing is revealed or finished automatically', () => {
    const session = activationSession();
    inject(gameService, session);

    const afterP1 = gameService.discardAbility('ABLTY1', 'p1');
    expect('error' in afterP1).toBe(false);
    if ('error' in afterP1) return;
    expect(afterP1.session.status).toBe('ability_activation'); // p2 still pending
    expect(afterP1.allResolved).toBe(false);

    const afterP2 = gameService.activateAbility('ABLTY1', 'p2', { ownSlotIndex: 0 });
    expect('error' in afterP2).toBe(false);
    if ('error' in afterP2) return;
    expect(afterP2.allResolved).toBe(true); // now everyone resolved
    expect(afterP2.session.status).toBe('ability_activation'); // NOT auto-transitioned
    expect(afterP2.session.abilityActivations).toHaveLength(0); // still hidden

    // Calling reveal before this point would be premature per allResolved,
    // but the service itself also refuses it independently.
    const revealResult = gameService.revealAbilityActivations('ABLTY1');
    expect('error' in revealResult).toBe(false);
    if ('error' in revealResult) return;
    expect(revealResult.session.status).toBe('ability_activation'); // still not subs
    expect(revealResult.session.abilityActivationRevealed).toBe(true);
    expect(revealResult.session.abilityActivations).toHaveLength(1); // p1 discarded (silent), p2 used (logged)
    expect(revealResult.session.abilityActivations[0]).toMatchObject({ byPlayerId: 'p2', type: 'captain' });

    const finishResult = gameService.finishAbilityActivation('ABLTY1');
    expect('error' in finishResult).toBe(false);
    if ('error' in finishResult) return;
    expect(finishResult.session.status).toBe('lineup_edit');
    expect(finishResult.session.subsPhase).not.toBeNull();
  });

  it('revealAbilityActivations is rejected with ABILITIES_STILL_PENDING if called before every player has committed', () => {
    const session = activationSession(); // p1 + p2 both pending
    inject(gameService, session);

    const result = gameService.revealAbilityActivations('ABLTY1');

    expect(result).toEqual({ error: 'ABILITIES_STILL_PENDING' });
    expect(session.abilityActivationRevealed).toBe(false);
  });

  it('forceFinalizeAbilityActivation (already covered in game.service.spec.ts) auto-discards pending abilities and reveals — cross-checked here against activateAbility/discardAbility for consistency: a player who already resolved is left untouched by it', () => {
    const session = activationSession();
    inject(gameService, session);
    gameService.discardAbility('ABLTY1', 'p1'); // p1 resolves normally first

    const result = gameService.forceFinalizeAbilityActivation('ABLTY1');

    expect('error' in result).toBe(false);
    if ('error' in result) return;
    expect(result.session.playerAbilities.p1.status).toBe('discarded'); // untouched, already resolved
    expect(result.session.playerAbilities.p2.status).toBe('discarded'); // force-discarded (was pending)
    expect(result.session.status).toBe('lineup_edit');
    expect(result.session.abilityActivationRevealed).toBe(true);
    expect(result.session.abilityActivations).toHaveLength(0); // both ended up discarded — nothing to log
  });

  it('forceFinalizeAbilityActivation still reveals a `used` ability that was committed but never got a chance to reveal normally (e.g. only one player ever acted before the deadline) — the swap/log must not be silently lost', () => {
    const session = activationSession({
      playerAbilities: { p1: { type: 'sub', status: 'pending' }, p2: { type: 'yellow', status: 'pending' } },
    });
    inject(gameService, session);
    const myCardId = session.pitches.p1.slots[0].card!.cardId;
    const rivalCardId = session.pitches.p2.slots[0].card!.cardId;

    const committed = gameService.activateAbility('ABLTY1', 'p1', {
      ownSlotIndex: 0,
      targetUserId: 'p2',
      targetSlotIndex: 0,
    });
    expect('error' in committed).toBe(false);
    if ('error' in committed) return;
    expect(committed.allResolved).toBe(false); // p2 never acts — deadline expires instead
    // Board untouched immediately after commit.
    expect(session.pitches.p1.slots[0].card!.cardId).toBe(myCardId);

    const result = gameService.forceFinalizeAbilityActivation('ABLTY1');

    expect('error' in result).toBe(false);
    if ('error' in result) return;
    expect(result.session.playerAbilities.p2.status).toBe('discarded'); // auto-discarded by the timeout
    // p1's committed sub still gets revealed and applied, not lost.
    expect(result.session.pitches.p1.slots[0].card!.cardId).toBe(rivalCardId);
    expect(result.session.pitches.p2.slots[0].card!.cardId).toBe(myCardId);
    expect(result.session.abilityActivations).toHaveLength(1);
    expect(result.session.abilityActivations[0]).toMatchObject({ byPlayerId: 'p1', type: 'sub' });
    expect(result.session.status).toBe('lineup_edit');
  });

  // ── red: targeting legality + effect tracking ───────────────────────────
  it('activateAbility (red) on a filled rival slot marks it used and tracks the target CARD id (so it follows the card if moved)', () => {
    const session = activationSession({
      playerAbilities: { p1: { type: 'red', status: 'pending' }, p2: { type: 'yellow', status: 'pending' } },
    });
    inject(gameService, session);
    const targetCardId = session.pitches.p2.slots[0].card!.cardId; // p2's GK

    const result = gameService.activateAbility('ABLTY1', 'p1', { targetUserId: 'p2', targetSlotIndex: 0 });

    expect('error' in result).toBe(false);
    if ('error' in result) return;
    expect(session.playerAbilities.p1.status).toBe('used');
    expect(session.playerAbilities.p1.targetUserId).toBe('p2');
    expect(session.playerAbilities.p1.targetSlotIndex).toBe(0);
    expect(session.playerAbilities.p1.targetPlayerId).toBe(targetCardId);
    // Hidden until reveal — nothing published to the public log yet.
    expect(session.abilityActivations).toHaveLength(0);
  });

  it('activateAbility (red) on an EMPTY rival slot is rejected with INVALID_TARGET, ability stays pending', () => {
    const session = activationSession({
      playerAbilities: { p1: { type: 'red', status: 'pending' }, p2: { type: 'yellow', status: 'pending' } },
    });
    session.pitches.p2.slots[0] = { ...session.pitches.p2.slots[0], card: null };
    inject(gameService, session);

    const result = gameService.activateAbility('ABLTY1', 'p1', { targetUserId: 'p2', targetSlotIndex: 0 });

    expect(result).toEqual({ error: 'INVALID_TARGET' });
    expect(session.playerAbilities.p1.status).toBe('pending');
  });

  it('activateAbility (red) targeting your OWN slot is rejected with INVALID_TARGET — red can only target a rival', () => {
    const session = activationSession({
      playerAbilities: { p1: { type: 'red', status: 'pending' }, p2: { type: 'yellow', status: 'pending' } },
    });
    inject(gameService, session);

    const result = gameService.activateAbility('ABLTY1', 'p1', { targetUserId: 'p1', targetSlotIndex: 0 });

    expect(result).toEqual({ error: 'INVALID_TARGET' });
  });

  // ── sub: same-position legality + deferred (reveal-time) swap effect ────
  it('activateAbility (sub) commits without touching the board (hidden from the rival while they still decide); revealAbilityActivations then swaps the two cards and tracks both card ids as swapped', () => {
    const session = activationSession({
      playerAbilities: { p1: { type: 'sub', status: 'pending' }, p2: { type: 'yellow', status: 'pending' } },
    });
    inject(gameService, session);
    const myCardId = session.pitches.p1.slots[0].card!.cardId; // A-GK-0
    const rivalCardId = session.pitches.p2.slots[0].card!.cardId; // B-GK-0

    const result = gameService.activateAbility('ABLTY1', 'p1', { ownSlotIndex: 0, targetUserId: 'p2', targetSlotIndex: 0 });

    expect('error' in result).toBe(false);
    if ('error' in result) return;
    expect(session.playerAbilities.p1.status).toBe('used');
    // Board untouched at commit time — this is what keeps it hidden from p2
    // while they're still deciding their own ability.
    expect(session.pitches.p1.slots[0].card!.cardId).toBe(myCardId);
    expect(session.pitches.p2.slots[0].card!.cardId).toBe(rivalCardId);
    expect(session.subSwappedCardIds.size).toBe(0);
    expect(result.allResolved).toBe(false); // p2 still pending

    const afterP2 = gameService.discardAbility('ABLTY1', 'p2');
    expect('error' in afterP2).toBe(false);
    if ('error' in afterP2) return;
    expect(afterP2.allResolved).toBe(true);

    const revealResult = gameService.revealAbilityActivations('ABLTY1');
    expect('error' in revealResult).toBe(false);
    if ('error' in revealResult) return;
    // Now, revealed together, the swap actually happens.
    expect(session.pitches.p1.slots[0].card!.cardId).toBe(rivalCardId);
    expect(session.pitches.p2.slots[0].card!.cardId).toBe(myCardId);
    expect(session.subSwappedCardIds.has(myCardId)).toBe(true);
    expect(session.subSwappedCardIds.has(rivalCardId)).toBe(true);
    expect(session.abilityActivations[0]).toMatchObject({ byPlayerId: 'p1', type: 'sub', targetUserId: 'p2', targetSlotIndex: 0 });
  });

  it('two `sub` cards revealed in the same baseTurnOrder pass, both targeting the same rival slot: they chain deterministically (first swap, then second against whatever landed there) rather than crashing or corrupting the board', () => {
    // 3 players so a second `sub` card is possible (duplicate types only
    // happen when player count exceeds the 5 ability originals, but nothing
    // stops constructing that state directly here for the reveal-conflict
    // case specifically). p3 subs the SAME p2 slot that p1 also subs.
    const session = activationSession({
      players: [
        { id: 'p1', displayName: 'Alice', isHost: true, isConnected: true } as any,
        { id: 'p2', displayName: 'Bob', isHost: false, isConnected: true } as any,
        { id: 'p3', displayName: 'Cara', isHost: false, isConnected: true } as any,
      ],
      baseTurnOrder: ['p1', 'p2', 'p3'],
      pitches: {
        p1: pitch('p1', fullLineup('A')),
        p2: pitch('p2', fullLineup('B')),
        p3: pitch('p3', fullLineup('C')),
      },
      playerAbilities: {
        p1: { type: 'sub', status: 'pending' },
        p2: { type: 'yellow', status: 'pending' },
        p3: { type: 'sub', status: 'pending' },
      },
    });
    inject(gameService, session);
    const p1CardId = session.pitches.p1.slots[0].card!.cardId;
    const p2CardId = session.pitches.p2.slots[0].card!.cardId;
    const p3CardId = session.pitches.p3.slots[0].card!.cardId;

    // p1 subs their GK with p2's GK.
    const r1 = gameService.activateAbility('ABLTY1', 'p1', { ownSlotIndex: 0, targetUserId: 'p2', targetSlotIndex: 0 });
    expect('error' in r1).toBe(false);
    // p2 discards.
    gameService.discardAbility('ABLTY1', 'p2');
    // p3 ALSO subs their GK with p2's GK slot (still validates fine at commit
    // time — nothing has moved yet, since sub is deferred to reveal).
    const r3 = gameService.activateAbility('ABLTY1', 'p3', { ownSlotIndex: 0, targetUserId: 'p2', targetSlotIndex: 0 });
    expect('error' in r3).toBe(false);
    if ('error' in r3) return;
    expect(r3.allResolved).toBe(true);

    const revealResult = gameService.revealAbilityActivations('ABLTY1');
    expect('error' in revealResult).toBe(false);
    if ('error' in revealResult) return;
    const revealed = revealResult.session;

    // p1 resolves first (baseTurnOrder): p1 <-> p2 swap applies normally.
    expect(revealed.pitches.p1.slots[0].card!.cardId).toBe(p2CardId);
    // p3 resolves second, against WHATEVER is in p2's slot 0 by then (p1's
    // old card, since a `sub` swap always leaves both slots filled — a
    // "conflicting" sub never finds an empty slot, so it never fizzles, it
    // just chains predictably in baseTurnOrder).
    expect(revealed.pitches.p2.slots[0].card!.cardId).toBe(p3CardId);
    expect(revealed.pitches.p3.slots[0].card!.cardId).toBe(p1CardId);
    const p3Activation = revealed.abilityActivations.find((a) => a.byPlayerId === 'p3');
    expect(p3Activation).toMatchObject({ type: 'sub' });
    expect(p3Activation!.summary).not.toContain('fizzled');
  });

  it('a `sub` fizzles at reveal if the rival is removed from the game after commit but before reveal (their pitch entry no longer exists)', () => {
    const session = activationSession({
      playerAbilities: { p1: { type: 'sub', status: 'pending' }, p2: { type: 'yellow', status: 'pending' } },
    });
    inject(gameService, session);
    const myCardId = session.pitches.p1.slots[0].card!.cardId;

    const committed = gameService.activateAbility('ABLTY1', 'p1', {
      ownSlotIndex: 0,
      targetUserId: 'p2',
      targetSlotIndex: 0,
    });
    expect('error' in committed).toBe(false);

    // p2 leaves before p1's sub is revealed — removePlayer deletes their
    // pitch entry entirely (see game.service.ts:1314).
    gameService.removePlayer('ABLTY1', 'p2');
    expect(session.pitches.p2).toBeUndefined();

    const revealResult = gameService.revealAbilityActivations('ABLTY1');
    expect('error' in revealResult).toBe(false);
    if ('error' in revealResult) return;

    // p1's own slot is untouched — the swap never happened.
    expect(revealResult.session.pitches.p1.slots[0].card!.cardId).toBe(myCardId);
    expect(revealResult.session.subSwappedCardIds.size).toBe(0);
    const p1Activation = revealResult.session.abilityActivations.find((a) => a.byPlayerId === 'p1');
    expect(p1Activation).toMatchObject({ type: 'sub' });
    expect(p1Activation!.summary).toContain('fizzled');
  });

  it('activateAbility (sub) across DIFFERENT positions is rejected with POSITION_MISMATCH, and nothing is swapped', () => {
    const session = activationSession({
      playerAbilities: { p1: { type: 'sub', status: 'pending' }, p2: { type: 'yellow', status: 'pending' } },
    });
    inject(gameService, session);
    const myCardId = session.pitches.p1.slots[0].card!.cardId; // GK
    const rivalCardId = session.pitches.p2.slots[1].card!.cardId; // LB

    const result = gameService.activateAbility('ABLTY1', 'p1', { ownSlotIndex: 0, targetUserId: 'p2', targetSlotIndex: 1 });

    expect(result).toEqual({ error: 'POSITION_MISMATCH' });
    expect(session.pitches.p1.slots[0].card!.cardId).toBe(myCardId); // unchanged
    expect(session.pitches.p2.slots[1].card!.cardId).toBe(rivalCardId); // unchanged
    expect(session.playerAbilities.p1.status).toBe('pending');
  });

  it('activateAbility (sub) with your OWN slot empty is rejected with INVALID_TARGET', () => {
    const session = activationSession({
      playerAbilities: { p1: { type: 'sub', status: 'pending' }, p2: { type: 'yellow', status: 'pending' } },
    });
    session.pitches.p1.slots[0] = { ...session.pitches.p1.slots[0], card: null };
    inject(gameService, session);

    const result = gameService.activateAbility('ABLTY1', 'p1', { ownSlotIndex: 0, targetUserId: 'p2', targetSlotIndex: 0 });

    expect(result).toEqual({ error: 'INVALID_TARGET' });
  });

  it('activateAbility (sub) with the rival\'s slot empty is rejected with INVALID_TARGET', () => {
    const session = activationSession({
      playerAbilities: { p1: { type: 'sub', status: 'pending' }, p2: { type: 'yellow', status: 'pending' } },
    });
    session.pitches.p2.slots[0] = { ...session.pitches.p2.slots[0], card: null };
    inject(gameService, session);

    const result = gameService.activateAbility('ABLTY1', 'p1', { ownSlotIndex: 0, targetUserId: 'p2', targetSlotIndex: 0 });

    expect(result).toEqual({ error: 'INVALID_TARGET' });
  });

  // ── extra_bench: no target required, resolved eagerly ───────────────────
  it('activateAbility (extra_bench) needs no target, marks used and freezes a pendingSummary immediately, but only grants the 4th sub slot once reveal + finish have run', () => {
    const session = activationSession({
      playerAbilities: { p1: { type: 'extra_bench', status: 'pending' }, p2: { type: 'yellow', status: 'pending' } },
    });
    inject(gameService, session);

    const result = gameService.activateAbility('ABLTY1', 'p1', {});
    expect('error' in result).toBe(false);
    if ('error' in result) return;
    expect(session.playerAbilities.p1.status).toBe('used');
    expect(session.playerAbilities.p1.pendingSummary).toBe('Extra Bench activated');
    expect(session.abilityActivations).toHaveLength(0); // hidden until reveal

    // Resolve p2 too so allResolved flips.
    const after = gameService.discardAbility('ABLTY1', 'p2');
    expect('error' in after).toBe(false);
    if ('error' in after) return;
    expect(after.allResolved).toBe(true);
    expect(after.session.status).toBe('ability_activation'); // not auto-transitioned

    const revealResult = gameService.revealAbilityActivations('ABLTY1');
    expect('error' in revealResult).toBe(false);
    if ('error' in revealResult) return;
    expect(revealResult.session.abilityActivations[0]).toMatchObject({ byPlayerId: 'p1', type: 'extra_bench' });

    const finishResult = gameService.finishAbilityActivation('ABLTY1');
    expect('error' in finishResult).toBe(false);
    if ('error' in finishResult) return;
    expect(finishResult.session.status).toBe('lineup_edit');
    expect(finishResult.session.subsPhase!.userSubs.p1.hasExtraBench).toBe(true);
    expect(finishResult.session.subsPhase!.userSubs.p2.hasExtraBench).toBe(false);
  });
});

/**
 * Privacy-contract tests for buildSnapshot during 'ability_activation'
 * specifically (the ability-draft privacy block above only covers the
 * earlier 'ability_draft' status). Confirmed by reading buildSnapshot: a
 * PENDING ability's type is exposed only via `myAbility`, gated on
 * `localPlayerId`; `abilityActivation.resolved` deliberately carries only a
 * boolean per player, never the type, for anyone who hasn't activated yet.
 */
describe('GameService — ability activation buildSnapshot privacy (Phase 4)', () => {
  let gameService: GameService;
  beforeEach(() => { gameService = new GameService(); });

  function activationSession(overrides: Partial<GameSession> = {}): GameSession {
    return baseSession({
      status: 'ability_activation',
      abilityDraft: null,
      playerAbilities: {
        p1: { type: 'yellow', status: 'pending' },
        p2: { type: 'captain', status: 'pending' },
      },
      ...overrides,
    });
  }

  it('a pending ability\'s type is visible only to its own owner — never to another viewer, never to no viewer at all', () => {
    const session = activationSession();
    inject(gameService, session);

    const ownView = gameService.buildSnapshot(session, 'p1') as any;
    expect(ownView.myAbility).toEqual({ type: 'yellow', status: 'pending' });

    const rivalView = gameService.buildSnapshot(session, 'p2') as any;
    expect(rivalView.myAbility).toEqual({ type: 'captain', status: 'pending' });

    const publicView = gameService.buildSnapshot(session) as any;
    expect(publicView.myAbility).toBeNull();

    // The public `abilityActivation.resolved` map exposes ONLY booleans —
    // never a hint of what type either player is holding.
    expect(ownView.abilityActivation.resolved).toEqual({ p1: false, p2: false });
    expect(Object.keys(ownView.abilityActivation)).toEqual(['resolved']);
  });

  it('once a player activates/discards, resolved flips true for everyone, but the OTHER player\'s pending type never leaks through myAbility AND the acting player\'s own choice stays out of the public log until reveal', () => {
    const session = activationSession();
    inject(gameService, session);
    gameService.activateAbility('ABLTY1', 'p1', { targetUserId: 'p2' });

    const p1View = gameService.buildSnapshot(session, 'p1') as any;
    expect(p1View.myAbility).toMatchObject({ type: 'yellow', status: 'used', targetUserId: 'p2' });
    expect(typeof p1View.myAbility.pendingSummary).toBe('string');
    expect(p1View.abilityActivation.resolved).toEqual({ p1: true, p2: false });

    // p2 has not acted yet — still pending, and p1's activation is HIDDEN
    // (abilityActivations stays empty for everyone, including p1 themselves)
    // until p2 also commits and a reveal pass runs — that's the whole point
    // of hidden simultaneous commitment: no one can react to a choice they
    // can't yet see, not even a summary of it.
    const p2View = gameService.buildSnapshot(session, 'p2') as any;
    expect(p2View.myAbility).toEqual({ type: 'captain', status: 'pending' });
    expect(p1View.myAbility.type).not.toBe('captain');
    expect(p1View.abilityActivations).toEqual([]);
    expect(p2View.abilityActivations).toEqual([]);
  });

  it('a discarded ability\'s type is never exposed to anyone but its owner — resolved is true, but the type stays private forever', () => {
    const session = activationSession();
    inject(gameService, session);
    gameService.discardAbility('ABLTY1', 'p2');

    const ownerView = gameService.buildSnapshot(session, 'p2') as any;
    expect(ownerView.myAbility).toEqual({ type: 'captain', status: 'discarded' });

    const rivalView = gameService.buildSnapshot(session, 'p1') as any;
    expect(rivalView.myAbility).toEqual({ type: 'yellow', status: 'pending' }); // p1's own, unaffected
    expect(rivalView.abilityActivation.resolved).toEqual({ p1: false, p2: true });
    // p2's discard never appears in the public activation log at all.
    expect(session.abilityActivations).toHaveLength(0);
  });

  it('abilityActivationRevealed is top-level (not nested under the status-gated abilityActivation object), false before reveal, true after — and stays true and visible even once status moves on to lineup_edit', () => {
    const session = activationSession({
      playerAbilities: {
        p1: { type: 'yellow', status: 'pending' },
        p2: { type: 'captain', status: 'pending' },
      },
    });
    inject(gameService, session);

    const before = gameService.buildSnapshot(session, 'p1') as any;
    expect(before.abilityActivationRevealed).toBe(false);

    gameService.activateAbility('ABLTY1', 'p1', { targetUserId: 'p2' });
    gameService.activateAbility('ABLTY1', 'p2', { ownSlotIndex: 0 });
    gameService.revealAbilityActivations('ABLTY1');

    const afterReveal = gameService.buildSnapshot(session, 'p1') as any;
    expect(afterReveal.abilityActivationRevealed).toBe(true);
    expect(afterReveal.abilityActivation.resolved).toEqual({ p1: true, p2: true });

    gameService.finishAbilityActivation('ABLTY1');
    const afterFinish = gameService.buildSnapshot(session, 'p1') as any;
    expect(afterFinish.status).toBe('lineup_edit');
    // abilityActivation (singular, status-gated) is gone now, but the
    // top-level revealed flag and the log itself remain — a client that
    // reconnects deep into subs must still be able to see what happened.
    expect(afterFinish.abilityActivation).toBeNull();
    expect(afterFinish.abilityActivationRevealed).toBe(true);
    expect(afterFinish.abilityActivations).toHaveLength(2);
  });
});

/**
 * Task 3.6 — pre-existing gap (carried from Phase 0's final review): kicking
 * or leave_permanently-ing a player during 'ability_draft' or
 * 'ability_activation' previously had NO handling for either phase in
 * removePlayer — only the 'drafting' status's turn-advancement was covered.
 * A removed player left mid-ability_draft would permanently block
 * pickAbilityCard (NOT_YOUR_TURN forever, since pickOrder still named them)
 * and a removed player with a pending activation would permanently block
 * _maybeFinishActivation (it never resolves, so the game can never reach
 * subs). Read removePlayer/pickAbilityCard/discardAbility/
 * _maybeFinishActivation in full before writing any of this.
 */
describe('GameService — removePlayer ability-phase awareness (Task 3.6)', () => {
  let gameService: GameService;

  beforeEach(() => {
    gameService = new GameService();
  });

  describe('during ability_draft', () => {
    it('removing a non-current picker drops them from pickOrder without disturbing whose turn it is', () => {
      const session = baseSession({
        abilityDraft: {
          pool: [
            { id: 0, type: 'captain', pickedBy: null },
            { id: 1, type: 'yellow', pickedBy: null },
          ],
          pickOrder: ['p1', 'p2'],
          currentPickIndex: 0, // p1's turn
        },
      });
      inject(gameService, session);

      const result = gameService.removePlayer('ABLTY1', 'p2');

      expect(result).not.toBeNull();
      expect(result!.session.abilityDraft!.pickOrder).toEqual(['p1']);
      expect(result!.session.abilityDraft!.currentPickIndex).toBe(0); // still p1's turn
      expect(result!.abilityDraftAllPicked).toBe(false); // p1 still hasn't picked
      expect(result!.session.status).toBe('ability_draft'); // unchanged
    });

    it('removing the CURRENT picker advances pickOrder to the next remaining player, not duplicated/skipped', () => {
      const threePlayer = baseSession({
        players: [
          { id: 'p1', displayName: 'Alice', isHost: true, isConnected: true } as any,
          { id: 'p2', displayName: 'Bob', isHost: false, isConnected: true } as any,
          { id: 'p3', displayName: 'Cara', isHost: false, isConnected: true } as any,
        ],
        pitches: {
          p1: pitch('p1', fullLineup('A')),
          p2: pitch('p2', fullLineup('B')),
          p3: pitch('p3', fullLineup('C')),
        },
        baseTurnOrder: ['p1', 'p2', 'p3'],
        abilityDraft: {
          pool: [
            { id: 0, type: 'captain', pickedBy: null },
            { id: 1, type: 'yellow', pickedBy: null },
            { id: 2, type: 'red', pickedBy: null },
          ],
          pickOrder: ['p1', 'p2', 'p3'],
          currentPickIndex: 1, // p2's turn (p1 already picked, not modeled here — pool unaffected)
        },
      });
      inject(gameService, threePlayer);

      const result = gameService.removePlayer('ABLTY1', 'p2');

      expect(result!.session.abilityDraft!.pickOrder).toEqual(['p1', 'p3']);
      // p2 was at index 1 (===currentPickIndex), so the splice shifts p3 into
      // that slot — currentPickIndex stays 1, now correctly pointing at p3.
      expect(result!.session.abilityDraft!.currentPickIndex).toBe(1);
      expect(result!.session.abilityDraft!.pickOrder[result!.session.abilityDraft!.currentPickIndex]).toBe('p3');
      expect(result!.abilityDraftAllPicked).toBe(false);
    });

    it('removing the last remaining un-picked player completes the draft (allPicked: true) — same signal pickAbilityCard returns, so the gateway can drive the real beginPlayerDraft transition', () => {
      const session = baseSession({
        abilityDraft: {
          pool: [
            { id: 0, type: 'captain', pickedBy: 'p1' },
            { id: 1, type: 'yellow', pickedBy: null },
          ],
          pickOrder: ['p1', 'p2'],
          currentPickIndex: 1, // p1 already picked; p2's turn
        },
      });
      inject(gameService, session);

      const result = gameService.removePlayer('ABLTY1', 'p2');

      expect(result!.session.abilityDraft!.pickOrder).toEqual(['p1']);
      expect(result!.session.abilityDraft!.currentPickIndex).toBe(1);
      expect(result!.abilityDraftAllPicked).toBe(true);
      // The draft itself isn't auto-completed by removePlayer (mirrors
      // pickAbilityCard's own contract — the gateway's beginPlayerDraft does
      // that, driven by `allPicked`), so status is still 'ability_draft' here.
      expect(result!.session.status).toBe('ability_draft');
    });

    it('removing a player not in pickOrder (e.g. already eliminated) does not set abilityDraftAllPicked at all', () => {
      const session = baseSession({
        players: [
          { id: 'p1', displayName: 'Alice', isHost: true, isConnected: true } as any,
          { id: 'p2', displayName: 'Bob', isHost: false, isConnected: true } as any,
        ],
        abilityDraft: {
          pool: [{ id: 0, type: 'captain', pickedBy: null }],
          pickOrder: ['p1'], // p2 already removed from pickOrder by some earlier path
          currentPickIndex: 0,
        },
      });
      inject(gameService, session);

      const result = gameService.removePlayer('ABLTY1', 'p2');

      expect(result!.abilityDraftAllPicked).toBeUndefined();
    });
  });

  describe('during ability_activation', () => {
    function activationSession(overrides: Partial<GameSession> = {}): GameSession {
      return baseSession({
        status: 'ability_activation',
        abilityDraft: null,
        playerAbilities: {
          p1: { type: 'yellow', status: 'pending' },
          p2: { type: 'captain', status: 'pending' },
        },
        ...overrides,
      });
    }

    it('auto-discards the removed player\'s pending ability — same mutation discardAbility makes', () => {
      const session = activationSession();
      inject(gameService, session);

      const result = gameService.removePlayer('ABLTY1', 'p1');

      expect(result!.session.playerAbilities.p1.status).toBe('discarded');
    });

    it('stays in ability_activation if another player still has a pending ability, and reports abilityActivationAllResolved as false', () => {
      const session = activationSession();
      inject(gameService, session);

      const result = gameService.removePlayer('ABLTY1', 'p1');

      expect(result!.session.status).toBe('ability_activation'); // p2 still pending
      expect(result!.session.playerAbilities.p2.status).toBe('pending');
      expect(result!.abilityActivationAllResolved).toBe(false);
    });

    it('reports abilityActivationAllResolved: true once the removed player\'s auto-discard was the LAST pending ability, but does NOT itself transition to subs — mirrors activateAbility/discardAbility\'s own allResolved, leaving reveal+finish to the caller', () => {
      const session = activationSession({
        playerAbilities: {
          p1: { type: 'yellow', status: 'pending' },
          p2: { type: 'captain', status: 'used', sourceSlotIndex: 0, targetPlayerId: 'B-GK-0', pendingSummary: 'Captain on B-GK-0' }, // already resolved
        },
      });
      inject(gameService, session);

      const result = gameService.removePlayer('ABLTY1', 'p1');

      expect(result!.session.playerAbilities.p1.status).toBe('discarded');
      expect(result!.abilityActivationAllResolved).toBe(true);
      expect(result!.session.status).toBe('ability_activation'); // not auto-transitioned
      expect(result!.session.abilityActivations).toHaveLength(0); // still hidden

      // The caller (gateway, in production) is expected to reveal + finish
      // next, exactly as it would after a real activateAbility/discardAbility
      // call reported allResolved: true.
      const revealResult = gameService.revealAbilityActivations('ABLTY1');
      expect('error' in revealResult).toBe(false);
      if ('error' in revealResult) return;
      expect(revealResult.session.abilityActivations[0]).toMatchObject({ byPlayerId: 'p2', type: 'captain' });

      const finishResult = gameService.finishAbilityActivation('ABLTY1');
      expect('error' in finishResult).toBe(false);
      if ('error' in finishResult) return;
      expect(finishResult.session.status).toBe('lineup_edit');
      expect(finishResult.session.subsPhase).not.toBeNull();
    });

    it('a removed player with no pending ability (already resolved, or none assigned) does not disturb an already-pending teammate', () => {
      const session = activationSession({
        playerAbilities: {
          p1: { type: 'yellow', status: 'discarded' }, // already resolved
          p2: { type: 'captain', status: 'pending' },
        },
      });
      inject(gameService, session);

      const result = gameService.removePlayer('ABLTY1', 'p1');

      expect(result!.session.status).toBe('ability_activation'); // p2 still pending
      expect(result!.session.playerAbilities.p2.status).toBe('pending');
    });
  });

  it('the drafting-phase turn-advancement block does not misfire during ability_draft (status guard)', () => {
    // session.turn defaults to activePlayerId: 'p1', phase: 'selecting_position'
    // (initialized at session creation, before ability_draft even begins) —
    // removing 'p1' here must NOT reassign session.turn, since that block is
    // only meaningful once status is actually 'drafting'.
    const session = baseSession({
      abilityDraft: {
        pool: [{ id: 0, type: 'captain', pickedBy: null }],
        pickOrder: ['p1', 'p2'],
        currentPickIndex: 0,
      },
    });
    const originalTurnId = session.turn.turnId;
    inject(gameService, session);

    const result = gameService.removePlayer('ABLTY1', 'p1');

    expect(result!.session.turn.turnId).toBe(originalTurnId); // untouched
    expect(result!.session.status).toBe('ability_draft');
  });
});

/**
 * Regression suite for the pre-reveal pitch-badge leak found by the strict
 * implementation audit: `_abilityMarks` (feeding `_serializePitches`'s
 * `captain`/`redCarded` flags and `buildSnapshot`'s `yellowPenalties`) used
 * to key off `ab.status === 'used'` alone — true at COMMIT time, well
 * before reveal — with no `abilityActivationRevealed` gate and no viewer
 * redaction. Fix: `_abilityMarks` now returns empty marks entirely until
 * `session.abilityActivationRevealed` is true (see its updated doc comment
 * in game.service.ts). `sub` was never affected (its swap + `subSwappedCardIds`
 * were already deferred to `_revealAbilityActivations`) and stays that way.
 */
describe('captain/redCarded/yellowPenalties pitch-badge visibility gated on abilityActivationRevealed', () => {
  let gameService: GameService;
  beforeEach(() => { gameService = new GameService(); });

  function auditSession(overrides: Partial<GameSession> = {}): GameSession {
    return baseSession({
      status: 'ability_activation',
      abilityDraft: null,
      playerAbilities: {
        p1: { type: 'captain', status: 'pending' },
        p2: { type: 'red', status: 'pending' },
      },
      ...overrides,
    });
  }

  it('1/2. captain: NOT visible to a rival (or a viewerless/public snapshot) pre-reveal, but IS visible — to the rival, and publicly — once revealed', () => {
    const session = auditSession({
      playerAbilities: { p1: { type: 'captain', status: 'pending' }, p2: { type: 'yellow', status: 'pending' } },
    });
    inject(gameService, session);
    const captainedCardId = session.pitches.p1.slots[0].card!.cardId;

    gameService.activateAbility('ABLTY1', 'p1', { ownSlotIndex: 0 });
    expect(session.abilityActivationRevealed).toBe(false);

    const findCaptainFlag = (view: any) =>
      view.pitches.p1.slots.find((s: any) => s.card?.cardId === captainedCardId).captain;

    // Pre-reveal: hidden from the rival, and from a viewerless/public snapshot.
    expect(findCaptainFlag(gameService.buildSnapshot(session, 'p2'))).toBe(false);
    expect(findCaptainFlag(gameService.buildSnapshot(session))).toBe(false);
    // Pre-reveal: hidden even from the captaining player's OWN view of their
    // own pitch (badges are derived state, not the private `myAbility`
    // field — they only exist once the server has actually revealed).
    expect(findCaptainFlag(gameService.buildSnapshot(session, 'p1'))).toBe(false);

    gameService.discardAbility('ABLTY1', 'p2');
    const revealResult = gameService.revealAbilityActivations('ABLTY1');
    expect('error' in revealResult).toBe(false);

    // Post-reveal: visible to everyone, including a public/viewerless snapshot.
    expect(findCaptainFlag(gameService.buildSnapshot(session, 'p2'))).toBe(true);
    expect(findCaptainFlag(gameService.buildSnapshot(session, 'p1'))).toBe(true);
    expect(findCaptainFlag(gameService.buildSnapshot(session))).toBe(true);
  });

  it('3/4. red: NOT visible to the targeted owner pre-reveal, but IS visible once revealed', () => {
    const session = auditSession();
    inject(gameService, session);
    const targetCardId = session.pitches.p1.slots[0].card!.cardId;

    gameService.activateAbility('ABLTY1', 'p2', { targetUserId: 'p1', targetSlotIndex: 0 });
    expect(session.abilityActivationRevealed).toBe(false);

    const findRedFlag = (view: any) =>
      view.pitches.p1.slots.find((s: any) => s.card?.cardId === targetCardId).redCarded;

    // Pre-reveal: the victim (p1) does not see their own card marked yet.
    expect(findRedFlag(gameService.buildSnapshot(session, 'p1'))).toBe(false);
    expect(findRedFlag(gameService.buildSnapshot(session, 'p2'))).toBe(false);

    gameService.discardAbility('ABLTY1', 'p1');
    gameService.revealAbilityActivations('ABLTY1');

    // Post-reveal: visible to everyone.
    expect(findRedFlag(gameService.buildSnapshot(session, 'p1'))).toBe(true);
    expect(findRedFlag(gameService.buildSnapshot(session, 'p2'))).toBe(true);
  });

  it('5/6. yellow: penalty NOT visible pre-reveal, but IS visible (and correctly totalled) once revealed', () => {
    const session = auditSession({
      playerAbilities: { p1: { type: 'yellow', status: 'pending' }, p2: { type: 'captain', status: 'pending' } },
    });
    inject(gameService, session);

    gameService.activateAbility('ABLTY1', 'p1', { targetUserId: 'p2' });
    expect(session.abilityActivationRevealed).toBe(false);

    // Pre-reveal: neither the victim nor a public snapshot sees the penalty.
    expect((gameService.buildSnapshot(session, 'p2') as any).yellowPenalties.p2 ?? 0).toBe(0);
    expect((gameService.buildSnapshot(session) as any).yellowPenalties.p2 ?? 0).toBe(0);

    gameService.discardAbility('ABLTY1', 'p2');
    gameService.revealAbilityActivations('ABLTY1');

    // Post-reveal: visible and correct everywhere.
    expect((gameService.buildSnapshot(session, 'p2') as any).yellowPenalties.p2).toBe(20);
    expect((gameService.buildSnapshot(session) as any).yellowPenalties.p2).toBe(20);
  });

  it('7. sub: unaffected by the fix — was already, and remains, not publicly mutated/marked before reveal', () => {
    const session = auditSession({
      playerAbilities: { p1: { type: 'sub', status: 'pending' }, p2: { type: 'yellow', status: 'pending' } },
    });
    inject(gameService, session);
    const myCardId = session.pitches.p1.slots[0].card!.cardId;
    const rivalCardId = session.pitches.p2.slots[0].card!.cardId;

    gameService.activateAbility('ABLTY1', 'p1', { ownSlotIndex: 0, targetUserId: 'p2', targetSlotIndex: 0 });

    const preReveal = gameService.buildSnapshot(session, 'p2') as any;
    // Board itself untouched, and the swap badge isn't set yet.
    expect(preReveal.pitches.p1.slots[0].card.cardId).toBe(myCardId);
    expect(preReveal.pitches.p2.slots[0].card.cardId).toBe(rivalCardId);
    expect(preReveal.pitches.p1.slots[0].subSwapped).toBe(false);

    gameService.discardAbility('ABLTY1', 'p2');
    gameService.revealAbilityActivations('ABLTY1');

    const postReveal = gameService.buildSnapshot(session, 'p2') as any;
    expect(postReveal.pitches.p1.slots[0].card.cardId).toBe(rivalCardId);
    expect(postReveal.pitches.p1.slots[0].subSwapped).toBe(true);
  });
});

// ── Bench targeting (Red / Sub / Coach; Captain pitch-only) ───────────────────

describe('GameService — ability bench targeting', () => {
  let gameService: GameService;
  beforeEach(() => {
    gameService = new GameService();
  });

  function benchSession(
    abilities: Record<string, { type: string; status: string }>,
  ): GameSession {
    const p2MidCard = card('B-bench-CM', 'CM', 80);
    const p1MidCard = card('A-bench-CM', 'CM', 78);
    return baseSession({
      status: 'ability_activation',
      abilityDraft: null,
      playerAbilities: abilities as any,
      abilityActivations: [],
      abilityActivationRevealed: false,
      coachedPositions: {},
      subsPhase: {
        userSubs: {
          p1: {
            isComplete: true,
            lineupConfirmed: false,
            att: {
              positionGroup: 'att',
              chosenPlayerId: 'A-bench-ST',
              chosenPlayerName: 'A-bench-ST',
              chosenPlayerPosition: 'ST',
              chosenCard: card('A-bench-ST', 'ST'),
            },
            mid: {
              positionGroup: 'mid',
              chosenPlayerId: p1MidCard.cardId,
              chosenPlayerName: p1MidCard.playerName,
              chosenPlayerPosition: 'CM',
              chosenCard: p1MidCard,
            },
            def: {
              positionGroup: 'def',
              chosenPlayerId: 'A-bench-CB',
              chosenPlayerName: 'A-bench-CB',
              chosenPlayerPosition: 'CB',
              chosenCard: card('A-bench-CB', 'CB'),
            },
          },
          p2: {
            isComplete: true,
            lineupConfirmed: false,
            att: {
              positionGroup: 'att',
              chosenPlayerId: 'B-bench-ST',
              chosenPlayerName: 'B-bench-ST',
              chosenPlayerPosition: 'ST',
              chosenCard: card('B-bench-ST', 'ST'),
            },
            mid: {
              positionGroup: 'mid',
              chosenPlayerId: p2MidCard.cardId,
              chosenPlayerName: p2MidCard.playerName,
              chosenPlayerPosition: 'CM',
              chosenCard: p2MidCard,
            },
            def: {
              positionGroup: 'def',
              chosenPlayerId: 'B-bench-CB',
              chosenPlayerName: 'B-bench-CB',
              chosenPlayerPosition: 'CB',
              chosenCard: card('B-bench-CB', 'CB'),
            },
          },
        },
      },
    });
  }

  it('red can target a rival bench player', () => {
    const session = benchSession({
      p1: { type: 'red', status: 'pending' },
      p2: { type: 'yellow', status: 'pending' },
    });
    inject(gameService, session);

    const result = gameService.activateAbility('ABLTY1', 'p1', {
      targetUserId: 'p2',
      targetBenchGroup: 'mid',
    });
    expect('error' in result).toBe(false);
    expect(session.playerAbilities.p1.targetPlayerId).toBe('B-bench-CM');
    expect(session.playerAbilities.p1.targetBenchGroup).toBe('mid');
    expect(session.playerAbilities.p1.pendingSummary).toContain('bench');
  });

  it('red rejects empty rival bench group', () => {
    const session = benchSession({
      p1: { type: 'red', status: 'pending' },
      p2: { type: 'yellow', status: 'pending' },
    });
    session.subsPhase!.userSubs.p2.mid = undefined;
    inject(gameService, session);

    expect(
      gameService.activateAbility('ABLTY1', 'p1', {
        targetUserId: 'p2',
        targetBenchGroup: 'mid',
      }),
    ).toEqual({ error: 'INVALID_TARGET' });
  });

  it('sub can target same-position rival bench and reveal swaps pitch↔bench', () => {
    const session = benchSession({
      p1: { type: 'sub', status: 'pending' },
      p2: { type: 'yellow', status: 'pending' },
    });
    inject(gameService, session);
    // p1 CM pitch slot index 6 (CDM=5, CM=6, CAM=7 in FORMATION_SLOTS)
    const cmIndex = session.pitches.p1.slots.findIndex(
      (s) => s.basePositionType === 'CM',
    );
    const myCardId = session.pitches.p1.slots[cmIndex].card!.cardId;
    const benchCardId = 'B-bench-CM';

    const act = gameService.activateAbility('ABLTY1', 'p1', {
      ownSlotIndex: cmIndex,
      targetUserId: 'p2',
      targetBenchGroup: 'mid',
    });
    expect('error' in act).toBe(false);

    gameService.discardAbility('ABLTY1', 'p2');
    gameService.revealAbilityActivations('ABLTY1');

    expect(session.pitches.p1.slots[cmIndex].card!.cardId).toBe(benchCardId);
    const p2Mid = session.subsPhase!.userSubs.p2.mid!;
    const onBench = p2Mid.benchedCard ?? p2Mid.chosenCard;
    expect(onBench!.cardId).toBe(myCardId);
    expect(session.subSwappedCardIds.has(myCardId)).toBe(true);
    expect(session.subSwappedCardIds.has(benchCardId)).toBe(true);
  });

  it('sub rejects position mismatch against rival bench', () => {
    const session = benchSession({
      p1: { type: 'sub', status: 'pending' },
      p2: { type: 'yellow', status: 'pending' },
    });
    inject(gameService, session);
    const stIndex = session.pitches.p1.slots.findIndex(
      (s) => s.basePositionType === 'ST',
    );

    expect(
      gameService.activateAbility('ABLTY1', 'p1', {
        ownSlotIndex: stIndex,
        targetUserId: 'p2',
        targetBenchGroup: 'mid', // CM bench vs ST pitch
      }),
    ).toEqual({ error: 'POSITION_MISMATCH' });
  });

  it('coach can target own bench player', () => {
    const session = benchSession({
      p1: { type: 'coach', status: 'pending' },
      p2: { type: 'yellow', status: 'pending' },
    });
    inject(gameService, session);

    const result = gameService.activateAbility('ABLTY1', 'p1', {
      ownBenchGroup: 'mid',
      coachedPosition: 'CAM',
    });
    expect('error' in result).toBe(false);
    expect(session.playerAbilities.p1.targetPlayerId).toBe('A-bench-CM');
    expect(session.playerAbilities.p1.sourceBenchGroup).toBe('mid');
  });

  it('coach on own bench applies position and keeps it after entering pitch', () => {
    const session = benchSession({
      p1: { type: 'coach', status: 'pending' },
      p2: { type: 'yellow', status: 'pending' },
    });
    inject(gameService, session);

    gameService.activateAbility('ABLTY1', 'p1', {
      ownBenchGroup: 'mid',
      coachedPosition: 'CAM',
    });
    gameService.discardAbility('ABLTY1', 'p2');
    gameService.revealAbilityActivations('ABLTY1');

    const benchCard =
      session.subsPhase!.userSubs.p1.mid!.benchedCard ??
      session.subsPhase!.userSubs.p1.mid!.chosenCard!;
    expect(benchCard.naturalPositions).toContain('CAM');
    expect(session.coachedPositions['A-bench-CM']).toBe('CAM');

    // Move coached bench card onto a pitch CM slot via lineup_edit swap.
    session.status = 'lineup_edit';
    const cmIndex = session.pitches.p1.slots.findIndex(
      (s) => s.basePositionType === 'CM',
    );
    gameService.swapRoster(
      'ABLTY1',
      'p1',
      { kind: 'pitch', index: cmIndex },
      { kind: 'bench', group: 'mid' },
    );
    expect(session.pitches.p1.slots[cmIndex].card!.naturalPositions).toContain(
      'CAM',
    );
  });

  it('captain cannot target bench (ownBenchGroup alone is INVALID_TARGET)', () => {
    const session = benchSession({
      p1: { type: 'captain', status: 'pending' },
      p2: { type: 'yellow', status: 'pending' },
    });
    inject(gameService, session);

    expect(
      gameService.activateAbility('ABLTY1', 'p1', {
        ownBenchGroup: 'mid',
      }),
    ).toEqual({ error: 'INVALID_TARGET' });
  });

  it('red on rival bench remains attached after that card later enters the pitch', () => {
    const session = benchSession({
      p1: { type: 'red', status: 'pending' },
      p2: { type: 'yellow', status: 'pending' },
    });
    inject(gameService, session);

    gameService.activateAbility('ABLTY1', 'p1', {
      targetUserId: 'p2',
      targetBenchGroup: 'mid',
    });
    gameService.discardAbility('ABLTY1', 'p2');
    gameService.revealAbilityActivations('ABLTY1');
    expect(session.playerAbilities.p1.targetPlayerId).toBe('B-bench-CM');

    session.status = 'lineup_edit';
    const cmIndex = session.pitches.p2.slots.findIndex(
      (s) => s.basePositionType === 'CM',
    );
    gameService.swapRoster(
      'ABLTY1',
      'p2',
      { kind: 'pitch', index: cmIndex },
      { kind: 'bench', group: 'mid' },
    );

    const snap = gameService.buildSnapshot(session, 'p1') as any;
    expect(snap.pitches.p2.slots[cmIndex].redCarded).toBe(true);
    expect(snap.pitches.p2.slots[cmIndex].card.cardId).toBe('B-bench-CM');
  });

  it('snapshot exposes rival bench identity only during ability_activation', () => {
    const session = benchSession({
      p1: { type: 'red', status: 'pending' },
      p2: { type: 'yellow', status: 'pending' },
    });
    inject(gameService, session);

    const during = gameService.buildSnapshot(session, 'p1') as any;
    expect(during.subsPhase.userSubs.p2.mid.chosenPlayerId).toBe('B-bench-CM');
    expect(during.subsPhase.userSubs.p2.mid.benchedChemistryBonuses).toEqual(
      [],
    );

    session.status = 'lineup_edit';
    const after = gameService.buildSnapshot(session, 'p1') as any;
    expect(after.subsPhase.userSubs.p2.mid).toBeUndefined();
    expect(after.subsPhase.userSubs.p2.isComplete).toBe(true);
  });

  it('starting-XI red targeting still works (regression)', () => {
    const session = benchSession({
      p1: { type: 'red', status: 'pending' },
      p2: { type: 'yellow', status: 'pending' },
    });
    inject(gameService, session);
    const result = gameService.activateAbility('ABLTY1', 'p1', {
      targetUserId: 'p2',
      targetSlotIndex: 0,
    });
    expect('error' in result).toBe(false);
    expect(session.playerAbilities.p1.targetBenchGroup).toBeUndefined();
    expect(session.playerAbilities.p1.targetPlayerId).toBe(
      session.pitches.p2.slots[0].card!.cardId,
    );
  });
});
