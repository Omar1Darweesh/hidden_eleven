import * as fs from 'fs';
import { GameService } from './game.service';
import { GameSession } from './interfaces/game-session.interface';
import { Room } from '../rooms/interfaces/room.interface';
import { clearAllCache } from './admin-data-cache';
import { MatchHistoryService } from '../match-history/match-history.service';
import { DEFAULT_SCORING_CONFIG_V1 } from './scoring-config';

// Node's built-in `fs` module exposes non-configurable property descriptors
// under this project's ts-jest/ESM-interop setup — `jest.spyOn(fs, 'readFileSync')`
// fails with "Cannot redefine property" rather than installing a spy. Jest
// hoists jest.mock() calls above imports automatically, and mocking the whole
// module (replacing the registry entry, not redefining a property on the
// existing frozen object) sidesteps the issue entirely. readFileSync still
// delegates to the real implementation by default, so every other test in
// this file (and the rest of the suite) behaves exactly as before — this
// only adds the ability to count calls.
jest.mock('fs', () => {
  const actual = jest.requireActual('fs');
  return { ...actual, readFileSync: jest.fn(actual.readFileSync) };
});

/**
 * Regression coverage for the ability-activation hang fix: a phase with
 * pending players must be force-resolvable (auto-discard) rather than able to
 * hang forever, mirroring `forceFinalizeLineupEdit` for the lineup_edit phase.
 *
 * Builds a minimal-but-valid GameSession fixture and injects it directly into
 * the service's internal maps (acceptable here: driving a real game from
 * `createSession` all the way through an 11-round draft just to reach
 * `ability_activation` would make this test slow, flaky, and far removed from
 * the one piece of logic actually under test).
 */
describe('GameService — forceFinalizeAbilityActivation', () => {
  let gameService: GameService;
  const ROOM_CODE = 'TEST01';
  const SESSION_ID = 'sess-1';

  function baseSession(overrides: Partial<GameSession> = {}): GameSession {
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
      pitches: {},
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
      turn: {
        turnId: 't1',
        phase: 'selecting_position',
        activePlayerId: 'p1',
        activeSlotIndex: null,
        candidates: [],
        turnStartedAt: null,
      },
      turnTimeoutPolicy: { enabled: false, turnSeconds: null, onExpiry: null },
      status: 'ability_activation',
      abilityDraft: null,
      playerAbilities: {
        p1: { type: 'captain', status: 'pending' },
        p2: { type: 'yellow', status: 'used' },
      },
      abilityActivations: [],
      subSwappedCardIds: new Set(),
      isFinished: false,
      subsPhase: null,
      subsTimerSeconds: null,
      abilityTimerSeconds: null,
      subsDeadlineAt: null,
      abilityActivationDeadlineAt: Date.now() + 45_000,
      result: null,
      ...overrides,
    } as GameSession;
  }

  beforeEach(() => {
    gameService = new GameService();
  });

  function inject(session: GameSession): void {
    (gameService as unknown as { sessions: Map<string, GameSession> }).sessions.set(
      session.sessionId,
      session,
    );
    (gameService as unknown as { roomToSession: Map<string, string> }).roomToSession.set(
      session.roomCode,
      session.sessionId,
    );
  }

  it('errors if the room has no session', () => {
    const result = gameService.forceFinalizeAbilityActivation('NOPE99');
    expect(result).toEqual({ error: 'SESSION_NOT_FOUND' });
  });

  it('errors if the session is not in ability_activation', () => {
    inject(baseSession({ status: 'lineup_edit' }));
    const result = gameService.forceFinalizeAbilityActivation(ROOM_CODE);
    expect(result).toEqual({ error: 'NOT_ACTIVATION_PHASE' });
  });

  it('auto-discards every still-pending ability and advances to lineup_edit', () => {
    inject(baseSession());

    const result = gameService.forceFinalizeAbilityActivation(ROOM_CODE);
    expect('error' in result).toBe(false);
    if ('error' in result) return;

    // p1 was pending → force-discarded. p2 was already used → left untouched.
    expect(result.session.playerAbilities.p1.status).toBe('discarded');
    expect(result.session.playerAbilities.p2.status).toBe('used');

    // The phase actually ended.
    expect(result.session.status).toBe('lineup_edit');
    expect(result.session.subsPhase).not.toBeNull();
    // The deadline that just fired must be cleared, not left dangling.
    expect(result.session.abilityActivationDeadlineAt).toBeNull();
  });
});

