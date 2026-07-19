import { RoomsGateway } from './rooms.gateway';
import { RoomsService } from './rooms.service';
import { GameService } from '../game/game.service';
import { GameSession } from '../game/interfaces/game-session.interface';
import { Room } from './interfaces/room.interface';
import { generateReconnectToken } from '../reconnect-token';

/**
 * Disconnect-during-turn handling — product rule (current): a temporary
 * disconnect must never leave a still-in-room player with fewer drafted
 * cards than everyone else. Historically (see git history / SESSION_LOG.md)
 * a disconnected active player's turn was instead SKIPPED forward to the
 * next connected player, which permanently cost them that round's card even
 * after reconnecting. That's been replaced: the active player's turn is now
 * auto-picked for them (`_autoPickCurrentPhase` — the exact same logic a
 * connected-but-slow player's full turnSeconds timeout already uses), not
 * taken away.
 *
 * Mechanism: a refresh always disconnects the old socket before the new one
 * reconnects — there is no such thing as an instant, zero-gap refresh. So
 * the auto-pick is delayed by ACTIVE_TURN_DISCONNECT_GRACE_MS
 * (`_scheduleDisconnectedTurnResolution`) and cancelled if the same room's
 * player reconnects within that window — preserving the original guarantee
 * that the room is never stuck waiting on a dead socket forever, while not
 * punishing an ordinary refresh with an unwanted auto-pick.
 *
 * `_scheduleTurnTimer` (rooms.gateway.ts) is the single point that decides,
 * on EVERY turn transition, whether the newly active player is connected;
 * if not, it arms this same grace-then-auto-pick mechanism instead of a
 * real per-turn countdown. That covers both "the active player disconnects
 * mid-turn" (this file, via handleDisconnect) AND "the turn naturally
 * rotates to a player who was already disconnected" (covered at the
 * service-turn-order level by game.service.disconnect-turn-order.spec.ts,
 * and end-to-end by the "full lobby" test below).
 */
