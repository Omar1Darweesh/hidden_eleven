import { ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { ThrottlerStorageService } from '@nestjs/throttler';
import { MESSAGE_METADATA } from '@nestjs/websockets/constants';
import 'reflect-metadata';
import { RoomsGateway } from './rooms.gateway';
import { RoomsService } from './rooms.service';
import { GameService } from '../game/game.service';
import { GameSession } from '../game/interfaces/game-session.interface';
import { generateReconnectToken } from '../reconnect-token';
import { WsThrottlerGuard } from './ws-throttler.guard';
import { resetIpThrottleBuckets } from './ws-ip-throttle';

/**
 * Regression coverage for the stale-room-deletion bug: an active, unfinished
 * game session with a connected player must never be swept by the 60-minute
 * inactivity cleanup, even if `lastActivityAt` is (for whatever reason) old —
 * this is the belt-and-suspenders guard in `_cleanStaleRooms()`. A genuinely
 * abandoned, never-started lobby must still be cleaned up as before.
 */
describe('RoomsGateway — stale-room cleanup', () => {
  let roomsService: RoomsService;
  let gameService: GameService;
  let gateway: RoomsGateway;
  const T0 = 1_000_000_000;

  beforeEach(() => {
    jest.spyOn(Date, 'now').mockReturnValue(T0);
    roomsService = new RoomsService();
    gameService = new GameService();
    gateway = new RoomsGateway(roomsService, gameService);
  });

  afterEach(() => {
    gateway.onModuleDestroy();
    jest.restoreAllMocks();
  });

  it('never deletes a room with an active session and a connected player, even if stale by lastActivityAt', () => {
    const { room } = roomsService.createRoom('Host', 'sock-host');
    roomsService.joinRoom(room.code, 'Player2', 'sock-p2');
    roomsService.startGame('sock-host');
    gameService.createSession(room);

    // Jump 61 minutes ahead with NO activity touches in between — this is
    // deliberately the worst case for the primary fix (0.1's touchRoomActivity
    // calls), to prove the independent second line of defense holds on its own.
    jest.spyOn(Date, 'now').mockReturnValue(T0 + 61 * 60 * 1000);

    (gateway as unknown as { _cleanStaleRooms(): void })._cleanStaleRooms();

    expect(roomsService.getRoom(room.code)).toBeDefined();
    expect(gameService.getSessionByRoomCode(room.code)).toBeDefined();
  });

  it('still cleans up a genuinely abandoned, never-started lobby past the cutoff', () => {
    const { room } = roomsService.createRoom('Host', 'sock-host');
    // No second player, no startGame, no session — a real abandoned lobby.

    jest.spyOn(Date, 'now').mockReturnValue(T0 + 61 * 60 * 1000);

    (gateway as unknown as { _cleanStaleRooms(): void })._cleanStaleRooms();

    expect(roomsService.getRoom(room.code)).toBeUndefined();
  });
});

/**
 * Regression coverage for the ability-draft hang fix: a picker who never acts
 * must be auto-picked for after a timeout, exactly like the existing
 * per-turn draft timer does for the player draft. Uses a directly-injected
 * session fixture (rather than driving the real flow, which would couple the
 * test to whatever abilities admin-data/abilities.json currently has enabled
 * on disk) so this test is fully isolated and deterministic.
 */
describe('RoomsGateway — ability-draft timeout', () => {
  let roomsService: RoomsService;
  let gameService: GameService;
  let gateway: RoomsGateway;
  const ROOM_CODE = 'ABILTY';
  const SESSION_ID = 'sess-ability';

  function abilityDraftSession(
    overrides: Partial<GameSession> = {},
  ): GameSession {
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
      pitches: {
        p1: { playerId: 'p1', slots: [], filledCount: 0 },
        p2: { playerId: 'p2', slots: [], filledCount: 0 },
      },
      baseTurnOrder: ['p1', 'p2'],
      currentRound: 1,
      totalRounds: 11,
      currentTurnIndex: 0,
      currentRoundSlotIndex: null,
      draftedCardIds: new Set(),
      roundCandidates: [],
      orderedHiddenDeck: [],
      hiddenPicksTaken: new Set(),
      hiddenPicksMap: new Map(),
      hiddenPickReveal: null,
      turn: {
        turnId: 't1',
        phase: 'selecting_position',
        activePlayerId: 'p1',
        activeSlotIndex: null,
        candidates: [],
        turnStartedAt: null,
      },
      turnTimeoutPolicy: { enabled: false, turnSeconds: null, onExpiry: null },
      status: 'ability_draft',
      abilityDraft: {
        pool: [
          { id: 0, type: 'captain', pickedBy: 'p1' }, // p1 already picked
          { id: 1, type: 'yellow', pickedBy: null }, // p2's turn next
        ],
        pickOrder: ['p1', 'p2'],
        currentPickIndex: 1,
      },
      playerAbilities: { p1: { type: 'captain', status: 'pending' } },
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

  function inject(session: GameSession): void {
    (
      gameService as unknown as { sessions: Map<string, GameSession> }
    ).sessions.set(session.sessionId, session);
    (
      gameService as unknown as { roomToSession: Map<string, string> }
    ).roomToSession.set(session.roomCode, session.sessionId);
  }

  beforeEach(() => {
    jest.useFakeTimers();
    roomsService = new RoomsService();
    gameService = new GameService();
    gateway = new RoomsGateway(roomsService, gameService);
    roomsService.createRoom('Alice', 'sock-p1');
    // Re-key the auto-generated room to our fixed test room code so the
    // injected session's roomCode lines up with it.
    const created = (roomsService as unknown as { rooms: Map<string, unknown> })
      .rooms;
    const [code, room] = [...created.entries()][0];
    created.delete(code);
    (room as { code: string }).code = ROOM_CODE;
    created.set(ROOM_CODE, room);
    (
      roomsService as unknown as {
        socketIndex: Map<string, { roomCode: string; playerId: string }>;
      }
    ).socketIndex.set('sock-p1', { roomCode: ROOM_CODE, playerId: 'p1' });
  });

  afterEach(() => {
    gateway.onModuleDestroy();
    jest.useRealTimers();
  });

  it('arms a timer for the current picker and clears it on manual pick (no leaked handles)', () => {
    const session = abilityDraftSession();
    inject(session);

    (
      gateway as unknown as {
        _scheduleAbilityDraftTimer(s: GameSession, rc: string): void;
      }
    )._scheduleAbilityDraftTimer(session, ROOM_CODE);

    const timers = (
      gateway as unknown as { _abilityDraftTimers: Map<string, unknown> }
    )._abilityDraftTimers;
    expect(timers.has(SESSION_ID)).toBe(true);

    (
      gateway as unknown as { _clearAbilityDraftTimer(id: string): void }
    )._clearAbilityDraftTimer(SESSION_ID);
    expect(timers.has(SESSION_ID)).toBe(false);
  });

  it('auto-picks for the idle picker once the timeout fires, and onModuleDestroy leaves no dangling timers', () => {
    const session = abilityDraftSession();
    inject(session);

    (
      gateway as unknown as {
        _scheduleAbilityDraftTimer(s: GameSession, rc: string): void;
      }
    )._scheduleAbilityDraftTimer(session, ROOM_CODE);

    // Fire the (fallback, since no per-turn timer is configured) auto-pick timeout.
    jest.advanceTimersByTime(31_000);

    // p2 (the idle picker) must now have an ability — the only remaining card.
    expect(session.playerAbilities.p2).toBeDefined();
    expect(session.abilityDraft!.pool.every((c) => c.pickedBy !== null)).toBe(
      true,
    );

    // Both picks are done, so the draft timer for this session must be gone —
    // not left running uselessly (or worse, double-firing later).
    const timers = (
      gateway as unknown as { _abilityDraftTimers: Map<string, unknown> }
    )._abilityDraftTimers;
    expect(timers.has(SESSION_ID)).toBe(false);

    // No leaked setTimeout handles process-wide after teardown.
    gateway.onModuleDestroy();
    expect(jest.getTimerCount()).toBe(0);
  });
});

/**
 * Regression coverage for Task 3.6: kicking or leave_permanently-ing a
 * player during 'ability_draft' or 'ability_activation' previously had no
 * handling for either phase — a removed player left either phase stalled
 * forever for everyone else. Verifies the GATEWAY WIRING specifically (that
 * handleKickPlayer/handleLeaveGamePermanently actually invoke the new
 * _afterPlayerRemoved → _afterAbilityPick / _maybeArmAbilityActivationTimer
 * path end-to-end, including the real reveal-window timer) — the underlying
 * removePlayer state-mutation logic itself is covered exhaustively at the
 * GameService level in game.service.ability.spec.ts.
 */
describe('RoomsGateway — removePlayer ability-phase awareness (Task 3.6)', () => {
  let roomsService: RoomsService;
  let gameService: GameService;
  let gateway: RoomsGateway;
  const ROOM_CODE = 'ABLTY2';
  const SESSION_ID = 'sess-ability-2';

  // 3 players throughout (not 2): _tryEndGame's pre-existing MIN_ACTIVE_PLAYERS
  // check unconditionally ends+deletes the session once player count drops
  // below 2 — a 2-player room kicked down to 1 would short-circuit BEFORE
  // this task's new logic ever runs. 3→2 stays above that floor, so these
  // tests actually exercise the ability-phase removal path, not the
  // pre-existing forfeit path.
  function abilityDraftSession(
    overrides: Partial<GameSession> = {},
  ): GameSession {
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
        { id: 'p3', displayName: 'Cara', isHost: false, isConnected: true },
      ],
      pitches: {
        p1: { playerId: 'p1', slots: [], filledCount: 0 },
        p2: { playerId: 'p2', slots: [], filledCount: 0 },
        p3: { playerId: 'p3', slots: [], filledCount: 0 },
      },
      baseTurnOrder: ['p1', 'p2', 'p3'],
      currentRound: 1,
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
      turn: {
        turnId: 't1',
        phase: 'selecting_position',
        activePlayerId: 'p1',
        activeSlotIndex: null,
        candidates: [],
        turnStartedAt: null,
      },
      turnTimeoutPolicy: { enabled: false, turnSeconds: null, onExpiry: null },
      status: 'ability_draft',
      abilityDraft: {
        pool: [
          { id: 0, type: 'captain', pickedBy: 'p1' },
          { id: 1, type: 'yellow', pickedBy: null },
          { id: 2, type: 'red', pickedBy: null },
        ],
        pickOrder: ['p1', 'p2', 'p3'],
        currentPickIndex: 2, // p1, p2 already picked; p3's turn (the last one)
      },
      playerAbilities: {
        p1: { type: 'captain', status: 'pending' },
        p2: { type: 'yellow', status: 'pending' },
      },
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

  function inject(session: GameSession): void {
    (
      gameService as unknown as { sessions: Map<string, GameSession> }
    ).sessions.set(session.sessionId, session);
    (
      gameService as unknown as { roomToSession: Map<string, string> }
    ).roomToSession.set(session.roomCode, session.sessionId);
  }

  /** Real 3-player room (p1 host, p2/p3 guests) so kickPlayer/
   *  leaveGamePermanently's own host/membership checks pass, matching the
   *  injected session's ids. */
  function setupRoom(): void {
    roomsService.createRoom('Alice', 'sock-p1');
    const rooms = (roomsService as unknown as { rooms: Map<string, any> })
      .rooms;
    const [code, room] = [...rooms.entries()][0];
    rooms.delete(code);
    room.code = ROOM_CODE;
    room.players = [
      {
        id: 'p1',
        displayName: 'Alice',
        isHost: true,
        isConnected: true,
        socketId: 'sock-p1',
      },
      {
        id: 'p2',
        displayName: 'Bob',
        isHost: false,
        isConnected: true,
        socketId: 'sock-p2',
      },
      {
        id: 'p3',
        displayName: 'Cara',
        isHost: false,
        isConnected: true,
        socketId: 'sock-p3',
      },
    ];
    rooms.set(ROOM_CODE, room);
    const socketIndex = (
      roomsService as unknown as {
        socketIndex: Map<string, { roomCode: string; playerId: string }>;
      }
    ).socketIndex;
    socketIndex.set('sock-p1', { roomCode: ROOM_CODE, playerId: 'p1' });
    socketIndex.set('sock-p2', { roomCode: ROOM_CODE, playerId: 'p2' });
    socketIndex.set('sock-p3', { roomCode: ROOM_CODE, playerId: 'p3' });
  }

  beforeEach(() => {
    jest.useFakeTimers();
    roomsService = new RoomsService();
    gameService = new GameService();
    gateway = new RoomsGateway(roomsService, gameService);
    setupRoom();
  });

  afterEach(() => {
    gateway.onModuleDestroy();
    jest.useRealTimers();
  });

  it('kicking the current ability-draft picker (the last one left to pick) completes the draft via the real reveal-window → beginPlayerDraft sequence', () => {
    inject(abilityDraftSession());

    (
      gateway as unknown as {
        handleKickPlayer(
          dto: { targetPlayerId: string },
          client: { id: string },
        ): void;
      }
    ).handleKickPlayer({ targetPlayerId: 'p3' }, { id: 'sock-p1' });

    const session = gameService.getSessionByRoomCode(ROOM_CODE)!;
    // Removed immediately: p3 dropped from pickOrder, still 'ability_draft'
    // (the gateway's reveal-window timing — same as a real final pick —
    // hasn't elapsed yet).
    expect(session.abilityDraft!.pickOrder).toEqual(['p1', 'p2']);
    expect(session.status).toBe('ability_draft');

    // Advance past the real 3.5s reveal window used by _afterAbilityPick.
    jest.advanceTimersByTime(3500);

    const after = gameService.getSessionByRoomCode(ROOM_CODE)!;
    expect(after.status).toBe('drafting'); // beginPlayerDraft ran for real
    expect(after.abilityDraft).toBeNull();
  });

  it('leave_game_permanently during ability_draft for a NON-final picker re-arms the draft timer for the remaining picker, without touching the draft-completion path', () => {
    inject(
      abilityDraftSession({
        abilityDraft: {
          pool: [
            { id: 0, type: 'captain', pickedBy: 'p1' },
            { id: 1, type: 'yellow', pickedBy: null },
            { id: 2, type: 'red', pickedBy: null },
          ],
          pickOrder: ['p1', 'p2', 'p3'],
          currentPickIndex: 1, // p2's turn — p3 hasn't picked yet either
        },
      }),
    );

    (
      gateway as unknown as {
        handleLeaveGamePermanently(dto: unknown, client: { id: string }): void;
      }
    ).handleLeaveGamePermanently(undefined, { id: 'sock-p2' });

    const after = gameService.getSessionByRoomCode(ROOM_CODE)!;
    expect(after.abilityDraft!.pickOrder).toEqual(['p1', 'p3']);
    expect(after.status).toBe('ability_draft'); // not complete — p3 still hasn't picked

    // The draft timer must have been re-armed (cleared+rescheduled by
    // _afterAbilityPick's !allPicked branch) for the new current picker —
    // not left stale/unset.
    const timers = (
      gateway as unknown as { _abilityDraftTimers: Map<string, unknown> }
    )._abilityDraftTimers;
    expect(timers.has(SESSION_ID)).toBe(true);
  });

  it('kicking a player with a pending ability during ability_activation auto-discards it, and (once everyone is resolved) reveals immediately then transitions to subs after the real 3.5s hold, clearing the activation timer', () => {
    inject(
      abilityDraftSession({
        status: 'ability_activation',
        abilityDraft: null,
        playerAbilities: {
          p1: { type: 'captain', status: 'used', targetPlayerId: 'B-ST-9' }, // host, already resolved
          p2: { type: 'yellow', status: 'pending' }, // about to be kicked
          // p3: no ability assigned at all — not every player drafts one.
        },
        abilityActivationDeadlineAt: Date.now() + 60_000,
      }),
    );

    // Arm the activation timer the way a real entry into the phase would,
    // so we can prove removal clears it once the phase completes.
    (
      gateway as unknown as {
        _maybeArmAbilityActivationTimer(s: GameSession, rc: string): void;
      }
    )._maybeArmAbilityActivationTimer(
      gameService.getSessionByRoomCode(ROOM_CODE)!,
      ROOM_CODE,
    );
    const activationTimers = (
      gateway as unknown as {
        _abilityActivationTimers: Map<string, unknown>;
      }
    )._abilityActivationTimers;
    expect(activationTimers.has(SESSION_ID)).toBe(true);

    (
      gateway as unknown as {
        handleKickPlayer(
          dto: { targetPlayerId: string },
          client: { id: string },
        ): void;
      }
    ).handleKickPlayer({ targetPlayerId: 'p2' }, { id: 'sock-p1' });

    // Removed immediately: p2 auto-discarded, everyone now resolved, so
    // revealAbilityActivations already ran synchronously (p1's captain use
    // is now in the public log) — but the phase hasn't finished yet, the
    // same reveal-then-hold timing real activate/discard calls use.
    const revealed = gameService.getSessionByRoomCode(ROOM_CODE)!;
    expect(revealed.status).toBe('ability_activation');
    expect(revealed.abilityActivationRevealed).toBe(true);
    expect(revealed.abilityActivations).toHaveLength(1);
    expect(revealed.abilityActivations[0]).toMatchObject({ byPlayerId: 'p1', type: 'captain' });
    expect(activationTimers.has(SESSION_ID)).toBe(false); // deadline timer cleared — nothing left to force

    // Advance past the real 3.5s reveal-hold window used by _afterAbilityActivation.
    jest.advanceTimersByTime(3500);

    const after = gameService.getSessionByRoomCode(ROOM_CODE)!;
    expect(after.status).toBe('lineup_edit'); // finishAbilityActivation ran for real
  });
});

/**
 * Phase 3 (player draft) hardening — regression coverage for the
 * personalized-broadcast fix in handleDisconnect/_scheduleActiveTurnSkip/
 * handleKickPlayer/handleLeaveGamePermanently. All four used to call
 * broadcastRoom('game_state', gameSnapshot(session)) with NO localPlayerId,
 * which — during 'drafting' specifically — meant the ACTIVE selecting_card
 * player's own turn.candidates (their live candidate pool, mid-decision)
 * would transiently blank to [] on every disconnect/kick/leave anywhere in
 * the room, not just their own. Fixed by switching all four call sites to
 * the already-existing per-socket-personalized _broadcastGameStateToRoom
 * helper (already used by every real gameplay action handler) instead of
 * broadcastRoom. Verifies the fix at the actual wire boundary — the raw
 * message a real socket receives — not just the session's internal state.
 */
describe('RoomsGateway — drafting-phase personalized game_state on disconnect/kick/leave (Phase 3)', () => {
  let roomsService: RoomsService;
  let gameService: GameService;
  let gateway: RoomsGateway;
  const ROOM_CODE = 'DRAFT3';
  const SESSION_ID = 'sess-draft-3';

  function draftingSession(overrides: Partial<GameSession> = {}): GameSession {
    const pool = [
      {
        cardId: 'c1',
        playerName: 'Card One',
        basePositionType: 'GK',
        rating: 80,
      },
      {
        cardId: 'c2',
        playerName: 'Card Two',
        basePositionType: 'GK',
        rating: 75,
      },
    ];
    return {
      sessionId: SESSION_ID,
      roomCode: ROOM_CODE,
      createdAt: Date.now(),
      leagues: [],
      playerBonusCache: new Map(),
      userChallengeCache: new Map(),
      formation: { name: '4-3-3', slots: [] } as any,
      players: [
        { id: 'p1', displayName: 'Alice', isHost: true, isConnected: true },
        { id: 'p2', displayName: 'Bob', isHost: false, isConnected: true },
        { id: 'p3', displayName: 'Cara', isHost: false, isConnected: true },
      ],
      pitches: {
        p1: { playerId: 'p1', slots: [], filledCount: 0 },
        p2: { playerId: 'p2', slots: [], filledCount: 0 },
        p3: { playerId: 'p3', slots: [], filledCount: 0 },
      },
      baseTurnOrder: ['p1', 'p2', 'p3'],
      currentRound: 1,
      totalRounds: 11,
      currentTurnIndex: 0,
      currentRoundSlotIndex: 0,
      draftedCardIds: new Set(),
      roundCandidates: pool as any,
      orderedHiddenDeck: [],
      hiddenPicksTaken: new Set(),
      hiddenPicksMap: new Map(),
      hiddenPickReveal: null,
      lastRoundLeftovers: [],
      // p1 is mid-selecting_card, actively holding its own candidate pool —
      // this is exactly the field that used to get wiped by a non-personalized
      // broadcast triggered by an UNRELATED player (p3) disconnecting.
      turn: {
        turnId: 't1',
        phase: 'selecting_card',
        activePlayerId: 'p1',
        activeSlotIndex: 0,
        candidates: pool as any,
        turnStartedAt: null,
      },
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

  function inject(session: GameSession): void {
    (
      gameService as unknown as { sessions: Map<string, GameSession> }
    ).sessions.set(session.sessionId, session);
    (
      gameService as unknown as { roomToSession: Map<string, string> }
    ).roomToSession.set(session.roomCode, session.sessionId);
  }

  function makeClient(id: string) {
    const sent: { event: string; data: unknown }[] = [];
    const client = {
      id,
      readyState: 1,
      send: (raw: string) => sent.push(JSON.parse(raw)),
      close: jest.fn(),
    };
    return { client, sent };
  }

  function connect(client: { id: string }): void {
    (
      gateway as unknown as { _connectedSockets: Map<string, unknown> }
    )._connectedSockets.set(client.id, client);
  }

  /** Real 3-player room matching the injected session's ids. */
  function setupRoom(): void {
    roomsService.createRoom('Alice', 'sock-p1');
    const rooms = (roomsService as unknown as { rooms: Map<string, any> })
      .rooms;
    const [code, room] = [...rooms.entries()][0];
    rooms.delete(code);
    room.code = ROOM_CODE;
    room.players = [
      {
        id: 'p1',
        displayName: 'Alice',
        isHost: true,
        isConnected: true,
        socketId: 'sock-p1',
      },
      {
        id: 'p2',
        displayName: 'Bob',
        isHost: false,
        isConnected: true,
        socketId: 'sock-p2',
      },
      {
        id: 'p3',
        displayName: 'Cara',
        isHost: false,
        isConnected: true,
        socketId: 'sock-p3',
      },
    ];
    rooms.set(ROOM_CODE, room);
    const socketIndex = (
      roomsService as unknown as {
        socketIndex: Map<string, { roomCode: string; playerId: string }>;
      }
    ).socketIndex;
    socketIndex.set('sock-p1', { roomCode: ROOM_CODE, playerId: 'p1' });
    socketIndex.set('sock-p2', { roomCode: ROOM_CODE, playerId: 'p2' });
    socketIndex.set('sock-p3', { roomCode: ROOM_CODE, playerId: 'p3' });
  }

  beforeEach(() => {
    roomsService = new RoomsService();
    gameService = new GameService();
    gateway = new RoomsGateway(roomsService, gameService);
    setupRoom();
  });

  afterEach(() => {
    gateway.onModuleDestroy();
  });

  it("an unrelated player (p3) disconnecting during drafting does not blank p1's own live candidate pool in the game_state p1 receives", () => {
    inject(draftingSession());
    const { client: p1, sent: p1Sent } = makeClient('sock-p1');
    connect(p1);
    const { client: p3 } = makeClient('sock-p3');
    connect(p3);

    gateway.handleDisconnect(p3 as never);

    const gameStates = p1Sent.filter((m) => m.event === 'game_state');
    expect(gameStates.length).toBeGreaterThan(0);
    const last = gameStates[gameStates.length - 1].data as any;
    expect(last.turn.candidates).toEqual(
      expect.arrayContaining([expect.objectContaining({ cardId: 'c1' })]),
    );
  });

  it("kick_player during drafting does not blank the active picker's own candidate pool in the game_state they receive", () => {
    inject(draftingSession());
    const { client: p1, sent: p1Sent } = makeClient('sock-p1');
    connect(p1);
    const { client: p3 } = makeClient('sock-p3');
    connect(p3);

    (
      gateway as unknown as {
        handleKickPlayer(
          dto: { targetPlayerId: string },
          client: { id: string },
        ): void;
      }
    ).handleKickPlayer({ targetPlayerId: 'p3' }, { id: 'sock-p1' });

    const gameStates = p1Sent.filter((m) => m.event === 'game_state');
    expect(gameStates.length).toBeGreaterThan(0);
    const last = gameStates[gameStates.length - 1].data as any;
    expect(last.turn.candidates).toEqual(
      expect.arrayContaining([expect.objectContaining({ cardId: 'c1' })]),
    );
  });
});

/**
 * Phase 5 audit — wiring coverage for removePlayer's new subs-phase
 * awareness (the game-service-level state mutation is covered exhaustively
 * in game.service.subs.spec.ts). Verifies handleKickPlayer actually reaches
 * that logic and the resulting 'finished' state (with a real result, no
 * timer needed) lands in the game_state broadcast every remaining player's
 * own socket receives — i.e. that kicking the last unconfirmed player
 * during subs no longer soft-locks the room.
 */
describe('RoomsGateway — removePlayer subs-phase awareness (Phase 5)', () => {
  let roomsService: RoomsService;
  let gameService: GameService;
  let gateway: RoomsGateway;
  const ROOM_CODE = 'SUBS02';
  const SESSION_ID = 'sess-subs-2';

  function subsSession(overrides: Partial<GameSession> = {}): GameSession {
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
        { id: 'p3', displayName: 'Cara', isHost: false, isConnected: true },
      ],
      pitches: {
        p1: { playerId: 'p1', slots: [], filledCount: 0 },
        p2: { playerId: 'p2', slots: [], filledCount: 0 },
        p3: { playerId: 'p3', slots: [], filledCount: 0 },
      },
      baseTurnOrder: ['p1', 'p2', 'p3'],
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
      turn: {
        turnId: 't1',
        phase: 'selecting_position',
        activePlayerId: 'p1',
        activeSlotIndex: null,
        candidates: [],
        turnStartedAt: null,
      },
      turnTimeoutPolicy: { enabled: false, turnSeconds: null, onExpiry: null },
      status: 'lineup_edit',
      abilityDraft: null,
      playerAbilities: {},
      abilityActivations: [],
      subSwappedCardIds: new Set(),
      isFinished: false,
      // p1 and p2 already confirmed — p3 (about to be kicked) is the ONLY
      // holdout, so removing them should complete the phase outright.
      subsPhase: {
        userSubs: {
          p1: { isComplete: true, lineupConfirmed: true, hasExtraBench: false },
          p2: { isComplete: true, lineupConfirmed: true, hasExtraBench: false },
          p3: {
            isComplete: false,
            lineupConfirmed: false,
            hasExtraBench: false,
          },
        },
      },
      subsTimerSeconds: null, // no timer armed — forceFinalizeLineupEdit can never rescue this room
      subsDeadlineAt: null,
      abilityActivationDeadlineAt: null,
      result: null,
      ...overrides,
    } as GameSession;
  }

  function inject(session: GameSession): void {
    (
      gameService as unknown as { sessions: Map<string, GameSession> }
    ).sessions.set(session.sessionId, session);
    (
      gameService as unknown as { roomToSession: Map<string, string> }
    ).roomToSession.set(session.roomCode, session.sessionId);
  }

  function makeClient(id: string) {
    const sent: { event: string; data: unknown }[] = [];
    const client = {
      id,
      readyState: 1,
      send: (raw: string) => sent.push(JSON.parse(raw)),
      close: jest.fn(),
    };
    return { client, sent };
  }

  function connect(client: { id: string }): void {
    (
      gateway as unknown as { _connectedSockets: Map<string, unknown> }
    )._connectedSockets.set(client.id, client);
  }

  function setupRoom(): void {
    roomsService.createRoom('Alice', 'sock-p1');
    const rooms = (roomsService as unknown as { rooms: Map<string, any> })
      .rooms;
    const [code, room] = [...rooms.entries()][0];
    rooms.delete(code);
    room.code = ROOM_CODE;
    room.players = [
      {
        id: 'p1',
        displayName: 'Alice',
        isHost: true,
        isConnected: true,
        socketId: 'sock-p1',
      },
      {
        id: 'p2',
        displayName: 'Bob',
        isHost: false,
        isConnected: true,
        socketId: 'sock-p2',
      },
      {
        id: 'p3',
        displayName: 'Cara',
        isHost: false,
        isConnected: true,
        socketId: 'sock-p3',
      },
    ];
    rooms.set(ROOM_CODE, room);
    const socketIndex = (
      roomsService as unknown as {
        socketIndex: Map<string, { roomCode: string; playerId: string }>;
      }
    ).socketIndex;
    socketIndex.set('sock-p1', { roomCode: ROOM_CODE, playerId: 'p1' });
    socketIndex.set('sock-p2', { roomCode: ROOM_CODE, playerId: 'p2' });
    socketIndex.set('sock-p3', { roomCode: ROOM_CODE, playerId: 'p3' });
  }

  beforeEach(() => {
    roomsService = new RoomsService();
    gameService = new GameService();
    gateway = new RoomsGateway(roomsService, gameService);
    setupRoom();
  });

  afterEach(() => {
    gateway.onModuleDestroy();
  });

  it("kicking the last unconfirmed player during subs (no timer armed) completes the phase — the game_state every remaining player receives shows 'finished' with a real result", () => {
    inject(subsSession());
    const { client: p1, sent: p1Sent } = makeClient('sock-p1');
    connect(p1);
    const { client: p2, sent: p2Sent } = makeClient('sock-p2');
    connect(p2);

    (
      gateway as unknown as {
        handleKickPlayer(
          dto: { targetPlayerId: string },
          client: { id: string },
        ): void;
      }
    ).handleKickPlayer({ targetPlayerId: 'p3' }, { id: 'sock-p1' });

    const session = gameService.getSessionByRoomCode(ROOM_CODE)!;
    expect(session.status).toBe('finished');
    expect(session.result).not.toBeNull();
    expect(session.result!.players.map((p) => p.playerId).sort()).toEqual([
      'p1',
      'p2',
    ]);

    for (const sent of [p1Sent, p2Sent]) {
      const gameStates = sent.filter((m) => m.event === 'game_state');
      expect(gameStates.length).toBeGreaterThan(0);
      const last = gameStates[gameStates.length - 1].data as any;
      expect(last.status).toBe('finished');
    }
  });
});

/**
 * Regression coverage for Task 1.3's real rate limiting (@nestjs/throttler),
 * replacing the Phase 0 hand-rolled token bucket previously tested here.
 * Constructs WsThrottlerGuard directly (bypassing Nest's DI container, the
 * same technique @nestjs/throttler's own test suite uses) against a real
 * ThrottlerStorageService, and drives it through a fake WS ExecutionContext.
 */
describe('WsThrottlerGuard (Task 1.3)', () => {
  function makeContext(
    socketId: string,
    sentMessages: string[],
    opts?: { clientIp?: string; eventName?: string },
  ): ExecutionContext {
    const client = {
      id: socketId,
      clientIp: opts?.clientIp,
      readyState: 1, // WebSocket.OPEN
      send: (raw: string) => sentMessages.push(raw),
    };
    const handler = () => ({});
    if (opts?.eventName) {
      Reflect.defineMetadata(MESSAGE_METADATA, opts.eventName, handler);
    }
    return {
      switchToWs: () => ({ getClient: () => client }),
      switchToHttp: () => ({}),
      getHandler: () => handler,
      getClass: () => ({ name: 'RoomsGateway' }),
    } as unknown as ExecutionContext;
  }

  // ThrottlerStorageService schedules its own internal expiry setTimeouts —
  // not torn down automatically, since it's normally an injected singleton
  // whose lifecycle Nest manages. Track every instance created by a test and
  // explicitly shut it down afterward so no test leaks a live timer into the
  // next one (or into jest's process-exit detection).
  const storages: ThrottlerStorageService[] = [];

  function makeGuard(limit: number, ttlMs: number): WsThrottlerGuard {
    const storage = new ThrottlerStorageService();
    storages.push(storage);
    const reflector = new Reflector();
    const guard = new WsThrottlerGuard(
      { throttlers: [{ name: 'default', limit, ttl: ttlMs }] },
      storage,
      reflector,
    );
    // Normally run by Nest's module lifecycle (onModuleInit) — invoked
    // manually here since the guard is constructed outside DI.
    void (guard as unknown as { onModuleInit(): Promise<void> }).onModuleInit();
    return guard;
  }

  afterEach(() => {
    storages.forEach((s) => s.onApplicationShutdown());
    storages.length = 0;
    resetIpThrottleBuckets();
    jest.restoreAllMocks();
  });

  it('allows calls under the limit and blocks (with a clean RATE_LIMITED message) the call that exceeds it', async () => {
    const guard = makeGuard(5, 10_000);
    const sent: string[] = [];
    const ctx = makeContext('sock-a', sent);

    for (let i = 0; i < 5; i++) {
      expect(await guard.canActivate(ctx)).toBe(true);
    }
    // 6th call within the same window is over the limit.
    expect(await guard.canActivate(ctx)).toBe(false);
    expect(sent).toHaveLength(1);
    expect(JSON.parse(sent[0])).toEqual({
      event: 'error',
      data: { code: 'RATE_LIMITED' },
    });
  });

  it('tracks each socket independently — one socket being limited does not affect another', async () => {
    const guard = makeGuard(5, 10_000);
    const sentA: string[] = [];
    const sentB: string[] = [];
    const ctxA = makeContext('sock-a', sentA);
    const ctxB = makeContext('sock-b', sentB);

    for (let i = 0; i < 5; i++) await guard.canActivate(ctxA);
    expect(await guard.canActivate(ctxA)).toBe(false);

    // A different connection has its own, untouched counter.
    expect(await guard.canActivate(ctxB)).toBe(true);
    expect(sentB).toHaveLength(0);
  });

  it('allows calls again once the window elapses', async () => {
    jest.useFakeTimers({ doNotFake: ['nextTick'] });
    try {
      const guard = makeGuard(5, 10_000);
      const sent: string[] = [];
      const ctx = makeContext('sock-a', sent);

      for (let i = 0; i < 5; i++) await guard.canActivate(ctx);
      expect(await guard.canActivate(ctx)).toBe(false);

      jest.advanceTimersByTime(10_001);
      expect(await guard.canActivate(ctx)).toBe(true);
    } finally {
      jest.useRealTimers();
    }
  });

  it('IP-throttles join_room across different socket ids from the same IP', async () => {
    // Per-socket limit is high so only the IP bucket (15/60s) can block.
    const guard = makeGuard(100, 10_000);
    const sent: string[] = [];
    const ip = '203.0.113.10';

    for (let i = 0; i < 15; i++) {
      const ctx = makeContext(`sock-${i}`, sent, {
        clientIp: ip,
        eventName: 'join_room',
      });
      expect(await guard.canActivate(ctx)).toBe(true);
    }

    const blocked = makeContext('sock-final', sent, {
      clientIp: ip,
      eventName: 'join_room',
    });
    expect(await guard.canActivate(blocked)).toBe(false);
    expect(JSON.parse(sent[sent.length - 1])).toEqual({
      event: 'error',
      data: { code: 'RATE_LIMITED' },
    });
  });

  it('does not IP-throttle a normal gameplay event (pick_slot)', async () => {
    const guard = makeGuard(100, 10_000);
    const sent: string[] = [];
    const ip = '203.0.113.11';

    for (let i = 0; i < 20; i++) {
      const ctx = makeContext(`sock-${i}`, sent, {
        clientIp: ip,
        eventName: 'pick_slot',
      });
      expect(await guard.canActivate(ctx)).toBe(true);
    }
    expect(sent).toHaveLength(0);
  });
});

/**
 * Regression coverage for a CRITICAL bug found during the Phase 0
 * production-safety review: when the LAST connected player in an active game
 * disconnects, `roomsService` deletes the room internally, but — before this
 * fix — `RoomsGateway.handleDisconnect()` never called `gameService.endSession()`
 * for that case. The orphaned GameSession lived forever: `_cleanStaleRooms()`
 * can never find it (it only scans `roomsService`'s rooms, and the room is
 * already gone), and any timer still armed for it would keep firing and
 * silently auto-advancing an abandoned game in the background indefinitely.
 * See PHASE_0_FINAL_REVIEW.md for the full writeup.
 */
describe('RoomsGateway — orphaned session on full disconnect (critical fix)', () => {
  let roomsService: RoomsService;
  let gameService: GameService;
  let gateway: RoomsGateway;

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

  it('ends the session and clears its timers when the last connected player disconnects mid-game', () => {
    const { room } = roomsService.createRoom('Host', 'sock-host');
    roomsService.joinRoom(room.code, 'Player2', 'sock-p2');
    roomsService.startGame('sock-host');
    const session = gameService.createSession(room);

    // Arm a turn timer for this session, exactly like a real drafting turn
    // would — this is the concrete thing that, before the fix, would have
    // kept firing forever against the orphaned session. Force status to
    // 'drafting' explicitly so this test is deterministic regardless of
    // whatever abilities admin-data/abilities.json currently has enabled on
    // disk (createSession may otherwise start the real session in
    // 'ability_draft' instead).
    (
      gateway as unknown as {
        _scheduleTurnTimer(s: GameSession, rc: string): void;
      }
    )._scheduleTurnTimer(
      {
        ...session,
        status: 'drafting',
        turnTimeoutPolicy: {
          enabled: true,
          turnSeconds: 30,
          onExpiry: 'auto_pick_random',
        },
      } as GameSession,
      room.code,
    );

    // First disconnect: Player2 leaves, but Host is still connected — the
    // room and session must both survive untouched.
    gateway.handleDisconnect({ id: 'sock-p2' } as never);
    expect(roomsService.getRoom(room.code)).toBeDefined();
    expect(gameService.getSessionByRoomCode(room.code)).toBeDefined();

    // Second disconnect: Host was the last connected player. The room is
    // deleted by roomsService internally — the bug was that the session
    // and its timers were left behind, orphaned, forever.
    gateway.handleDisconnect({ id: 'sock-host' } as never);

    expect(roomsService.getRoom(room.code)).toBeUndefined();
    expect(gameService.getSessionByRoomCode(room.code)).toBeUndefined(); // ← the actual fix

    // The turn timer armed for this session must be cleared, not left
    // dangling against an ended session (checked directly, not via
    // jest.getTimerCount() — the gateway's own background cleanupTimer
    // interval is correctly still running at this point and would otherwise
    // make this assertion always fail regardless of the fix).
    const turnTimers = (
      gateway as unknown as { _turnTimers: Map<string, unknown> }
    )._turnTimers;
    expect(turnTimers.has(session.sessionId)).toBe(false);
  });

  it('does not touch the session/room when the disconnecting socket has no active entry', () => {
    // A socket that was never associated with a room (e.g. it disconnected
    // before ever sending a message) must be a safe no-op, not a crash.
    expect(() =>
      gateway.handleDisconnect({ id: 'sock-ghost' } as never),
    ).not.toThrow();
  });
});

/**
 * Regression coverage for Task 1.1 (Phase 1): `reconnect` and `check_presence`
 * previously trusted a bare client-supplied playerId with no cryptographic
 * binding — anyone who learned a player's playerId + roomCode (visible to
 * every player in the room via room_update.players[].id) could hijack their
 * seat. Both handlers now require a `reconnectToken` issued at
 * create_room/join_room/approve_join time and verify it server-side.
 */
describe('RoomsGateway — signed reconnect tokens (Task 1.1)', () => {
  let roomsService: RoomsService;
  let gameService: GameService;
  let gateway: RoomsGateway;

  function makeClient(id: string) {
    const sent: { event: string; data: unknown }[] = [];
    const client = {
      id,
      readyState: 1, // WebSocket.OPEN
      send: (raw: string) => sent.push(JSON.parse(raw)),
    };
    return { client, sent };
  }

  beforeEach(() => {
    roomsService = new RoomsService();
    gameService = new GameService();
    gateway = new RoomsGateway(roomsService, gameService);
  });

  afterEach(() => {
    gateway.onModuleDestroy();
  });

  it('create_room returns a reconnectToken alongside the playerId', () => {
    const { client, sent } = makeClient('sock-host');

    gateway.handleCreateRoom(
      { displayName: 'Host', leagues: [] } as never,
      client as never,
    );

    const roomUpdate = sent.find((m) => m.event === 'room_update');
    expect(roomUpdate).toBeDefined();
    const data = roomUpdate!.data as {
      localPlayerId: string;
      reconnectToken: string;
    };
    expect(typeof data.reconnectToken).toBe('string');
    expect(data.reconnectToken.length).toBeGreaterThan(0);
    expect(data.localPlayerId).toBeTruthy();
  });

  it('reconnect succeeds with a valid token', () => {
    const { room, playerId } = roomsService.createRoom('Host', 'sock-host');
    const token = generateReconnectToken(playerId, room.code);

    const { client, sent } = makeClient('sock-host-2');

    gateway.handleReconnect(
      { roomCode: room.code, playerId, reconnectToken: token } as never,
      client as never,
    );

    expect(sent.some((m) => m.event === 'error')).toBe(false);
    expect(sent.some((m) => m.event === 'room_update')).toBe(true);
  });

  it('reconnect is rejected with INVALID_TOKEN when no token is supplied', () => {
    const { room, playerId } = roomsService.createRoom('Host', 'sock-host');

    const { client, sent } = makeClient('sock-host-2');

    gateway.handleReconnect(
      {
        roomCode: room.code,
        playerId,
        reconnectToken: undefined as unknown as string,
      } as never,
      client as never,
    );

    expect(sent).toEqual([{ event: 'error', data: { code: 'INVALID_TOKEN' } }]);
  });

  it('reconnect is rejected with INVALID_TOKEN when the token is tampered with', () => {
    const { room, playerId } = roomsService.createRoom('Host', 'sock-host');
    const token = generateReconnectToken(playerId, room.code);
    const tampered = token.slice(0, -2) + 'xx';

    const { client, sent } = makeClient('sock-host-2');

    gateway.handleReconnect(
      { roomCode: room.code, playerId, reconnectToken: tampered } as never,
      client as never,
    );

    expect(sent).toEqual([{ event: 'error', data: { code: 'INVALID_TOKEN' } }]);
  });

  it('reconnect is rejected with INVALID_TOKEN when the token was issued for a different room', () => {
    const { playerId } = roomsService.createRoom('Host', 'sock-host');
    const { room: otherRoom } = roomsService.createRoom(
      'Someone',
      'sock-other',
    );
    const tokenForWrongRoom = generateReconnectToken(playerId, otherRoom.code);

    const { client, sent } = makeClient('sock-host-2');

    gateway.handleReconnect(
      {
        roomCode: otherRoom.code,
        playerId,
        reconnectToken: tokenForWrongRoom,
      } as never,
      client as never,
    );

    // Token verifies for otherRoom's code, but playerId never belonged to
    // that room — the underlying roomsService.reconnect() lookup fails next,
    // proving the token check alone isn't enough and the room is still safe.
    expect(sent.some((m) => m.event === 'error')).toBe(true);
  });

  it('check_presence is rejected with INVALID_TOKEN when the token does not match the playerId', () => {
    const { room, playerId } = roomsService.createRoom('Host', 'sock-host');
    const tokenForSomeoneElse = generateReconnectToken(
      'a-different-player-id',
      room.code,
    );

    const { client, sent } = makeClient('sock-host-2');

    gateway.handleCheckPresence(
      {
        playerId,
        roomCode: room.code,
        reconnectToken: tokenForSomeoneElse,
      } as never,
      client as never,
    );

    expect(sent).toEqual([{ event: 'error', data: { code: 'INVALID_TOKEN' } }]);
  });

  it('check_presence succeeds with a valid token', () => {
    const { room, playerId } = roomsService.createRoom('Host', 'sock-host');
    roomsService.createRoom('Player2', 'sock-p2'); // ensure MIN_PLAYERS unrelated noise doesn't matter
    const token = generateReconnectToken(playerId, room.code);

    // Simulate the original socket going away, then reconnecting on a new one.
    const { client, sent } = makeClient('sock-host-new');

    gateway.handleCheckPresence(
      { playerId, roomCode: room.code, reconnectToken: token } as never,
      client as never,
    );

    expect(
      sent.some(
        (m) =>
          m.event === 'error' &&
          (m.data as { code: string }).code === 'INVALID_TOKEN',
      ),
    ).toBe(false);
  });

  it('check_presence succeeds and restores the same authoritative room+game snapshot, not a stale one', () => {
    // "Reconnect success restores the same room snapshot" — proves the
    // full happy path this fix must never regress: a valid check_presence
    // re-associates the player with their EXISTING room/session (not a new
    // one) and the response reflects that session's true current state.
    const { room, playerId } = roomsService.createRoom('Host', 'sock-host');
    roomsService.joinRoom(room.code, 'Player2', 'sock-p2');
    roomsService.startGame('sock-host');
    const session = gameService.createSession(room);
    const token = generateReconnectToken(playerId, room.code);

    const { client, sent } = makeClient('sock-host-new');
    // game_state is delivered via _broadcastGameStateToRoom -> sendToSocket,
    // which only reaches sockets registered in _connectedSockets (normally
    // populated by handleConnection) — register this mock client the same
    // way the graceful-shutdown suite's own `connect()` helper does.
    (
      gateway as unknown as { _connectedSockets: Map<string, unknown> }
    )._connectedSockets.set(client.id, client);
    gateway.handleCheckPresence(
      { playerId, roomCode: room.code, reconnectToken: token } as never,
      client as never,
    );

    expect(sent.some((m) => m.event === 'error')).toBe(false);
    const roomUpdate = sent.find((m) => m.event === 'room_update');
    expect(roomUpdate).toBeDefined();
    expect((roomUpdate!.data as { code: string }).code).toBe(room.code);
    const gameState = sent.find((m) => m.event === 'game_state');
    expect(gameState).toBeDefined();
    expect((gameState!.data as { sessionId: string }).sessionId).toBe(
      session.sessionId,
    );
    // The reconnecting socket is now the authoritative one for this player —
    // proves roomsService.reconnect() actually re-associated it, not just
    // that a response was sent.
    expect(roomsService.getSocketEntry('sock-host-new')).toEqual({
      roomCode: room.code,
      playerId,
    });
  });

  /**
   * Regression coverage for the QMNGFR -> LXQWLK client-divergence bug: a
   * client whose check_presence is rejected must get a clean, well-formed
   * NOT_FOUND — nothing that could be mistaken for success, and nothing
   * that corrupts server state for a LATER, legitimate check_presence
   * (e.g. this same tab retrying, or the room being correctly recreated
   * under a fresh code). See PROJECT_OVERVIEW.md: a server restart wipes
   * the in-memory session store entirely, so a browser tab left open from
   * before the restart fails check_presence with exactly this shape.
   */
  describe('check_presence — server-restart / stale-room scenario (client-divergence bug)', () => {
    it('is rejected with a clean NOT_FOUND for a token whose room no longer exists anywhere server-side', () => {
      // Simulates a server restart: generateReconnectToken is a pure HMAC
      // function of (playerId, roomCode) with no dependency on RoomsService
      // state, so a token "issued before the restart" is trivially
      // reproducible against a completely fresh RoomsService/GameService —
      // exactly what an old browser tab presents after the process restarts.
      const staleToken = generateReconnectToken('old-player-id', 'QMNGFR');
      const { client, sent } = makeClient('sock-old-tab');

      gateway.handleCheckPresence(
        {
          playerId: 'old-player-id',
          roomCode: 'QMNGFR',
          reconnectToken: staleToken,
        } as never,
        client as never,
      );

      expect(sent).toEqual([{ event: 'error', data: { code: 'NOT_FOUND' } }]);
      // Must not have fabricated a room/session as a side effect.
      expect(roomsService.getRoom('QMNGFR')).toBeUndefined();
      expect(gameService.getSessionByRoomCode('QMNGFR')).toBeUndefined();
    });

    it('a repeated rejected check_presence from the same stale tab stays a clean NOT_FOUND each time (no state corruption, no throw)', () => {
      const staleToken = generateReconnectToken('old-player-id', 'QMNGFR');

      for (let i = 0; i < 3; i++) {
        const { client, sent } = makeClient(`sock-old-tab-${i}`);
        expect(() =>
          gateway.handleCheckPresence(
            {
              playerId: 'old-player-id',
              roomCode: 'QMNGFR',
              reconnectToken: staleToken,
            } as never,
            client as never,
          ),
        ).not.toThrow();
        expect(sent).toEqual([{ event: 'error', data: { code: 'NOT_FOUND' } }]);
      }
    });

    it('a rejected check_presence for one (stale) room does not affect an unrelated, currently-live room', () => {
      // The two-client-divergence scenario from the bug report: one client
      // (web) fails to reconnect into the OLD room; a second client
      // (emulator) is meanwhile still live in a DIFFERENT, real room. The
      // rejected reconnect for the first must have zero effect on the second.
      const { room: liveRoom, playerId: livePlayerId } =
        roomsService.createRoom('Host', 'sock-live-host');
      const liveToken = generateReconnectToken(livePlayerId, liveRoom.code);

      const staleToken = generateReconnectToken('old-player-id', 'QMNGFR');
      const { client: staleClient, sent: staleSent } =
        makeClient('sock-old-tab');
      gateway.handleCheckPresence(
        {
          playerId: 'old-player-id',
          roomCode: 'QMNGFR',
          reconnectToken: staleToken,
        } as never,
        staleClient as never,
      );
      expect(staleSent).toEqual([
        { event: 'error', data: { code: 'NOT_FOUND' } },
      ]);

      const { client: liveClient, sent: liveSent } =
        makeClient('sock-live-host-new');
      gateway.handleCheckPresence(
        {
          playerId: livePlayerId,
          roomCode: liveRoom.code,
          reconnectToken: liveToken,
        } as never,
        liveClient as never,
      );
      expect(liveSent.some((m) => m.event === 'error')).toBe(false);
      expect(liveSent.some((m) => m.event === 'room_update')).toBe(true);
    });
  });
});

/**
 * Regression coverage for Task 1.6's graceful shutdown: broadcastShutdownWarning()
 * (called by main.ts's SIGTERM handler before the drain window) and
 * onApplicationShutdown() (the NestJS lifecycle hook that runs as part of
 * app.close(), after the drain window has elapsed).
 */
describe('RoomsGateway — graceful shutdown (Task 1.6)', () => {
  let roomsService: RoomsService;
  let gameService: GameService;
  let gateway: RoomsGateway;

  function makeClient(id: string, readyState = 1 /* OPEN */) {
    const sent: { event: string; data: unknown }[] = [];
    const client = {
      id,
      readyState,
      send: (raw: string) => sent.push(JSON.parse(raw)),
      close: jest.fn(),
    };
    return { client, sent };
  }

  // Task 2.1: broadcastShutdownWarning/onApplicationShutdown now iterate the
  // gateway's own _connectedSockets map (populated by handleConnection),
  // not this.server.clients directly — see rooms.gateway.ts for why.
  function connect(client: { id: string }): void {
    (
      gateway as unknown as { _connectedSockets: Map<string, unknown> }
    )._connectedSockets.set(client.id, client);
  }

  beforeEach(() => {
    roomsService = new RoomsService();
    gameService = new GameService();
    gateway = new RoomsGateway(roomsService, gameService);
  });

  afterEach(() => {
    gateway.onModuleDestroy();
  });

  it('broadcastShutdownWarning sends a server_shutdown event to every open socket', () => {
    const { client: openA, sent: sentA } = makeClient('sock-a');
    const { client: openB, sent: sentB } = makeClient('sock-b');
    const CLOSED = 3;
    const { client: closedC, sent: sentC } = makeClient('sock-c', CLOSED);
    [openA, openB, closedC].forEach(connect);

    gateway.broadcastShutdownWarning();

    expect(sentA).toEqual([
      {
        event: 'server_shutdown',
        data: { message: 'Server restarting, please reconnect in a moment' },
      },
    ]);
    expect(sentB).toHaveLength(1);
    // A socket that's already closed must not be written to.
    expect(sentC).toHaveLength(0);
  });

  it('onApplicationShutdown closes every still-open socket with a clean close frame', () => {
    const { client: openA } = makeClient('sock-a');
    const { client: openB } = makeClient('sock-b');
    const CLOSED = 3;
    const { client: closedC } = makeClient('sock-c', CLOSED);
    [openA, openB, closedC].forEach(connect);

    gateway.onApplicationShutdown('SIGTERM');

    expect(openA.close).toHaveBeenCalledWith(1001, 'Server shutting down');
    expect(openB.close).toHaveBeenCalledWith(1001, 'Server shutting down');
    // Already-closed sockets are left alone, not double-closed.
    expect(closedC.close).not.toHaveBeenCalled();
  });

  it('onApplicationShutdown does not throw when no sockets are connected', () => {
    expect(() => gateway.onApplicationShutdown()).not.toThrow();
  });
});

/**
 * Regression coverage for Task 1.7's zombie-connection heartbeat: a TCP
 * connection that dies without a clean WS close frame (laptop lid closed,
 * network partition) never fires handleDisconnect on its own — see
 * PHASE_0_FINAL_REVIEW.md's residual-risk section. ping/pong detects and
 * terminates such a connection, which in turn does fire handleDisconnect via
 * the real 'close' event.
 */
describe('RoomsGateway — heartbeat / zombie-connection detection (Task 1.7)', () => {
  let roomsService: RoomsService;
  let gameService: GameService;
  let gateway: RoomsGateway;
  const HEARTBEAT_INTERVAL_MS = 30_000;

  function makeClient(id: string) {
    const handlers: Record<string, () => void> = {};
    const client = {
      id,
      isAlive: undefined as boolean | undefined,
      ping: jest.fn(),
      terminate: jest.fn(),
      on: jest.fn((event: string, handler: () => void) => {
        handlers[event] = handler;
      }),
      // Test helper, not part of the real ws API surface.
      __triggerPong: () => handlers['pong']?.(),
    };
    return client;
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

  it('handleConnection marks a new socket alive and listens for pong', () => {
    const client = makeClient('sock-a');
    gateway.handleConnection(client as never);

    expect(client.isAlive).toBe(true);
    expect(client.on).toHaveBeenCalledWith('pong', expect.any(Function));
  });

  it('a responsive socket (replies to every ping) is never terminated', () => {
    const client = makeClient('sock-a');
    // handleConnection (Task 2.1) already populates _connectedSockets, which
    // _heartbeat() now reads — no separate server.clients setup needed.
    gateway.handleConnection(client as never);

    for (let i = 0; i < 4; i++) {
      jest.advanceTimersByTime(HEARTBEAT_INTERVAL_MS);
      client.__triggerPong(); // simulates the client always responding in time
    }

    expect(client.terminate).not.toHaveBeenCalled();
    expect(client.ping).toHaveBeenCalledTimes(4);
  });

  it('a socket that stops responding to pings is terminated within two heartbeat intervals', () => {
    // The standard ws pattern needs two missed ticks to confirm a connection
    // is actually dead (not just slow): tick 1 sends a ping and can't yet
    // tell the difference between "dead" and "about to reply"; only if NO
    // pong arrives before tick 2 is it terminated.
    const client = makeClient('sock-a');
    gateway.handleConnection(client as never);

    jest.advanceTimersByTime(HEARTBEAT_INTERVAL_MS); // tick 1: ping sent, not yet terminated
    expect(client.terminate).not.toHaveBeenCalled();
    expect(client.ping).toHaveBeenCalledTimes(1);
    // Client never replies with pong.

    jest.advanceTimersByTime(HEARTBEAT_INTERVAL_MS); // tick 2: still no pong since tick 1 — dead
    expect(client.terminate).toHaveBeenCalledTimes(1);
  });

  it('a terminated socket is removed and not pinged or terminated again on a later tick', () => {
    const client = makeClient('sock-a');
    gateway.handleConnection(client as never);
    // In the real server, terminate() fires a 'close' event that routes to
    // handleDisconnect(), which removes the socket from _connectedSockets
    // (Task 2.1) — simulated here so this mock matches real behavior
    // instead of asserting against a test-double artifact.
    const connectedSockets = (
      gateway as unknown as { _connectedSockets: Map<string, unknown> }
    )._connectedSockets;
    client.terminate.mockImplementation(() =>
      connectedSockets.delete(client.id),
    );

    jest.advanceTimersByTime(HEARTBEAT_INTERVAL_MS); // tick 1: ping sent
    jest.advanceTimersByTime(HEARTBEAT_INTERVAL_MS); // tick 2: no pong since tick 1 — terminated, removed
    jest.advanceTimersByTime(HEARTBEAT_INTERVAL_MS); // tick 3: no longer in clients — must be a no-op

    expect(client.terminate).toHaveBeenCalledTimes(1);
    expect(client.ping).toHaveBeenCalledTimes(1);
  });
});

/**
 * Regression coverage for Task 2.1's broadcast-loop optimization. Every
 * broadcast in this gateway used to iterate `this.server.clients` — every
 * socket connected to the WHOLE server, across every room — filtering down
 * to the room it actually needed. It now iterates `roomsService.getSocketIds
 * (roomCode)` (already O(room size)) and looks each one up directly in
 * `_connectedSockets` (a flat, O(1)-per-lookup map populated by
 * handleConnection/handleDisconnect — see rooms.gateway.ts for why this was
 * chosen over a per-room Set). These tests prove the content/targeting is
 * identical to the old behavior — a room-scoped broadcast must reach exactly
 * that room's sockets and no others — not just that it no longer crashes.
 */
describe('RoomsGateway — broadcast targeting (Task 2.1)', () => {
  let roomsService: RoomsService;
  let gameService: GameService;
  let gateway: RoomsGateway;

  function makeClient(id: string) {
    const sent: { event: string; data: unknown }[] = [];
    const client = {
      id,
      readyState: 1 /* OPEN */,
      send: (raw: string) => sent.push(JSON.parse(raw)),
      on: jest.fn(), // handleConnection (Task 1.7 heartbeat) registers a 'pong' listener
    };
    return { client, sent };
  }

  beforeEach(() => {
    roomsService = new RoomsService();
    gameService = new GameService();
    gateway = new RoomsGateway(roomsService, gameService);
  });

  afterEach(() => {
    gateway.onModuleDestroy();
  });

  it("a broadcast to one room reaches exactly that room's connected sockets, not sockets from an unrelated room", () => {
    // Room A: host + a second player about to join.
    const { client: hostClient, sent: hostSent } = makeClient('sock-host-a');
    gateway.handleConnection(hostClient as never);
    const { room: roomA, playerId: hostId } = roomsService.createRoom(
      'Host',
      hostClient.id,
    );
    void hostId;

    const { client: p2Client, sent: p2Sent } = makeClient('sock-p2-a');
    gateway.handleConnection(p2Client as never);

    // Room B: a completely unrelated, unconnected-to-A socket.
    const { client: otherRoomClient, sent: otherRoomSent } =
      makeClient('sock-other-room');
    gateway.handleConnection(otherRoomClient as never);
    roomsService.createRoom('SomeoneElse', otherRoomClient.id);

    // Player2 joining room A triggers handleJoinRoom's real broadcastRoom()
    // call to every socket in room A.
    gateway.handleJoinRoom(
      { roomCode: roomA.code, displayName: 'Player2' } as never,
      p2Client as never,
    );

    // Host (in room A) receives the room_update broadcast.
    expect(
      hostSent.some(
        (m) =>
          m.event === 'room_update' &&
          (m.data as { players: unknown[] }).players.length === 2,
      ),
    ).toBe(true);
    // Player2 also receives their own direct room_update response.
    expect(p2Sent.some((m) => m.event === 'room_update')).toBe(true);
    // The unrelated room's socket receives nothing at all — not even an
    // empty/malformed message — proving the iteration is genuinely scoped to
    // room A's socketIds, not every connected socket on the server.
    expect(otherRoomSent).toHaveLength(0);
  });

  it('handleDisconnect removes the socket from _connectedSockets — it is no longer reachable by any future broadcast', () => {
    const { client, sent } = makeClient('sock-a');
    gateway.handleConnection(client as never);
    const connectedSockets = (
      gateway as unknown as { _connectedSockets: Map<string, unknown> }
    )._connectedSockets;
    expect(connectedSockets.has('sock-a')).toBe(true);

    gateway.handleDisconnect(client as never);
    expect(connectedSockets.has('sock-a')).toBe(false);

    // A broadcast attempt referencing the now-gone socketId is a safe no-op,
    // not a stale send and not a crash.
    sent.length = 0;
    (
      gateway as unknown as {
        broadcastToSockets(ids: string[], event: string, data: unknown): void;
      }
    ).broadcastToSockets(['sock-a'], 'room_update', {});
    expect(sent).toHaveLength(0);
  });

  it('after a room is closed, roomsService.getSocketIds returns empty and a broadcast to that room is a safe no-op', () => {
    const { client, sent } = makeClient('sock-a');
    gateway.handleConnection(client as never);
    const { room } = roomsService.createRoom('Host', client.id);

    roomsService.closeRoom(room.code);
    expect(roomsService.getSocketIds(room.code)).toEqual([]);

    sent.length = 0;
    (
      gateway as unknown as {
        broadcastRoom(roomCode: string, event: string, data: unknown): void;
      }
    ).broadcastRoom(room.code, 'room_update', {});
    expect(sent).toHaveLength(0);
  });
});

/**
 * Player-draft auto-pick-on-timeout tests (Task 3.1, scenarios 4/8/14) —
 * `_autoPickCurrentPhase` is gateway-level (not game.service.ts), called by
 * the per-turn timer (`_scheduleTurnTimer`) when a picker doesn't act in
 * time. Read it in full before writing these: for the 'selecting_position'
 * phase specifically, it doesn't just pick a slot — it cascades through
 * pickSlot → pickCard → (multi-player) orderHiddenDeck in one timer firing,
 * landing the turn all the way at 'hidden_pick' for the NEXT player. That
 * cascade is asserted explicitly below, not assumed to stop at "a slot got
 * picked."
 */
describe('RoomsGateway — player-draft auto-pick on timeout (Task 3.1)', () => {
  let roomsService: RoomsService;
  let gameService: GameService;
  let gateway: RoomsGateway;
  const SESSION_ID = 'sess-draft-timeout';

  function emptyPitch(playerId: string) {
    const slots = [
      { index: 0, label: 'GK', basePositionType: 'GK', card: null },
      { index: 1, label: 'LB', basePositionType: 'LB', card: null },
    ];
    return { playerId, slots, filledCount: 0 };
  }

  function draftSession(
    roomCode: string,
    overrides: Partial<GameSession> = {},
  ): GameSession {
    return {
      sessionId: SESSION_ID,
      roomCode,
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
      currentRoundSlotIndex: null,
      draftedCardIds: new Set(),
      roundCandidates: [],
      orderedHiddenDeck: [],
      hiddenPicksTaken: new Set(),
      hiddenPicksMap: new Map(),
      hiddenPickReveal: null,
      lastRoundLeftovers: [],
      turn: {
        turnId: 't1',
        phase: 'selecting_position',
        activePlayerId: 'p1',
        activeSlotIndex: null,
        candidates: [],
        turnStartedAt: null,
      },
      turnTimeoutPolicy: {
        enabled: true,
        turnSeconds: 30,
        onExpiry: 'auto_pick_random',
      },
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

  function setUpRoomAndSession(overrides: Partial<GameSession> = {}) {
    const { room } = roomsService.createRoom('Alice', 'sock-p1');
    roomsService.joinRoom(room.code, 'Bob', 'sock-p2');
    const session = draftSession(room.code, overrides);
    (
      gameService as unknown as { sessions: Map<string, GameSession> }
    ).sessions.set(session.sessionId, session);
    (
      gameService as unknown as { roomToSession: Map<string, string> }
    ).roomToSession.set(room.code, session.sessionId);
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

  it('scenario 4: auto-pick on timeout during selecting_position fills a slot and cascades the turn to the next player (hidden_pick)', () => {
    const { room, session } = setUpRoomAndSession();

    (
      gateway as unknown as {
        _scheduleTurnTimer(s: GameSession, rc: string): void;
      }
    )._scheduleTurnTimer(session, room.code);
    jest.advanceTimersByTime(30_000);

    // p1's pitch got a card from the auto-cascade (pickSlot + pickCard).
    expect(session.pitches.p1.slots.some((s) => s.card !== null)).toBe(true);
    // Multi-player cascade lands at hidden_pick for p2 (the next player),
    // not stuck at selecting_position or selecting_card.
    expect(session.turn.phase).toBe('hidden_pick');
    expect(session.turn.activePlayerId).toBe('p2');
  });

  it('scenario 8: auto-pick on timeout during selecting_card picks the first offered candidate and advances', () => {
    const offeredCard = {
      cardId: 'offer-1',
      playerName: 'X',
      basePositionType: 'GK',
      rating: 70,
      pace: 70,
      shooting: 70,
      passing: 70,
      dribbling: 70,
      defending: 70,
      physical: 70,
      nationality: 'England',
      club: 'Test FC',
      altPositions: [],
      naturalPositions: ['GK'],
      chemistryBonuses: [],
    };
    const { room, session } = setUpRoomAndSession({
      currentRoundSlotIndex: 0,
      roundCandidates: [offeredCard] as any,
      turn: {
        turnId: 't1',
        phase: 'selecting_card',
        activePlayerId: 'p1',
        activeSlotIndex: 0,
        candidates: [offeredCard] as any,
        turnStartedAt: null,
      },
    });

    (
      gateway as unknown as {
        _scheduleTurnTimer(s: GameSession, rc: string): void;
      }
    )._scheduleTurnTimer(session, room.code);
    jest.advanceTimersByTime(30_000);

    expect(session.pitches.p1.slots[0].card?.cardId).toBe('offer-1');
    // Same cascade as scenario 4 once the card is picked — lands at hidden_pick.
    expect(session.turn.phase).toBe('hidden_pick');
    expect(session.turn.activePlayerId).toBe('p2');
  });

  it('scenario 14: a player who disconnects mid-turn still gets auto-picked for when the (already-armed) timer fires — the room survives because the OTHER player is still connected', () => {
    const { room, session } = setUpRoomAndSession();

    (
      gateway as unknown as {
        _scheduleTurnTimer(s: GameSession, rc: string): void;
      }
    )._scheduleTurnTimer(session, room.code);

    // p1 (the active picker) disconnects — a TEMPORARY disconnect during an
    // active game (handleDisconnect's hasActiveSession branch), not a
    // permanent removal. The room survives since p2 is still connected, and
    // nothing here touches the already-armed turn timer.
    gateway.handleDisconnect({ id: 'sock-p1' } as never);
    expect(roomsService.getRoom(room.code)).toBeDefined();

    jest.advanceTimersByTime(30_000);

    // The timer fired exactly as if p1 had simply been slow, not connected
    // vs. not — auto-pick doesn't distinguish the reason.
    expect(session.pitches.p1.slots.some((s) => s.card !== null)).toBe(true);
    expect(session.turn.activePlayerId).toBe('p2');
  });
});

/**
 * Tournament mode (Phase 1) gateway coverage:
 *  - `_clearAllTimersForSession` must sweep all 4 new tournament timer Maps
 *    (the Phase 0 orphaned-timer bug, reproduced for tournament sessions if any
 *    were missed).
 *  - `buildTournamentStatePayload` must never leak the server-only
 *    `simulationEvents` / `nextEventIndex` fields into a client snapshot.
 */
describe('RoomsGateway — tournament timer cleanup (Phase 1, Task 8)', () => {
  let gateway: RoomsGateway;

  beforeEach(() => {
    // Construct BEFORE enabling fake timers so the gateway's background
    // cleanup/heartbeat intervals are real handles, and therefore not counted
    // by jest.getTimerCount() — leaving only the fake timers we arm below.
    gateway = new RoomsGateway(new RoomsService(), new GameService());
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.useRealTimers();
    gateway.onModuleDestroy();
  });

  it('clears all 4 tournament timers + the turn timer, leaving zero fake handles', () => {
    const g = gateway as unknown as {
      _tournamentRevealTimers: Map<string, ReturnType<typeof setTimeout>>;
      _tournamentReadyTimers: Map<string, ReturnType<typeof setTimeout>>;
      _tournamentSimTimers: Map<string, ReturnType<typeof setInterval>>;
      _tournamentResultTimers: Map<string, ReturnType<typeof setTimeout>>;
      _turnTimers: Map<string, ReturnType<typeof setTimeout>>;
      _clearAllTimersForSession(roomCode: string, sessionId?: string): void;
    };
    g._tournamentRevealTimers.set(
      'ROOM',
      setTimeout(() => {}, 10_000),
    );
    g._tournamentReadyTimers.set(
      'ROOM',
      setTimeout(() => {}, 10_000),
    );
    g._tournamentSimTimers.set(
      'ROOM',
      setInterval(() => {}, 400),
    );
    g._tournamentResultTimers.set(
      'ROOM',
      setTimeout(() => {}, 10_000),
    );
    g._turnTimers.set(
      'SESS',
      setTimeout(() => {}, 10_000),
    );

    expect(jest.getTimerCount()).toBe(5);

    g._clearAllTimersForSession('ROOM', 'SESS');

    expect(jest.getTimerCount()).toBe(0);
    expect(g._tournamentRevealTimers.size).toBe(0);
    expect(g._tournamentReadyTimers.size).toBe(0);
    expect(g._tournamentSimTimers.size).toBe(0);
    expect(g._tournamentResultTimers.size).toBe(0);
  });
});

describe('RoomsGateway — tournament_state payload safety (Phase 1, Task 9 / Acceptance #7)', () => {
  let gateway: RoomsGateway;

  beforeEach(() => {
    gateway = new RoomsGateway(new RoomsService(), new GameService());
  });
  afterEach(() => {
    gateway.onModuleDestroy();
  });

  it('omits server-only simulationEvents / nextEventIndex from every match in the payload', () => {
    // A tournament state whose match carries the server-only fields populated.
    const tournament = {
      phase: 'simulating',
      currentRound: 1,
      totalRounds: 2,
      readyPlayerIds: ['p1'],
      readyDeadlineAt: null,
      bracketRevealAt: 0,
      awards: null,
      bracket: {
        size: 4,
        rounds: [
          {
            roundNumber: 1,
            label: 'Semi-finals',
            status: 'in_progress',
            matches: [
              {
                matchId: 'r1_m1',
                roundNumber: 1,
                participantA: {
                  kind: 'real',
                  participantId: 'p1',
                  displayName: 'P1',
                  lineup: { overallRating: 88 },
                },
                participantB: {
                  kind: 'real',
                  participantId: 'p2',
                  displayName: 'P2',
                  lineup: { overallRating: 86 },
                },
                status: 'simulating',
                simulationEvents: [
                  {
                    minute: 45,
                    type: 'goal',
                    teamParticipantId: 'p1',
                    playerName: 'X',
                    playerRating: 88,
                  },
                ],
                nextEventIndex: 0,
                result: null,
                winnerId: null,
              },
            ],
          },
        ],
      },
    } as any;

    const payload = (
      gateway as unknown as {
        buildTournamentStatePayload(t: unknown): unknown;
      }
    ).buildTournamentStatePayload(tournament);

    const serialized = JSON.stringify(payload);
    expect(serialized).not.toContain('simulationEvents');
    expect(serialized).not.toContain('nextEventIndex');

    const typed = payload as {
      bracket: { rounds: { matches: Record<string, unknown>[] }[] };
    };
    for (const round of typed.bracket.rounds) {
      for (const m of round.matches) {
        expect(m).not.toHaveProperty('simulationEvents');
        expect(m).not.toHaveProperty('nextEventIndex');
      }
    }
  });
});

/**
 * _tryEndGame's tournament-mode skip (Phase 7 audit). Before this fix,
 * _tryEndGame unconditionally ended the WHOLE session (declareForfeitWin,
 * or 'abandoned' if literally empty) the moment the ROOM dropped below
 * MIN_ACTIVE_PLAYERS (2), regardless of session.status. That's correct for
 * every pre-tournament phase (the core match genuinely needs 2 real
 * players), but once a tournament actually begins the bracket
 * (session.tournament) is a self-sufficient, frozen structure — AI fills
 * every slot a real player doesn't occupy, and every match is pre-computed
 * server-side — so a single remaining real participant can keep going
 * through their matches alone. The old behavior prematurely declared a
 * "forfeit win" (a concept from the pre-tournament single-match flow) the
 * instant a room dropped to 1 player, discarding the entire multi-round
 * bracket. A genuinely EMPTY room (0 players) still needs the usual
 * cleanup — nobody's left to watch a tournament either way.
 */
describe('RoomsGateway — _tryEndGame tournament-mode skip (Phase 7)', () => {
  let roomsService: RoomsService;
  let gameService: GameService;
  let gateway: RoomsGateway;
  const ROOM_CODE = 'TRNMT2';
  const SESSION_ID = 'sess-tourney-2';

  function tournamentSession(
    overrides: Partial<GameSession> = {},
  ): GameSession {
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
      pitches: {
        p1: { playerId: 'p1', slots: [], filledCount: 0 },
        p2: { playerId: 'p2', slots: [], filledCount: 0 },
      },
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
      turn: {
        turnId: 't1',
        phase: 'selecting_position',
        activePlayerId: 'p1',
        activeSlotIndex: null,
        candidates: [],
        turnStartedAt: null,
      },
      turnTimeoutPolicy: { enabled: false, turnSeconds: null, onExpiry: null },
      status: 'tournament',
      abilityDraft: null,
      playerAbilities: {},
      abilityActivations: [],
      subSwappedCardIds: new Set(),
      isFinished: false,
      subsPhase: null,
      subsTimerSeconds: null,
      subsDeadlineAt: null,
      abilityActivationDeadlineAt: null,
      tournamentEnabled: true,
      tournament: {
        // bracket_reveal, not ready_check — this describe block is testing
        // _tryEndGame's status-level skip, not the ready-check auto-ready
        // path (already covered in game.service.tournament.spec.ts), so an
        // empty rounds array (never read by this phase) keeps the fixture
        // minimal.
        phase: 'bracket_reveal',
        bracket: { size: 4, rounds: [] } as any,
        currentRound: 1,
        totalRounds: 2,
        readyPlayerIds: [],
        readyDeadlineAt: null,
        bracketRevealAt: 0,
        awards: null,
      },
      result: null,
      ...overrides,
    } as GameSession;
  }

  function inject(session: GameSession): void {
    (
      gameService as unknown as { sessions: Map<string, GameSession> }
    ).sessions.set(session.sessionId, session);
    (
      gameService as unknown as { roomToSession: Map<string, string> }
    ).roomToSession.set(session.roomCode, session.sessionId);
  }

  function setupRoom(): void {
    roomsService.createRoom('Alice', 'sock-p1');
    const rooms = (roomsService as unknown as { rooms: Map<string, any> })
      .rooms;
    const [code, room] = [...rooms.entries()][0];
    rooms.delete(code);
    room.code = ROOM_CODE;
    room.players = [
      {
        id: 'p1',
        displayName: 'Alice',
        isHost: true,
        isConnected: true,
        socketId: 'sock-p1',
      },
      {
        id: 'p2',
        displayName: 'Bob',
        isHost: false,
        isConnected: true,
        socketId: 'sock-p2',
      },
    ];
    rooms.set(ROOM_CODE, room);
    const socketIndex = (
      roomsService as unknown as {
        socketIndex: Map<string, { roomCode: string; playerId: string }>;
      }
    ).socketIndex;
    socketIndex.set('sock-p1', { roomCode: ROOM_CODE, playerId: 'p1' });
    socketIndex.set('sock-p2', { roomCode: ROOM_CODE, playerId: 'p2' });
  }

  beforeEach(() => {
    roomsService = new RoomsService();
    gameService = new GameService();
    gateway = new RoomsGateway(roomsService, gameService);
    setupRoom();
  });

  afterEach(() => {
    gateway.onModuleDestroy();
  });

  it('kicking a room from 2 players down to 1 during an active tournament does NOT end the session — the lone remaining player keeps their bracket', () => {
    inject(tournamentSession());

    (
      gateway as unknown as {
        handleKickPlayer(
          dto: { targetPlayerId: string },
          client: { id: string },
        ): void;
      }
    ).handleKickPlayer({ targetPlayerId: 'p2' }, { id: 'sock-p1' });

    const session = gameService.getSessionByRoomCode(ROOM_CODE);
    expect(session).toBeDefined(); // NOT torn down
    expect(session!.status).toBe('tournament'); // NOT forced to 'finished'
    expect(session!.result).toBeNull(); // no forfeit-win declared
    expect(roomsService.getRoom(ROOM_CODE)).toBeDefined(); // room NOT closed
  });

  it('the same drop-to-1-player DOES still end the session for a NON-tournament phase (regression check — nothing broke the existing behavior)', () => {
    inject(tournamentSession({ status: 'lineup_edit', subsPhase: { userSubs: {} } }));

    (
      gateway as unknown as {
        handleKickPlayer(
          dto: { targetPlayerId: string },
          client: { id: string },
        ): void;
      }
    ).handleKickPlayer({ targetPlayerId: 'p2' }, { id: 'sock-p1' });

    expect(gameService.getSessionByRoomCode(ROOM_CODE)).toBeUndefined(); // torn down
    expect(roomsService.getRoom(ROOM_CODE)).toBeUndefined(); // room closed
  });
});

describe('RoomsGateway — simulationSpeedIntervalMs (host pacing setting)', () => {
  let gateway: RoomsGateway;

  afterEach(() => {
    gateway.onModuleDestroy();
  });

  it('maps each speed to its event-delivery interval, defaulting unknown/missing to normal', () => {
    const roomsService = new RoomsService();
    const gameService = new GameService();
    gateway = new RoomsGateway(roomsService, gameService);
    const intervalFor = (speed: 'fast' | 'normal' | 'slow') =>
      (
        gateway as unknown as {
          simulationSpeedIntervalMs: (s: string) => number;
        }
      ).simulationSpeedIntervalMs(speed);

    const fast = intervalFor('fast');
    const normal = intervalFor('normal');
    const slow = intervalFor('slow');

    // Ordering must hold — "fast" strictly quicker than "normal", "slow"
    // strictly slower — otherwise the setting would do nothing meaningful.
    expect(fast).toBeLessThan(normal);
    expect(normal).toBeLessThan(slow);
    // "normal" preserves the pre-existing hardcoded pacing (1500ms) as the
    // default, so rooms that never touch this setting behave exactly as
    // before.
    expect(normal).toBe(1500);
  });
});

/**
 * Spectator gateway coverage (multiplayer-rooms step 2 — see
 * MULTIPLAYER_ROOMS_DESIGN.md, section B). Exercises the real handlers end
 * to end: spectate_room / stop_spectating / spectator_reconnect, plus the
 * disconnect path now branching to spectators when a socket isn't a player.
 */
describe('RoomsGateway — spectators (multiplayer-rooms step 2)', () => {
  let roomsService: RoomsService;
  let gameService: GameService;
  let gateway: RoomsGateway;

  function makeClient(id: string, readyState = 1 /* OPEN */) {
    const sent: { event: string; data: unknown }[] = [];
    const client = {
      id,
      readyState,
      send: (raw: string) => sent.push(JSON.parse(raw)),
      close: jest.fn(),
    };
    return { client, sent };
  }

  function connect(client: { id: string }): void {
    (
      gateway as unknown as { _connectedSockets: Map<string, unknown> }
    )._connectedSockets.set(client.id, client);
  }

  beforeEach(() => {
    roomsService = new RoomsService();
    gameService = new GameService();
    gateway = new RoomsGateway(roomsService, gameService);
  });

  afterEach(() => {
    gateway.onModuleDestroy();
  });

  it('spectate_room joins as a spectator and replies with a room_update including a reconnectToken', () => {
    const { room } = roomsService.createRoom('Host', 'sock-host');
    const { client: spec, sent: specSent } = makeClient('sock-spec');
    connect(spec);

    gateway.handleSpectateRoom(
      { roomCode: room.code, displayName: 'Watcher' } as never,
      spec as never,
    );

    // Two room_update sends land on the spectator's own socket here — the
    // direct ack (with the reconnectToken) plus the generic room broadcast,
    // which now includes their own freshly-added socket. This mirrors the
    // exact same pre-existing double-send join_room already does for a
    // newly-joined player (its own ack, then the room-wide broadcast) — not
    // a new bug introduced by spectators.
    expect(specSent.length).toBeGreaterThanOrEqual(1);
    expect(specSent[0].event).toBe('room_update');
    const data = specSent[0].data as {
      spectators: { displayName: string }[];
      reconnectToken: string;
    };
    expect(data.spectators).toEqual([
      { id: expect.any(String), displayName: 'Watcher', isConnected: true },
    ]);
    expect(typeof data.reconnectToken).toBe('string');
  });

  it('spectate_room also broadcasts an updated room_update to already-connected players', () => {
    const { room } = roomsService.createRoom('Host', 'sock-host');
    const { client: hostClient, sent: hostSent } = makeClient('sock-host');
    connect(hostClient);
    const { client: spec } = makeClient('sock-spec');
    connect(spec);

    gateway.handleSpectateRoom(
      { roomCode: room.code, displayName: 'Watcher' } as never,
      spec as never,
    );

    expect(hostSent.some((m) => m.event === 'room_update')).toBe(true);
  });

  it('a spectator does not appear in room.players and cannot be found via getSocketEntry (structural guard every gameplay handler relies on)', () => {
    const { room } = roomsService.createRoom('Host', 'sock-host');
    const { client: spec } = makeClient('sock-spec');
    connect(spec);

    gateway.handleSpectateRoom(
      { roomCode: room.code, displayName: 'Watcher' } as never,
      spec as never,
    );

    const updatedRoom = roomsService.getRoom(room.code)!;
    expect(updatedRoom.players).toHaveLength(1); // host only
    expect(roomsService.getSocketEntry('sock-spec')).toBeUndefined();
  });

  it('a gameplay action from a spectator socket is rejected with NOT_IN_ROOM, exactly like any other unrecognized socket', () => {
    const { room } = roomsService.createRoom('Host', 'sock-host');
    const { client: spec, sent: specSent } = makeClient('sock-spec');
    connect(spec);
    gateway.handleSpectateRoom(
      { roomCode: room.code, displayName: 'Watcher' } as never,
      spec as never,
    );
    specSent.length = 0; // clear the room_update from joining

    gateway.handleStartGame(spec as never);

    expect(specSent).toEqual([
      { event: 'error', data: { code: 'NOT_IN_ROOM' } },
    ]);
  });

  it('stop_spectating removes the spectator and broadcasts the updated room_update', () => {
    const { room } = roomsService.createRoom('Host', 'sock-host');
    const { client: hostClient, sent: hostSent } = makeClient('sock-host');
    connect(hostClient);
    const { client: spec } = makeClient('sock-spec');
    connect(spec);
    gateway.handleSpectateRoom(
      { roomCode: room.code, displayName: 'Watcher' } as never,
      spec as never,
    );
    hostSent.length = 0;

    gateway.handleStopSpectating(spec as never);

    expect(roomsService.getRoom(room.code)!.spectators).toHaveLength(0);
    expect(hostSent).toHaveLength(1);
    expect(hostSent[0].event).toBe('room_update');
  });

  it('handleDisconnect routes a spectator socket to the spectator path (not the player path) and broadcasts the updated room state', () => {
    const { room } = roomsService.createRoom('Host', 'sock-host');
    const { client: hostClient, sent: hostSent } = makeClient('sock-host');
    connect(hostClient);
    const { client: spec } = makeClient('sock-spec');
    connect(spec);
    gateway.handleSpectateRoom(
      { roomCode: room.code, displayName: 'Watcher' } as never,
      spec as never,
    );
    hostSent.length = 0;

    gateway.handleDisconnect(spec as never);

    // Room and host player are completely unaffected — only the spectator's
    // own connection state changed.
    const updatedRoom = roomsService.getRoom(room.code)!;
    expect(updatedRoom.players).toHaveLength(1);
    expect(updatedRoom.spectators[0].isConnected).toBe(false);
    expect(hostSent.some((m) => m.event === 'room_update')).toBe(true);
  });

  it('spectator_reconnect verifies the token and restores the spectator on a new socket', () => {
    const { room } = roomsService.createRoom('Host', 'sock-host');
    const { client: spec, sent: specSent } = makeClient('sock-spec');
    connect(spec);
    gateway.handleSpectateRoom(
      { roomCode: room.code, displayName: 'Watcher' } as never,
      spec as never,
    );
    const { reconnectToken, localSpectatorId: spectatorId } = specSent[0]
      .data as {
      reconnectToken: string;
      localSpectatorId: string;
    };

    gateway.handleDisconnect(spec as never);

    const { client: newSpecSocket, sent: newSent } =
      makeClient('sock-spec-new');
    connect(newSpecSocket);
    gateway.handleSpectatorReconnect(
      { roomCode: room.code, spectatorId, reconnectToken } as never,
      newSpecSocket as never,
    );

    expect(newSent[0].event).toBe('room_update');
    const updatedRoom = roomsService.getRoom(room.code)!;
    expect(updatedRoom.spectators[0].isConnected).toBe(true);
    expect(updatedRoom.spectators[0].socketId).toBe('sock-spec-new');
  });

  it('spectator_reconnect with an invalid token is rejected with INVALID_TOKEN', () => {
    const { room } = roomsService.createRoom('Host', 'sock-host');
    const { client: spec, sent: specSent } = makeClient('sock-spec');
    connect(spec);
    gateway.handleSpectateRoom(
      { roomCode: room.code, displayName: 'Watcher' } as never,
      spec as never,
    );
    const { localSpectatorId: spectatorId } = specSent[0].data as {
      localSpectatorId: string;
    };

    const { client: newSpecSocket, sent: newSent } =
      makeClient('sock-spec-new');
    connect(newSpecSocket);
    gateway.handleSpectatorReconnect(
      {
        roomCode: room.code,
        spectatorId,
        reconnectToken: 'forged-token',
      } as never,
      newSpecSocket as never,
    );

    expect(newSent).toEqual([
      { event: 'error', data: { code: 'INVALID_TOKEN' } },
    ]);
  });

  it('spectator_reconnect for a room that no longer exists is normalized to NOT_FOUND (not the internal ROOM_NOT_FOUND reason)', () => {
    // A validly-signed token for a room/spectator pair that was never
    // created — same shape as a token surviving a server restart or the
    // room having since closed. reconnectSpectator's own internal reason
    // string (ROOM_NOT_FOUND) must never leak to the client: RoomNotifier
    // only recognizes 'NOT_FOUND'/'INVALID_TOKEN' as "clear the stale
    // spectator seat" signals, and forwarding a differently-named code
    // silently strands that seat cached forever with no cleanup.
    const token = generateReconnectToken('ghost-spectator', 'GHOSTRM');
    const { client: spec, sent } = makeClient('sock-spec');
    connect(spec);

    gateway.handleSpectatorReconnect(
      {
        roomCode: 'GHOSTRM',
        spectatorId: 'ghost-spectator',
        reconnectToken: token,
      } as never,
      spec as never,
    );

    expect(sent).toEqual([{ event: 'error', data: { code: 'NOT_FOUND' } }]);
  });

  it('spectator_reconnect for a spectator id no longer in an existing room is normalized to NOT_FOUND', () => {
    const { room } = roomsService.createRoom('Host', 'sock-host');
    const token = generateReconnectToken('ghost-spectator', room.code);
    const { client: spec, sent } = makeClient('sock-spec');
    connect(spec);

    gateway.handleSpectatorReconnect(
      {
        roomCode: room.code,
        spectatorId: 'ghost-spectator',
        reconnectToken: token,
      } as never,
      spec as never,
    );

    expect(sent).toEqual([{ event: 'error', data: { code: 'NOT_FOUND' } }]);
  });
});

/**
 * Track B B4 — bench_selection / lineup_edit shared deadline timer:
 * arms for bench_selection, fires forceFinalizeBenchSelection, and re-arms
 * with a fresh deadline when the session later enters lineup_edit.
 */
describe('RoomsGateway — subs deadline timer across Track B phases (B4)', () => {
  let roomsService: RoomsService;
  let gameService: GameService;
  let gateway: RoomsGateway;
  const ROOM_CODE = 'B4TIME';
  const SESSION_ID = 'sess-b4-timer';

  beforeEach(() => {
    jest.useFakeTimers({ doNotFake: ['nextTick'] });
    roomsService = new RoomsService();
    gameService = new GameService();
    gateway = new RoomsGateway(roomsService, gameService);
  });
  afterEach(() => {
    gateway.onModuleDestroy();
    jest.useRealTimers();
    jest.restoreAllMocks();
  });

  function injectBenchSession(overrides: Partial<GameSession> = {}): GameSession {
    const t0 = Date.now();
    const session = {
      sessionId: SESSION_ID,
      roomCode: ROOM_CODE,
      createdAt: t0,
      leagues: [],
      playerBonusCache: new Map(),
      userChallengeCache: new Map(),
      formation: { name: '4-3-3', slots: [] },
      players: [
        { id: 'p1', displayName: 'A', isHost: true, isConnected: true },
        { id: 'p2', displayName: 'B', isHost: false, isConnected: true },
      ],
      pitches: { p1: { playerId: 'p1', slots: [], filledCount: 0 }, p2: { playerId: 'p2', slots: [], filledCount: 0 } },
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
      turn: {
        turnId: 't1',
        phase: 'selecting_position',
        activePlayerId: 'p1',
        activeSlotIndex: null,
        candidates: [],
        turnStartedAt: null,
      },
      turnTimeoutPolicy: { enabled: false, turnSeconds: null, onExpiry: null },
      status: 'bench_selection',
      abilityDraft: null,
      playerAbilities: {},
      abilityActivations: [],
      abilityActivationRevealed: false,
      subSwappedCardIds: new Set(),
      coachedPositions: {},
      isFinished: false,
      subsPhase: {
        userSubs: {
          p1: { isComplete: false, lineupConfirmed: false },
          p2: { isComplete: false, lineupConfirmed: false },
        },
      },
      subsTimerSeconds: 5,
      subsDeadlineAt: t0 + 5_000,
      abilityTimerSeconds: null,
      abilityActivationDeadlineAt: null,
      tournamentEnabled: false,
      tournament: null,
      result: null,
      ...overrides,
    } as GameSession;
    (gameService as unknown as { sessions: Map<string, GameSession> }).sessions.set(
      SESSION_ID,
      session,
    );
    (gameService as unknown as { roomToSession: Map<string, string> }).roomToSession.set(
      ROOM_CODE,
      SESSION_ID,
    );
    roomsService.createRoom('A', 'sock-p1');
    // Force the created room code to match — simpler: just stub getSocketIds.
    jest.spyOn(roomsService, 'getSocketIds').mockReturnValue(['sock-p1', 'sock-p2']);
    jest.spyOn(roomsService, 'getSocketEntry').mockImplementation((id: string) => {
      if (id === 'sock-p1') return { roomCode: ROOM_CODE, playerId: 'p1' };
      if (id === 'sock-p2') return { roomCode: ROOM_CODE, playerId: 'p2' };
      return undefined;
    });
    return session;
  }

  it('bench_selection deadline fires forceFinalizeBenchSelection and advances the session', () => {
    const session = injectBenchSession();
    (
      gateway as unknown as {
        _maybeArmSubsTimer(s: GameSession, rc: string): void;
      }
    )._maybeArmSubsTimer(session, ROOM_CODE);

    const timers = (
      gateway as unknown as {
        _subsTimers: Map<string, { deadlineAt: number }>;
      }
    )._subsTimers;
    expect(timers.has(SESSION_ID)).toBe(true);
    expect(timers.get(SESSION_ID)!.deadlineAt).toBe(session.subsDeadlineAt);

    jest.advanceTimersByTime(5_001);

    const after = gameService.getSessionByRoomCode(ROOM_CODE)!;
    expect(after.status).toBe('lineup_edit'); // no pending abilities → skip activation
    expect(after.subsPhase!.userSubs.p1.isComplete).toBe(true);
    // Fresh lineup_edit deadline re-armed (different from the bench window).
    expect(after.subsDeadlineAt).not.toBeNull();
  });

  it('re-arms when subsDeadlineAt changes (bench → lineup_edit)', () => {
    const session = injectBenchSession({
      playerAbilities: {
        p1: { type: 'captain', status: 'pending' },
        p2: { type: 'yellow', status: 'pending' },
      },
      abilityTimerSeconds: 30,
    });
    const arm = (
      gateway as unknown as {
        _maybeArmSubsTimer(s: GameSession, rc: string): void;
      }
    )._maybeArmSubsTimer.bind(gateway);
    const timers = (
      gateway as unknown as {
        _subsTimers: Map<string, { deadlineAt: number }>;
      }
    )._subsTimers;

    arm(session, ROOM_CODE);
    const benchDeadline = session.subsDeadlineAt!;
    expect(timers.get(SESSION_ID)!.deadlineAt).toBe(benchDeadline);

    // Manually advance phases the way forceFinalize + finishAbility would.
    gameService.forceFinalizeBenchSelection(ROOM_CODE);
    expect(session.status).toBe('ability_activation');
    arm(session, ROOM_CODE); // should clear the bench timer (status not bench/lineup with deadline)
    expect(timers.has(SESSION_ID)).toBe(false);

    // Advance clock so lineup_edit gets a distinct absolute deadline.
    jest.advanceTimersByTime(1_000);

    for (const id of ['p1', 'p2']) gameService.discardAbility(ROOM_CODE, id);
    gameService.revealAbilityActivations(ROOM_CODE);
    gameService.finishAbilityActivation(ROOM_CODE);
    expect(session.status).toBe('lineup_edit');
    const lineupDeadline = session.subsDeadlineAt!;
    expect(lineupDeadline).not.toBe(benchDeadline);

    arm(session, ROOM_CODE);
    expect(timers.get(SESSION_ID)!.deadlineAt).toBe(lineupDeadline);
  });
});

/**
 * Track B B5 — lineup_edit timeout tournament fork + ability-activation
 * deadline wiring through the gateway (service-level forks are covered in
 * game.service.subs.spec.ts).
 */
describe('RoomsGateway — lineup_edit timeout + ability deadline (Track B B5)', () => {
  let roomsService: RoomsService;
  let gameService: GameService;
  let gateway: RoomsGateway;
  const ROOM_CODE = 'B5TIME';
  const SESSION_ID = 'sess-b5-timer';

  beforeEach(() => {
    jest.useFakeTimers({ doNotFake: ['nextTick'] });
    roomsService = new RoomsService();
    gameService = new GameService();
    gateway = new RoomsGateway(roomsService, gameService);
  });
  afterEach(() => {
    gateway.onModuleDestroy();
    jest.useRealTimers();
    jest.restoreAllMocks();
  });

  function injectSession(overrides: Partial<GameSession> = {}): GameSession {
    const t0 = Date.now();
    const session = {
      sessionId: SESSION_ID,
      roomCode: ROOM_CODE,
      createdAt: t0,
      leagues: [],
      playerBonusCache: new Map(),
      userChallengeCache: new Map(),
      formation: { name: '4-3-3', slots: [] },
      players: [
        { id: 'p1', displayName: 'A', isHost: true, isConnected: true },
        { id: 'p2', displayName: 'B', isHost: false, isConnected: true },
      ],
      pitches: {
        p1: { playerId: 'p1', slots: [], filledCount: 0 },
        p2: { playerId: 'p2', slots: [], filledCount: 0 },
      },
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
      turn: {
        turnId: 't1',
        phase: 'selecting_position',
        activePlayerId: 'p1',
        activeSlotIndex: null,
        candidates: [],
        turnStartedAt: null,
      },
      turnTimeoutPolicy: { enabled: false, turnSeconds: null, onExpiry: null },
      status: 'lineup_edit',
      abilityDraft: null,
      playerAbilities: {},
      abilityActivations: [],
      abilityActivationRevealed: false,
      subSwappedCardIds: new Set(),
      coachedPositions: {},
      isFinished: false,
      subsPhase: {
        userSubs: {
          p1: { isComplete: true, lineupConfirmed: false },
          p2: { isComplete: true, lineupConfirmed: false },
        },
      },
      subsTimerSeconds: 5,
      subsDeadlineAt: t0 + 5_000,
      abilityTimerSeconds: null,
      abilityActivationDeadlineAt: null,
      tournamentEnabled: false,
      tournament: null,
      result: null,
      ...overrides,
    } as GameSession;
    (gameService as unknown as { sessions: Map<string, GameSession> }).sessions.set(
      SESSION_ID,
      session,
    );
    (gameService as unknown as { roomToSession: Map<string, string> }).roomToSession.set(
      ROOM_CODE,
      SESSION_ID,
    );
    jest.spyOn(roomsService, 'getSocketIds').mockReturnValue(['sock-p1', 'sock-p2']);
    jest.spyOn(roomsService, 'getSocketEntry').mockImplementation((id: string) => {
      if (id === 'sock-p1') return { roomCode: ROOM_CODE, playerId: 'p1' };
      if (id === 'sock-p2') return { roomCode: ROOM_CODE, playerId: 'p2' };
      return undefined;
    });
    return session;
  }

  it('lineup_edit deadline fires forceFinalizeLineupEdit and starts tournament bracket (B5)', () => {
    const session = injectSession({ tournamentEnabled: true });
    const beginSpy = jest
      .spyOn(
        gateway as unknown as { beginBracketReveal(rc: string): void },
        'beginBracketReveal',
      )
      .mockImplementation(() => undefined);

    (
      gateway as unknown as {
        _maybeArmSubsTimer(s: GameSession, rc: string): void;
      }
    )._maybeArmSubsTimer(session, ROOM_CODE);

    jest.advanceTimersByTime(5_001);

    expect(session.subsPhase!.userSubs.p1.lineupConfirmed).toBe(true);
    expect(session.subsPhase!.userSubs.p2.lineupConfirmed).toBe(true);
    expect(session.status).toBe('lineup_edit'); // stays until beginTournament
    expect(session.isFinished).toBe(false);
    expect(beginSpy).toHaveBeenCalledWith(ROOM_CODE);
  });

  it('lineup_edit deadline without tournament finalizes the game safely', () => {
    const session = injectSession({ tournamentEnabled: false });
    (
      gateway as unknown as {
        _maybeArmSubsTimer(s: GameSession, rc: string): void;
      }
    )._maybeArmSubsTimer(session, ROOM_CODE);

    jest.advanceTimersByTime(5_001);

    const after = gameService.getSessionByRoomCode(ROOM_CODE)!;
    expect(after.status).toBe('finished');
    expect(after.result).not.toBeNull();
  });

  it('ability_activation deadline force-finalizes and re-arms lineup_edit subs timer', () => {
    const t0 = Date.now();
    const session = injectSession({
      status: 'ability_activation',
      playerAbilities: {
        p1: { type: 'captain', status: 'pending' },
        p2: { type: 'yellow', status: 'pending' },
      },
      abilityTimerSeconds: 5,
      abilityActivationDeadlineAt: t0 + 5_000,
      subsTimerSeconds: 10,
      subsDeadlineAt: null, // cleared while in ability_activation
      subsPhase: {
        userSubs: {
          p1: { isComplete: true, lineupConfirmed: false },
          p2: { isComplete: true, lineupConfirmed: false },
        },
      },
    });

    (
      gateway as unknown as {
        _maybeArmAbilityActivationTimer(s: GameSession, rc: string): void;
      }
    )._maybeArmAbilityActivationTimer(session, ROOM_CODE);

    const abilityTimers = (
      gateway as unknown as {
        _abilityActivationTimers: Map<string, ReturnType<typeof setTimeout>>;
      }
    )._abilityActivationTimers;
    expect(abilityTimers.has(SESSION_ID)).toBe(true);

    jest.advanceTimersByTime(5_001);

    const after = gameService.getSessionByRoomCode(ROOM_CODE)!;
    expect(after.status).toBe('lineup_edit');
    expect(after.abilityActivationDeadlineAt).toBeNull();
    expect(after.playerAbilities.p1.status).toBe('discarded');
    expect(after.playerAbilities.p2.status).toBe('discarded');
    expect(after.subsDeadlineAt).not.toBeNull();

    // Broadcast path re-arms the shared subs timer for the fresh lineup_edit window.
    const subsTimers = (
      gateway as unknown as {
        _subsTimers: Map<string, { deadlineAt: number }>;
      }
    )._subsTimers;
    expect(subsTimers.has(SESSION_ID)).toBe(true);
    expect(subsTimers.get(SESSION_ID)!.deadlineAt).toBe(after.subsDeadlineAt);
    expect(abilityTimers.has(SESSION_ID)).toBe(false);
  });
});