/**
 * Coverage for the host-configurable ability-activation timer
 * (Room.abilityTimerSeconds / GameSession.abilityTimerSeconds), added so a
 * host can pick the ability-usage time from the host-room screen instead of
 * always inheriting the draft turn timer or the fixed 45s safety-net.
 */
describe('GameService — abilityTimerSeconds (host-configurable ability timer)', () => {
  let gameService: GameService;
  const ROOM_CODE = 'ABILRM';
  const SESSION_ID = 'sess-abil';

  function baseSession(overrides: Partial<GameSession> = {}): GameSession {
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
      pitches: {},
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
      // Pre-activation fixture status (Track B): enterActivationPhase overrides.
      status: 'bench_selection',
      abilityDraft: null,
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
      abilityTimerSeconds: null,
      result: null,
      ...overrides,
    } as GameSession;
  }

  beforeEach(() => {
    gameService = new GameService();
  });

  function enterActivationPhase(session: GameSession): GameSession {
    return (gameService as unknown as {
      _enterActivationPhase(s: GameSession): GameSession;
    })._enterActivationPhase(session);
  }

  it('createSession copies Room.abilityTimerSeconds onto the new session', () => {
    const room = {
      code: ROOM_CODE,
      players: [{ id: 'p1', displayName: 'Alice', isHost: true, isConnected: true, socketId: 'sock-1' }],
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
      abilityTimerSeconds: 20,
      formationSlug: null,
      tournamentEnabled: false,
      simulationSpeed: 'normal',
    } as any;

    const session = gameService.createSession(room);

    expect(session.abilityTimerSeconds).toBe(20);
  });

  it('createSession defaults abilityTimerSeconds to null when the host never set one', () => {
    const room = {
      code: ROOM_CODE,
      players: [{ id: 'p1', displayName: 'Alice', isHost: true, isConnected: true, socketId: 'sock-1' }],
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
      abilityTimerSeconds: null,
      formationSlug: null,
      tournamentEnabled: false,
      simulationSpeed: 'normal',
    } as any;

    const session = gameService.createSession(room);

    expect(session.abilityTimerSeconds).toBeNull();
  });

  it('uses the host-configured abilityTimerSeconds over the draft turn timer when both are set', () => {
    const before = Date.now();
    const session = enterActivationPhase(
      baseSession({
        abilityTimerSeconds: 20,
        turnTimeoutPolicy: { enabled: true, turnSeconds: 60, onExpiry: 'auto_pick_random' },
      }),
    );

    expect(session.abilityActivationDeadlineAt).not.toBeNull();
    const deadlineSeconds = (session.abilityActivationDeadlineAt! - before) / 1000;
    expect(deadlineSeconds).toBeGreaterThan(19);
    expect(deadlineSeconds).toBeLessThan(21);
  });

  it('abilityTimerSeconds: null means no limit — no deadline is armed, regardless of the room turn timer', () => {
    const session = enterActivationPhase(
      baseSession({
        abilityTimerSeconds: null,
        turnTimeoutPolicy: { enabled: true, turnSeconds: 60, onExpiry: 'auto_pick_random' },
      }),
    );

    // Same semantics as turnTimerSeconds/subsTimerSeconds: null is a real,
    // host-chosen "no limit", not an alias for the room's turn timer.
    expect(session.abilityActivationDeadlineAt).toBeNull();
  });

  it('abilityTimerSeconds: null means no limit even when no turn timer is configured either', () => {
    const session = enterActivationPhase(
      baseSession({
        abilityTimerSeconds: null,
        turnTimeoutPolicy: { enabled: false, turnSeconds: null, onExpiry: null },
      }),
    );

    expect(session.abilityActivationDeadlineAt).toBeNull();
  });
});

/**
 * Integration coverage for Task 2.2's admin-data caching, exercised through
 * the real public entry point (createSession) rather than calling the
 * private load*() module functions directly (they aren't exported — by
 * design, this cache is meant to be invisible to callers). createSession
 * calls both loadActiveFormations() (formations.json) and
 * loadEnabledAbilityTypes() (abilities.json) on every invocation — exactly
 * the "every game start re-reads from disk" cost this task closes.
 */