describe('RoomsGateway — active-turn disconnect grace period (auto-pick, not skip)', () => {
  let roomsService: RoomsService;
  let gameService: GameService;
  let gateway: RoomsGateway;

  const ROOM_CODE = 'HPROOM';
  const SESSION_ID = 'sess-hp';
  const GRACE_MS = 10_000; // must match ACTIVE_TURN_DISCONNECT_GRACE_MS in rooms.gateway.ts
  const REVEAL_MS = 5_000; // must match _scheduleHiddenRevealTimeout's hardcoded delay

  function emptyPitch(playerId: string) {
    return {
      playerId,
      slots: [
        { index: 0, label: 'GK', basePositionType: 'GK', card: null },
        { index: 1, label: 'LB', basePositionType: 'LB', card: null },
      ],
      filledCount: 0,
    };
  }

  const hiddenCard = {
    cardId: 'hidden-card-1',
    playerName: 'A. Areola',
    basePositionType: 'GK',
    rating: 82,
    pace: 60,
    shooting: 40,
    passing: 60,
    dribbling: 50,
    defending: 40,
    physical: 70,
    nationality: 'France',
    club: 'Test FC',
    altPositions: [],
    naturalPositions: ['GK'],
    chemistryBonuses: [],
  } as any;

  function hiddenPickSession(overrides: Partial<GameSession> = {}): GameSession {
    return {
      sessionId: SESSION_ID,
      roomCode: ROOM_CODE,
      leagues: [],
      playerBonusCache: new Map(),
      userChallengeCache: new Map(),
      formation: { name: '4-3-3', slots: [] } as any,
      players: [
        { id: 'p1', displayName: 'Alice', isHost: true, isConnected: true },
        { id: 'p2', displayName: 'Bob', isHost: false, isConnected: true },
      ],
      pitches: { p1: emptyPitch('p1') as any, p2: emptyPitch('p2') as any },
      baseTurnOrder: ['p1', 'p2'],
      currentRound: 1,
      totalRounds: 11,
      currentTurnIndex: 0,
      currentRoundSlotIndex: 0,
      draftedCardIds: new Set(),
      roundCandidates: [],
      orderedHiddenDeck: [hiddenCard],
      hiddenPicksTaken: new Set(),
      hiddenPicksMap: new Map(),
      hiddenPickReveal: null,
      lastRoundLeftovers: [],
      turn: {
        turnId: 't1',
        phase: 'hidden_pick',
        activePlayerId: 'p1',
        activeSlotIndex: 0,
        candidates: [],
        turnStartedAt: null,
      },
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
      ...overrides,
    } as GameSession;
  }

  /** Builds a Room + matching GameSession with real, aligned p1/p2 ids —
   * unlike some other fixtures in this file, this MUST have consistent ids
   * across roomsService and gameService, since the grace-period logic keys
   * off of matching playerId lookups in both services. */
  function setUpRoomAndSession(overrides: Partial<GameSession> = {}): { room: Room; session: GameSession } {
    const room: Room = {
      code: ROOM_CODE,
      players: [
        { id: 'p1', displayName: 'Alice', isHost: true, isConnected: true, socketId: 'sock-p1' },
        { id: 'p2', displayName: 'Bob', isHost: false, isConnected: true, socketId: 'sock-p2' },
      ],
      spectators: [],
      isStarted: true,
      isLocked: false,
      kickedPlayerIds: [],
      kickedDisplayNames: [],
      pendingJoinRequests: [],
      lastActivityAt: Date.now(),
      leagues: [],
      turnTimerSeconds: null,
      subsTimerSeconds: null,
      formationSlug: null,
      tournamentEnabled: false,
      simulationSpeed: 'normal',
    } as any;

    (roomsService as unknown as { rooms: Map<string, Room> }).rooms.set(ROOM_CODE, room);
    (roomsService as unknown as { socketIndex: Map<string, { roomCode: string; playerId: string }> })
      .socketIndex.set('sock-p1', { roomCode: ROOM_CODE, playerId: 'p1' });
    (roomsService as unknown as { socketIndex: Map<string, { roomCode: string; playerId: string }> })
      .socketIndex.set('sock-p2', { roomCode: ROOM_CODE, playerId: 'p2' });
    (roomsService as unknown as { playerRoomIndex: Map<string, string> })
      .playerRoomIndex.set('p1', ROOM_CODE);
    (roomsService as unknown as { playerRoomIndex: Map<string, string> })
      .playerRoomIndex.set('p2', ROOM_CODE);

    const session = hiddenPickSession(overrides);
    (gameService as unknown as { sessions: Map<string, GameSession> }).sessions.set(session.sessionId, session);
    (gameService as unknown as { roomToSession: Map<string, string> }).roomToSession.set(room.code, session.sessionId);

    return { room, session };
  }

  beforeEach(() => {
    jest.useFakeTimers();
    roomsService = new RoomsService();
    gameService = new GameService();
    gateway = new RoomsGateway(roomsService, gameService);
  });

  afterEach(() => {
    gateway.onModuleDestroy();
    jest.useRealTimers();
  });

  it('a refresh (disconnect then reconnect within the grace period) during hidden_pick does NOT auto-pick — the player can still pick for themselves', () => {
    setUpRoomAndSession();

    // Old socket closes — the first half of any refresh.
    gateway.handleDisconnect({ id: 'sock-p1' } as never);

    // New socket reconnects well within the grace window.
    jest.advanceTimersByTime(1_000);
    const token = generateReconnectToken('p1', ROOM_CODE);
    gateway.handleCheckPresence(
      { playerId: 'p1', roomCode: ROOM_CODE, reconnectToken: token } as never,
      { id: 'sock-p1-new' } as never,
    );

    // Let the grace window fully elapse — the auto-pick must never have fired.
    jest.advanceTimersByTime(GRACE_MS + 1_000);

    const session = gameService.getSessionByRoomCode(ROOM_CODE)!;
    expect(session.turn.phase).toBe('hidden_pick');
    expect(session.turn.activePlayerId).toBe('p1');
    expect(session.pitches.p1.slots[0].card).toBeNull(); // still theirs to pick

    // The player can still act — pick_hidden_slot succeeds as if nothing happened.
    const result = gameService.pickHiddenSlot(ROOM_CODE, 'p1', session.turn.turnId, 0);
    expect('error' in result).toBe(false);
    if (!('error' in result)) {
      expect(session.pitches.p1.slots[0].card?.cardId).toBe('hidden-card-1');
    }
  });

  it('a genuine abandonment (disconnect, never reconnects) gets AUTO-PICKED once the grace period elapses — they end up with the card, not a gap', () => {
    setUpRoomAndSession();

    gateway.handleDisconnect({ id: 'sock-p1' } as never);

    // No reconnect at all — advance straight past the grace window.
    jest.advanceTimersByTime(GRACE_MS + 1_000);

    const session = gameService.getSessionByRoomCode(ROOM_CODE)!;
    // p1 was auto-picked (the only card in this test's hidden deck), NOT
    // skipped — this is the core product-behavior change: they now hold the
    // card themselves, same as a real pick.
    expect(session.pitches.p1.slots[0].card?.cardId).toBe('hidden-card-1');
    // pickHiddenSlot transitions into a brief hidden_pick_reveal window
    // (the picker still "holds" the turn to see what they got) — turn
    // hasn't moved to p2 yet, that happens on the reveal's own 5s self-heal.
    expect(session.turn.phase).toBe('hidden_pick_reveal');
    expect(session.turn.activePlayerId).toBe('p1');

    // Advance past the reveal window too — turn now moves on to p2, exactly
    // as it would after a real pick.
    jest.advanceTimersByTime(REVEAL_MS + 1_000);
    const after = gameService.getSessionByRoomCode(ROOM_CODE)!;
    expect(after.turn.activePlayerId).toBe('p2');
  });

  it('a non-active player disconnecting does not affect (or delay-reset) a pending auto-pick for the actual active player', () => {
    // A 3rd, always-connected player (p3) so the room survives p1 AND p2
    // both being briefly offline at once — otherwise handleDisconnect's own
    // unrelated "everyone left, tear down the room" cleanup would fire and
    // confound this test with a different code path entirely.
    const room: Room = {
      code: ROOM_CODE,
      players: [
        { id: 'p1', displayName: 'Alice', isHost: true, isConnected: true, socketId: 'sock-p1' },
        { id: 'p2', displayName: 'Bob', isHost: false, isConnected: true, socketId: 'sock-p2' },
        { id: 'p3', displayName: 'Cara', isHost: false, isConnected: true, socketId: 'sock-p3' },
      ],
      spectators: [],
      isStarted: true,
      isLocked: false,
      kickedPlayerIds: [],
      kickedDisplayNames: [],
      pendingJoinRequests: [],
      lastActivityAt: Date.now(),
      leagues: [],
      turnTimerSeconds: null,
      subsTimerSeconds: null,
      formationSlug: null,
      tournamentEnabled: false,
      simulationSpeed: 'normal',
    } as any;
    (roomsService as unknown as { rooms: Map<string, Room> }).rooms.set(ROOM_CODE, room);
    for (const p of ['p1', 'p2', 'p3']) {
      (roomsService as unknown as { socketIndex: Map<string, { roomCode: string; playerId: string }> })
        .socketIndex.set(`sock-${p}`, { roomCode: ROOM_CODE, playerId: p });
      (roomsService as unknown as { playerRoomIndex: Map<string, string> })
        .playerRoomIndex.set(p, ROOM_CODE);
    }
    const session = hiddenPickSession({
      players: [
        { id: 'p1', displayName: 'Alice', isHost: true, isConnected: true },
        { id: 'p2', displayName: 'Bob', isHost: false, isConnected: true },
        { id: 'p3', displayName: 'Cara', isHost: false, isConnected: true },
      ] as any,
      pitches: { p1: emptyPitch('p1') as any, p2: emptyPitch('p2') as any, p3: emptyPitch('p3') as any },
      baseTurnOrder: ['p1', 'p2', 'p3'],
      // Two cards so BOTH p1's and p2's auto-picks (later in this test) have
      // something available — a single-card deck would leave p2 with
      // nothing to auto-pick once p1's pick already took the only one,
      // which isn't what this test is about.
      orderedHiddenDeck: [hiddenCard, { ...hiddenCard, cardId: 'hidden-card-2' }],
    });
    (gameService as unknown as { sessions: Map<string, GameSession> }).sessions.set(session.sessionId, session);
    (gameService as unknown as { roomToSession: Map<string, string> }).roomToSession.set(room.code, session.sessionId);

    // p1 (active) disconnects first.
    gateway.handleDisconnect({ id: 'sock-p1' } as never);
    // 6s later, p2 (NOT active) also disconnects — must not overwrite or
    // reset the clock on p1's already-pending auto-pick.
    jest.advanceTimersByTime(6_000);
    gateway.handleDisconnect({ id: 'sock-p2' } as never);

    // Only 4.1 more seconds pass (10.1s total since p1's disconnect) — enough
    // for p1's ORIGINAL grace window to elapse, even though less than a full
    // fresh 10s has passed since p2's later, irrelevant disconnect. If p2's
    // disconnect had wrongly reset/rescheduled anything keyed to p1, this
    // would still be waiting.
    jest.advanceTimersByTime(4_000 + 100);

    // p1 was auto-picked on ITS OWN original 10s schedule — not reset to
    // fire 10s from p2's later disconnect (that would be t=16000, long after
    // this point), and not misdirected at p2's turn (p2 was never active).
    const afterP1 = gameService.getSessionByRoomCode(ROOM_CODE)!;
    expect(afterP1.pitches.p1.slots[0].card?.cardId).toBe('hidden-card-1');
    expect(afterP1.turn.phase).toBe('hidden_pick_reveal');
    expect(afterP1.turn.activePlayerId).toBe('p1');

    // Let p1's reveal window elapse — turn moves to p2, who is now ALSO
    // disconnected, so _scheduleTurnTimer arms a fresh grace timer for p2
    // in turn (same mechanism, chained).
    jest.advanceTimersByTime(REVEAL_MS + 100);
    const afterReveal = gameService.getSessionByRoomCode(ROOM_CODE)!;
    expect(afterReveal.turn.activePlayerId).toBe('p2');
    expect(afterReveal.pitches.p2.slots[0].card).toBeNull(); // not yet auto-picked

    // Let p2's own grace window elapse too — they get auto-picked, then the
    // turn finally reaches p3, who's been connected the whole time.
    jest.advanceTimersByTime(GRACE_MS + REVEAL_MS + 1_000);
    const final = gameService.getSessionByRoomCode(ROOM_CODE)!;
    expect(final.pitches.p2.slots[0].card?.cardId).toBe('hidden-card-2');
    expect(final.turn.activePlayerId).toBe('p3');
  });

  it('reconnecting after a hidden-slot pick already resolved restores the reconnecting player\'s own drafted card intact (no data loss, no missing historic picks)', () => {
    const { session } = setUpRoomAndSession();

    // p1 picks their hidden slot BEFORE disconnecting — mirrors "reconnect
    // immediately after the hidden-slot choice resolves".
    const pickResult = gameService.pickHiddenSlot(ROOM_CODE, 'p1', session.turn.turnId, 0);
    expect('error' in pickResult).toBe(false);
    expect(session.pitches.p1.slots[0].card?.cardId).toBe('hidden-card-1');
    expect(session.turn.phase).toBe('hidden_pick_reveal');

    // p1 now disconnects (e.g. refreshing right after seeing the reveal).
    gateway.handleDisconnect({ id: 'sock-p1' } as never);

    // hidden_pick_reveal is excluded from the grace/auto-pick mechanism
    // entirely (it self-heals via its own 5s timer) — advancing well past
    // the grace period must not touch the resolved pick.
    jest.advanceTimersByTime(GRACE_MS + 1_000);
    expect(session.pitches.p1.slots[0].card?.cardId).toBe('hidden-card-1');

    // p1 reconnects — the snapshot they receive must show their own,
    // already-resolved drafted card, not an empty/reverted roster.
    const token = generateReconnectToken('p1', ROOM_CODE);
    gateway.handleCheckPresence(
      { playerId: 'p1', roomCode: ROOM_CODE, reconnectToken: token } as never,
      { id: 'sock-p1-new' } as never,
    );

    const snapshot = gameService.buildSnapshot(session, 'p1') as any;
    expect(snapshot.pitches.p1.slots[0].card.cardId).toBe('hidden-card-1');
    expect(snapshot.pitches.p1.filledCount).toBe(1);
  });

  it('a PERMANENTLY removed (kicked) player is never auto-picked for, even if their grace timer was already pending', () => {
    // 3 players so kicking one down to 2 doesn't also trigger the separate
    // "too few players left" end-game path (_tryEndGame) — that would be a
    // different code path entirely, not what this test is about. p1 is
    // host (stays connected, does the kicking); p2 is the disconnecting,
    // about-to-be-kicked player; p3 is a bystander who stays connected.
    const room: Room = {
      code: ROOM_CODE,
      players: [
        { id: 'p1', displayName: 'Alice', isHost: true, isConnected: true, socketId: 'sock-p1' },
        { id: 'p2', displayName: 'Bob', isHost: false, isConnected: true, socketId: 'sock-p2' },
        { id: 'p3', displayName: 'Cara', isHost: false, isConnected: true, socketId: 'sock-p3' },
      ],
      spectators: [],
      isStarted: true,
      isLocked: false,
      kickedPlayerIds: [],
      kickedDisplayNames: [],
      pendingJoinRequests: [],
      lastActivityAt: Date.now(),
      leagues: [],
      turnTimerSeconds: null,
      subsTimerSeconds: null,
      formationSlug: null,
      tournamentEnabled: false,
      simulationSpeed: 'normal',
    } as any;
    (roomsService as unknown as { rooms: Map<string, Room> }).rooms.set(ROOM_CODE, room);
    for (const p of ['p1', 'p2', 'p3']) {
      (roomsService as unknown as { socketIndex: Map<string, { roomCode: string; playerId: string }> })
        .socketIndex.set(`sock-${p}`, { roomCode: ROOM_CODE, playerId: p });
      (roomsService as unknown as { playerRoomIndex: Map<string, string> })
        .playerRoomIndex.set(p, ROOM_CODE);
    }
    const session = hiddenPickSession({
      players: [
        { id: 'p1', displayName: 'Alice', isHost: true, isConnected: true },
        { id: 'p2', displayName: 'Bob', isHost: false, isConnected: true },
        { id: 'p3', displayName: 'Cara', isHost: false, isConnected: true },
      ] as any,
      pitches: { p1: emptyPitch('p1') as any, p2: emptyPitch('p2') as any, p3: emptyPitch('p3') as any },
      baseTurnOrder: ['p1', 'p2', 'p3'],
      turn: {
        turnId: 't1',
        phase: 'hidden_pick',
        activePlayerId: 'p2',
        activeSlotIndex: 0,
        candidates: [],
        turnStartedAt: null,
      },
      currentTurnIndex: 1,
    });
    (gameService as unknown as { sessions: Map<string, GameSession> }).sessions.set(session.sessionId, session);
    (gameService as unknown as { roomToSession: Map<string, string> }).roomToSession.set(room.code, session.sessionId);

    // p2 disconnects — grace timer armed for p2.
    gateway.handleDisconnect({ id: 'sock-p2' } as never);
    jest.advanceTimersByTime(2_000);

    // Host (p1) kicks p2 outright (permanent removal) before the grace
    // window elapses — mirrors a real "disconnected, host gives up waiting,
    // kicks them" sequence.
    (gateway as unknown as {
      handleKickPlayer(dto: { targetPlayerId: string }, client: { id: string }): void;
    }).handleKickPlayer({ targetPlayerId: 'p2' }, { id: 'sock-p1' });

    const afterKick = gameService.getSessionByRoomCode(ROOM_CODE)!;
    // Permanently gone: not in players/baseTurnOrder/pitches at all.
    expect(afterKick.players.some((p) => p.id === 'p2')).toBe(false);
    expect(afterKick.baseTurnOrder).not.toContain('p2');
    expect(afterKick.pitches.p2).toBeUndefined();

    // Let the original grace window fully elapse — nothing should attempt
    // to auto-pick "for" a player who no longer exists in the session.
    jest.advanceTimersByTime(GRACE_MS);
    const final = gameService.getSessionByRoomCode(ROOM_CODE)!;
    expect(final.pitches.p2).toBeUndefined();
    // The turn already moved on to p3 as part of the kick itself
    // (removePlayer's own reassignment) — not stuck, not re-targeting the
    // removed player.
    expect(final.turn.activePlayerId).toBe('p3');
  });

  it('full lobby: a player disconnected for MULTIPLE consecutive rounds still ends the draft with a complete, non-empty squad — same shape as everyone else', () => {
    // A compact 2-round draft (GK, LB only) so the whole thing can run to
    // completion inside one test without excessive fake-timer bookkeeping.
    const { session } = setUpRoomAndSession({
      totalRounds: 2,
      // A real turnSeconds policy so the CONNECTED player (p2) also
      // auto-resolves if they don't act — this test is about the room
      // never getting stuck, not about manually driving p2's own picks.
      // p1's grace-then-auto-pick mechanism (unconditional, disconnect-only)
      // is what's actually under test; this just lets the whole draft run
      // to completion unattended.
      turnTimeoutPolicy: { enabled: true, turnSeconds: 5, onExpiry: 'auto_pick_random' },
      pitches: {
        p1: { playerId: 'p1', slots: [
          { index: 0, label: 'GK', basePositionType: 'GK', card: null },
          { index: 1, label: 'LB', basePositionType: 'LB', card: null },
        ], filledCount: 0 } as any,
        p2: { playerId: 'p2', slots: [
          { index: 0, label: 'GK', basePositionType: 'GK', card: null },
          { index: 1, label: 'LB', basePositionType: 'LB', card: null },
        ], filledCount: 0 } as any,
      },
      turn: {
        turnId: 't1',
        phase: 'selecting_position',
        activePlayerId: 'p1',
        activeSlotIndex: null,
        candidates: [],
        turnStartedAt: null,
      },
      currentRoundSlotIndex: null, // no slot chosen yet — matches selecting_position
      orderedHiddenDeck: [],
    });

    // p1 disconnects right at the very start and NEVER reconnects for the
    // rest of the test — the worst case: every one of their turns this
    // whole draft must be auto-picked.
    gateway.handleDisconnect({ id: 'sock-p1' } as never);

    // p1 is the round's first picker (selecting_position/selecting_card),
    // which isn't gated by _scheduleTurnTimer's own disconnect check at the
    // very start (nothing has called it yet for this fresh turn) — the
    // proactive handleDisconnect-triggered grace timer covers it.
    jest.advanceTimersByTime(GRACE_MS + 100);

    let current = gameService.getSessionByRoomCode(ROOM_CODE)!;
    // p1's first-picker turn was auto-picked (position + card), handing off
    // to p2 as first_player_order or straight into hidden_pick territory —
    // whatever pickCard's own multiplayer flow does next.
    expect(current.pitches.p1.filledCount).toBeGreaterThan(0);

    // Drain every remaining chained timer (grace + reveal, repeated for
    // every turn of this short 2-round draft) in one big jump — Jest's fake
    // timers process newly-scheduled timers that fall within the advanced
    // window too, so a single sufficiently-large advance fires the whole
    // chain exactly as real time would, just without a real 20+ minute test.
    jest.advanceTimersByTime(30 * (GRACE_MS + REVEAL_MS));
    current = gameService.getSessionByRoomCode(ROOM_CODE)!;

    // The draft must have moved past 'drafting' (into ability_draft/
    // ability_activation/subs — whichever this room's config lands on)
    // rather than being stuck waiting on p1 forever.
    expect(current.status).not.toBe('drafting');
    // p1, disconnected for the ENTIRE draft, still ends up with BOTH
    // positions filled — no weaker, incomplete squad compared to p2.
    expect(current.pitches.p1.filledCount).toBe(2);
    expect(current.pitches.p2.filledCount).toBe(2);
  });
});