describe('GameService — admin-data caching (Task 2.2)', () => {
  let gameService: GameService;

  function minimalRoom(code: string): Room {
    return {
      code,
      players: [
        { id: 'p1', displayName: 'Alice', isHost: true, isConnected: true, socketId: 'sock-1' },
        { id: 'p2', displayName: 'Bob', isHost: false, isConnected: true, socketId: 'sock-2' },
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
      abilityTimerSeconds: null,
      formationSlug: null,
      tournamentEnabled: false,
      simulationSpeed: 'normal',
    };
  }

  beforeEach(() => {
    clearAllCache();
    gameService = new GameService();
  });

  afterEach(() => {
    clearAllCache();
    jest.restoreAllMocks();
  });

  it('a second createSession call does not re-read admin-data files from disk (cache hit)', () => {
    const readMock = fs.readFileSync as jest.Mock;
    readMock.mockClear();

    gameService.createSession(minimalRoom('ROOM01'));
    const callsAfterFirst = readMock.mock.calls.length;
    expect(callsAfterFirst).toBeGreaterThan(0); // sanity: it actually read from disk at all

    gameService.createSession(minimalRoom('ROOM02'));
    const callsAfterSecond = readMock.mock.calls.length;

    // The second call must not have triggered any additional disk reads —
    // formations.json/abilities.json were both served from cache.
    expect(callsAfterSecond).toBe(callsAfterFirst);
  });

  it('clearAllCache forces the next createSession call to re-read from disk', () => {
    const readMock = fs.readFileSync as jest.Mock;
    readMock.mockClear();

    gameService.createSession(minimalRoom('ROOM01'));
    const callsAfterFirst = readMock.mock.calls.length;

    clearAllCache();

    gameService.createSession(minimalRoom('ROOM02'));
    const callsAfterClear = readMock.mock.calls.length;

    // After an explicit cache clear, the same files are read again — proving
    // the first call's low read count really was a cache hit, not just an
    // already-missing/empty file short-circuiting before ever reading.
    expect(callsAfterClear).toBeGreaterThan(callsAfterFirst);
  });
});

/**
 * Spectator structural-invisibility coverage (multiplayer-rooms step 2 — see
 * MULTIPLAYER_ROOMS_DESIGN.md, section B). createSession() only ever reads
 * room.players — room.spectators is a completely separate list a spectator
 * is added to (RoomsService.spectateRoom), so this is really confirming a
 * negative: a spectator present on the Room object must never leak into any
 * part of the resulting GameSession, without GameService needing to know
 * spectators exist at all.
 */
describe('GameService — spectators never enter the session (multiplayer-rooms step 2)', () => {
  let gameService: GameService;

  function minimalRoom(code: string): Room {
    return {
      code,
      players: [
        { id: 'p1', displayName: 'Alice', isHost: true, isConnected: true, socketId: 'sock-1' },
        { id: 'p2', displayName: 'Bob', isHost: false, isConnected: true, socketId: 'sock-2' },
      ],
      spectators: [
        { id: 'spec-1', displayName: 'Watcher', isConnected: true, socketId: 'sock-spec-1' },
      ],
      isStarted: true,
      isLocked: false,
      kickedPlayerIds: [],
      kickedDisplayNames: [],
      pendingJoinRequests: [],
      lastActivityAt: Date.now(),
      leagues: [],
      turnTimerSeconds: null,
      subsTimerSeconds: null,
      abilityTimerSeconds: null,
      formationSlug: null,
      tournamentEnabled: false,
      simulationSpeed: 'normal',
    };
  }

  beforeEach(() => {
    clearAllCache();
    gameService = new GameService();
  });

  afterEach(() => {
    clearAllCache();
    jest.restoreAllMocks();
  });

  it('a spectator on the room never appears in the session players, pitches, or turn order', () => {
    const session = gameService.createSession(minimalRoom('SPECROOM'));

    expect(session.players.map((p) => p.id)).toEqual(['p1', 'p2']);
    expect(session.players.some((p) => p.id === 'spec-1')).toBe(false);
    expect(Object.keys(session.pitches)).toEqual(['p1', 'p2']);
    expect(session.baseTurnOrder).not.toContain('spec-1');
    expect(session.pitches['spec-1']).toBeUndefined();
  });
});

/**
 * Integration coverage for Task 2.3: endSession() is the single choke point
 * every game-end path passes through, and must record a match-history row
 * whenever the session actually reached a real result — but not for a
 * session swept away with no result at all (e.g. a stale, never-started lobby).
 */
describe('GameService — endSession match-history recording (Task 2.3)', () => {
  let gameService: GameService;
  let matchHistoryService: MatchHistoryService;
  const ORIGINAL_ENV = process.env;
  const ROOM_CODE = 'MATCH1';
  const SESSION_ID = 'sess-match-1';

  function baseSession(overrides: Partial<GameSession> = {}): GameSession {
    return {
      sessionId: SESSION_ID,
      roomCode: ROOM_CODE,
      createdAt: Date.now() - 600_000, // 10 minutes ago
      leagues: [],
      playerBonusCache: new Map(),
      userChallengeCache: new Map(),
      formation: { name: '4-3-3', slots: [] } as any,
      players: [{ id: 'p1', displayName: 'Alice', isHost: true, isConnected: true }],
      pitches: {},
      baseTurnOrder: ['p1'],
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
      turn: {
        turnId: 't1',
        phase: 'selecting_position',
        activePlayerId: 'p1',
        activeSlotIndex: null,
        candidates: [],
        turnStartedAt: null,
      },
      turnTimeoutPolicy: { enabled: false, turnSeconds: null, onExpiry: null },
      status: 'finished',
      abilityDraft: null,
      playerAbilities: {},
      abilityActivations: [],
      subSwappedCardIds: new Set(),
      isFinished: true,
      subsPhase: null,
      subsTimerSeconds: null,
      abilityTimerSeconds: null,
      subsDeadlineAt: null,
      abilityActivationDeadlineAt: null,
      result: { reason: 'completed', players: [{ playerId: 'p1', displayName: 'Alice', rank: 1, score: 88 }] },
      ...overrides,
    } as GameSession;
  }

  function inject(session: GameSession): void {
    (gameService as unknown as { sessions: Map<string, GameSession> }).sessions.set(
      session.sessionId,
      session,
    );
    (gameService as unknown as { roomToSession: Map<string, string> }).roomToSession.set(
      session.roomCode,
      session.sessionId,
    );
  }

  beforeEach(() => {
    process.env = { ...ORIGINAL_ENV, DB_PATH: ':memory:' };
    matchHistoryService = new MatchHistoryService();
    matchHistoryService.onModuleInit();
    gameService = new GameService(undefined, matchHistoryService);
  });

  afterEach(() => {
    matchHistoryService.onModuleDestroy();
    process.env = ORIGINAL_ENV;
  });

  it('endSession on a session with a real result records a match-history row', () => {
    inject(baseSession());

    gameService.endSession(ROOM_CODE);

    const recent = matchHistoryService.getRecentMatches();
    expect(recent).toHaveLength(1);
    expect(recent[0]).toMatchObject({
      roomCode: ROOM_CODE,
      playerCount: 1,
      results: [{ playerId: 'p1', displayName: 'Alice', score: 88, rank: 1 }],
    });
    // createdAt was 10 minutes (600s) before endSession ran.
    expect(recent[0].durationSeconds).toBeGreaterThanOrEqual(599);
    expect(recent[0].durationSeconds).toBeLessThanOrEqual(601);
  });

  it('endSession on a session with no result does not record anything', () => {
    inject(baseSession({ result: null, status: 'drafting', isFinished: false }));

    gameService.endSession(ROOM_CODE);

    expect(matchHistoryService.getRecentMatches()).toHaveLength(0);
  });

  it('endSession for a roomCode with no session is a safe no-op', () => {
    expect(() => gameService.endSession('NOPE99')).not.toThrow();
    expect(matchHistoryService.getRecentMatches()).toHaveLength(0);
  });
});

/**
 * Regression coverage for the active-player refresh/reconnect bug: a client
 * that refreshed mid selecting_card had no way to ever see the candidate
 * pool again, because buildSnapshot's turn object explicitly omitted
 * `candidates` ("candidates intentionally omitted") — the only place that
 * pool was ever sent was the one-off `slot_candidates` event fired live,
 * once, as the direct response to the pick_slot request that created it.
 *
 * The fix makes `turn.candidates` part of the durable snapshot, scoped to
 * the active player only (mirroring myAbility/scoringPreview's existing
 * localPlayerId-scoped treatment elsewhere in buildSnapshot) — everyone
 * else, and every other phase, still gets an empty array.
 */
describe('GameService — buildSnapshot turn.candidates scoping (reconnect-restore fix)', () => {
  let gameService: GameService;
  const ROOM_CODE = 'CANDROOM';
  const SESSION_ID = 'sess-cand';

  const sampleCandidate = {
    cardId: 'card-1',
    playerName: 'Test Striker',
    basePositionType: 'ST',
    rating: 90,
    pace: 90,
    shooting: 90,
    passing: 70,
    dribbling: 80,
    defending: 30,
    physical: 75,
    nationality: 'Testland',
    club: 'Test FC',
    altPositions: [],
    naturalPositions: ['ST'],
  } as any;

  function baseSession(overrides: Partial<GameSession> = {}): GameSession {
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
      currentRoundSlotIndex: 3,
      draftedCardIds: new Set(),
      roundCandidates: [sampleCandidate],
      orderedHiddenDeck: [],
      hiddenPicksTaken: new Set(),
      hiddenPicksMap: new Map(),
      hiddenPickReveal: null,
      lastRoundLeftovers: [],
      turn: {
        turnId: 't1',
        phase: 'selecting_card',
        activePlayerId: 'p1',
        activeSlotIndex: 3,
        candidates: [sampleCandidate],
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
      abilityTimerSeconds: null,
      subsDeadlineAt: null,
      abilityActivationDeadlineAt: null,
      result: null,
      ...overrides,
    } as GameSession;
  }

  beforeEach(() => {
    gameService = new GameService();
  });

  function inject(session: GameSession): void {
    (gameService as unknown as { sessions: Map<string, GameSession> }).sessions.set(
      session.sessionId,
      session,
    );
    (gameService as unknown as { roomToSession: Map<string, string> }).roomToSession.set(
      session.roomCode,
      session.sessionId,
    );
  }

  it('includes the candidate pool for the active player\'s own snapshot — the reconnect-restore payload', () => {
    const session = baseSession();
    inject(session);

    const snapshot = gameService.buildSnapshot(session, 'p1') as any;

    expect(snapshot.turn.candidates).toHaveLength(1);
    expect(snapshot.turn.candidates[0].cardId).toBe('card-1');
  });

  it('never includes candidates for a non-active player (no peeking at the other player\'s pool)', () => {
    const session = baseSession();
    inject(session);

    const snapshot = gameService.buildSnapshot(session, 'p2') as any;

    expect(snapshot.turn.candidates).toEqual([]);
  });

  it('never includes candidates when localPlayerId is unknown (e.g. a spectator\'s snapshot)', () => {
    const session = baseSession();
    inject(session);

    const snapshot = gameService.buildSnapshot(session, undefined) as any;

    expect(snapshot.turn.candidates).toEqual([]);
  });

  it('is empty for the active player outside selecting_card, matching session.turn.candidates being reset elsewhere', () => {
    const session = baseSession({
      turn: {
        turnId: 't2',
        phase: 'selecting_position',
        activePlayerId: 'p1',
        activeSlotIndex: null,
        candidates: [], // reset by pickCard/advance-turn before this phase begins
        turnStartedAt: null,
      },
    });
    inject(session);

    const snapshot = gameService.buildSnapshot(session, 'p1') as any;

    expect(snapshot.turn.candidates).toEqual([]);
  });
});

/**
 * Regression coverage for the chemistry-privacy leak: chemistryBonuses were
 * previously sent unredacted for every pitch, which let any client locally
 * recompute an opponent's full achieved chemistry (ChemistryEvaluator on the
 * Flutter side derives everything from club/nationality/league/position —
 * already-public fields — combined with the card's own chemistryBonuses).
 * _serializePitches now strips chemistryBonuses to [] for every pitch except
 * the viewer's own, mirroring the existing localPlayerId-scoped pattern used
 * by _buildSubsPhaseSnapshot for the bench.
 */
describe('GameService — buildSnapshot pitch chemistry scoping (chemistry-privacy fix)', () => {
  let gameService: GameService;
  const ROOM_CODE = 'CHEMROOM';
  const SESSION_ID = 'sess-chem';

  const sampleBonus = {
    tier: 1,
    requirement: 'same_club',
    required: 2,
    reward: 3,
  } as any;

  function sampleCard(cardId: string): any {
    return {
      cardId,
      playerName: 'Test Striker',
      basePositionType: 'ST',
      rating: 90,
      pace: 90,
      shooting: 90,
      passing: 70,
      dribbling: 80,
      defending: 30,
      physical: 75,
      nationality: 'Testland',
      club: 'Test FC',
      altPositions: [],
      naturalPositions: ['ST'],
      chemistryBonuses: [sampleBonus],
    };
  }

  function baseSession(): GameSession {
    return {
      sessionId: SESSION_ID,
      roomCode: ROOM_CODE,
      createdAt: Date.now(),
      leagues: [],
      playerBonusCache: new Map(),
      userChallengeCache: new Map(),
      scoringConfig: DEFAULT_SCORING_CONFIG_V1,
      scoringConfigVersion: 1,
      formation: { name: '4-3-3', slots: [] } as any,
      players: [
        { id: 'p1', displayName: 'Alice', isHost: true, isConnected: true },
        { id: 'p2', displayName: 'Bob', isHost: false, isConnected: true },
      ],
      pitches: {
        p1: {
          playerId: 'p1',
          filledCount: 1,
          slots: [
            {
              index: 0,
              label: 'ST',
              basePositionType: 'ST',
              card: sampleCard('card-p1'),
            },
          ],
        },
        p2: {
          playerId: 'p2',
          filledCount: 1,
          slots: [
            {
              index: 0,
              label: 'ST',
              basePositionType: 'ST',
              card: sampleCard('card-p2'),
            },
          ],
        },
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
      status: 'drafting',
      abilityDraft: null,
      playerAbilities: {},
      abilityActivations: [],
      abilityActivationRevealed: false,
      subSwappedCardIds: new Set(),
      coachedPositions: {},
      isFinished: false,
      subsPhase: null,
      subsTimerSeconds: null,
      abilityTimerSeconds: null,
      subsDeadlineAt: null,
      abilityActivationDeadlineAt: null,
      tournamentEnabled: false,
      simulationSpeed: 'normal',
      tournament: null,
      tournamentAwardsConfig: null,
      tournamentAwardsConfigVersion: null,
      result: null,
    } as GameSession;
  }

  beforeEach(() => {
    gameService = new GameService();
  });

  function inject(session: GameSession): void {
    (gameService as unknown as { sessions: Map<string, GameSession> }).sessions.set(
      session.sessionId,
      session,
    );
    (gameService as unknown as { roomToSession: Map<string, string> }).roomToSession.set(
      session.roomCode,
      session.sessionId,
    );
  }

  it("redacts chemistryBonuses on another player's pitch when viewed as p1", () => {
    const session = baseSession();
    inject(session);

    const snapshot = gameService.buildSnapshot(session, 'p1') as any;

    expect(snapshot.pitches.p2.slots[0].card.chemistryBonuses).toEqual([]);
  });

  it('keeps chemistryBonuses intact on the viewer\'s own pitch', () => {
    const session = baseSession();
    inject(session);

    const snapshot = gameService.buildSnapshot(session, 'p1') as any;

    expect(snapshot.pitches.p1.slots[0].card.chemistryBonuses).toHaveLength(1);
    expect(snapshot.pitches.p1.slots[0].card.chemistryBonuses[0]).toEqual(sampleBonus);
  });

  it('symmetrically redacts p1 when viewed as p2', () => {
    const session = baseSession();
    inject(session);

    const snapshot = gameService.buildSnapshot(session, 'p2') as any;

    expect(snapshot.pitches.p1.slots[0].card.chemistryBonuses).toEqual([]);
    expect(snapshot.pitches.p2.slots[0].card.chemistryBonuses).toHaveLength(1);
  });

  it('redacts every pitch when localPlayerId is unknown (e.g. a spectator\'s snapshot)', () => {
    const session = baseSession();
    inject(session);

    const snapshot = gameService.buildSnapshot(session, undefined) as any;

    expect(snapshot.pitches.p1.slots[0].card.chemistryBonuses).toEqual([]);
    expect(snapshot.pitches.p2.slots[0].card.chemistryBonuses).toEqual([]);
  });

  it('leaves other card fields (rating, club, etc.) intact on a redacted opponent card', () => {
    const session = baseSession();
    inject(session);

    const snapshot = gameService.buildSnapshot(session, 'p1') as any;
    const opponentCard = snapshot.pitches.p2.slots[0].card;

    expect(opponentCard.cardId).toBe('card-p2');
    expect(opponentCard.rating).toBe(90);
    expect(opponentCard.club).toBe('Test FC');
  });

  it('drops the redaction once the game is finished — full chemistry for every pitch, matching the result screen\'s intentional post-game reveal', () => {
    const session = { ...baseSession(), isFinished: true, status: 'finished' } as GameSession;
    inject(session);

    const snapshot = gameService.buildSnapshot(session, 'p1') as any;

    expect(snapshot.pitches.p1.slots[0].card.chemistryBonuses).toHaveLength(1);
    expect(snapshot.pitches.p2.slots[0].card.chemistryBonuses).toHaveLength(1);
  });
});
