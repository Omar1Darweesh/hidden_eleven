import { GameService } from './game.service';
import { GameSession } from './interfaces/game-session.interface';
import { PitchSlot, Pitch } from './interfaces/pitch.interface';
import { clearAllCache, invalidateCache } from './admin-data-cache';
import { DEFAULT_SCORING_CONFIG_V1 } from './scoring-config';

/**
 * Regression coverage for the enriched-player-pool memoization fix (Task 5).
 *
 * BACKGROUND: load-testing at 30 concurrent games (medium.js) showed game
 * duration and even unrelated /metrics requests degrade ~3x compared to the
 * 10-game baseline — root-caused to loadPlayerPool() in game.service.ts
 * re-running a full `.map()` enrichment pass over the entire player pool
 * (5000+ rows in the real admin-data set) on every single generateCandidates
 * / sub-spin / AI-pool call, across every concurrent game, competing for the
 * single Node event loop. The fix memoizes the enriched pool by reference
 * identity against its two cached inputs (raw players, club metadata) so it
 * only actually recomputes when one of those inputs changes.
 *
 * These tests exist specifically to prove the fix didn't reintroduce the
 * staleness bug the original (deliberately uncached) code was written to
 * avoid: an admin editing club metadata mid-session must still show up on
 * the very next call, not be served from a memoized snapshot forever.
 *
 * `fs` is mocked at this file's module scope (isolated from other spec
 * files' real-admin-data-reading tests — Jest gives each test file its own
 * module registry) so this test controls club metadata precisely instead of
 * depending on the real ~5000-row admin-data/players.json.
 */
jest.mock('fs', () => ({
  ...jest.requireActual('fs'),
  existsSync: jest.fn(),
  readFileSync: jest.fn(),
}));

import * as fs from 'fs';

const PLAYERS_JSON = [
  { id: 'x1', name: 'X One', club: 'Test FC', positions: ['GK'], rating: 80, nationality: 'Testland' },
];

function mockAdminData(clubs: { name: string; league: string; logoUrl: string }[]): void {
  (fs.existsSync as jest.Mock).mockReturnValue(true);
  (fs.readFileSync as jest.Mock).mockImplementation((filePath: string) => {
    const p = String(filePath);
    if (p.endsWith('players.json')) return JSON.stringify(PLAYERS_JSON);
    if (p.endsWith('clubs.json')) return JSON.stringify(clubs);
    if (p.endsWith('formations.json') || p.endsWith('abilities.json')) return JSON.stringify([]);
    return '[]';
  });
}

function emptyPitchSlots(): PitchSlot[] {
  return [{ index: 0, label: 'GK', basePositionType: 'GK', card: null }];
}

function pitch(playerId: string, slots: PitchSlot[]): Pitch {
  return { playerId, slots, filledCount: 0 };
}

function draftSession(roomCode: string, sessionId: string): GameSession {
  return {
    sessionId,
    roomCode,
    createdAt: Date.now(),
    leagues: [],
    playerBonusCache: new Map(),
    userChallengeCache: new Map(),
    scoringConfig: DEFAULT_SCORING_CONFIG_V1,
    scoringConfigVersion: 1,
    formation: { name: '4-3-3', slots: [] } as any,
    players: [
      { id: 'p1', displayName: 'Alice', isHost: true, isConnected: true } as any,
      { id: 'p2', displayName: 'Bob', isHost: false, isConnected: true } as any,
    ],
    pitches: { p1: pitch('p1', emptyPitchSlots()), p2: pitch('p2', emptyPitchSlots()) },
    baseTurnOrder: ['p1', 'p2'],
    currentTurnIndex: 0,
    currentRound: 1,
    totalRounds: 11,
    currentRoundSlotIndex: null,
    draftedCardIds: new Set(),
    roundCandidates: [],
    turn: { turnId: 't1', phase: 'selecting_position', activePlayerId: 'p1', activeSlotIndex: null, candidates: [], turnStartedAt: null } as any,
    hiddenPickReveal: null,
    orderedHiddenDeck: [],
    hiddenPicksTaken: new Set(),
    hiddenPicksMap: new Map(),
    lastRoundLeftovers: [],
    turnTimeoutPolicy: { enabled: false, turnSeconds: null, onExpiry: null } as any,
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
    subsDeadlineAt: null,
    abilityActivationDeadlineAt: null,
    abilityTimerSeconds: null,
    result: null,
    tournamentEnabled: false,
    simulationSpeed: 'normal',
    tournament: null,
    tournamentAwardsConfig: null,
    tournamentAwardsConfigVersion: null,
  } as GameSession;
}

function inject(gameService: GameService, session: GameSession): void {
  (gameService as unknown as { sessions: Map<string, GameSession> }).sessions.set(session.sessionId, session);
  (gameService as unknown as { roomToSession: Map<string, string> }).roomToSession.set(session.roomCode, session.sessionId);
}

describe('GameService — enriched player-pool memoization stays fresh after admin edits (Task 5)', () => {
  let gameService: GameService;

  beforeEach(() => {
    gameService = new GameService();
    clearAllCache();
  });

  afterEach(() => {
    clearAllCache();
    jest.restoreAllMocks();
  });

  it('reflects club metadata set BEFORE the first read', () => {
    mockAdminData([{ name: 'Test FC', league: 'League V1', logoUrl: 'http://v1/logo.png' }]);

    const session = draftSession('ROOM1', 'sess-1');
    inject(gameService, session);

    const result = gameService.pickSlot('ROOM1', 'p1', 't1', 0) as { candidates: { league?: string; clubLogoUrl?: string }[] };
    expect(result.candidates).toHaveLength(1);
    expect(result.candidates[0].league).toBe('League V1');
    expect(result.candidates[0].clubLogoUrl).toBe('http://v1/logo.png');
  });

  it('a repeated read with no admin write in between stays consistent (memoization does not corrupt data)', () => {
    mockAdminData([{ name: 'Test FC', league: 'League V1', logoUrl: 'http://v1/logo.png' }]);

    const s1 = draftSession('ROOM1', 'sess-1');
    inject(gameService, s1);
    const first = gameService.pickSlot('ROOM1', 'p1', 't1', 0) as { candidates: { league?: string }[] };

    const s2 = draftSession('ROOM2', 'sess-2');
    inject(gameService, s2);
    const second = gameService.pickSlot('ROOM2', 'p1', 't1', 0) as { candidates: { league?: string }[] };

    expect(first.candidates[0].league).toBe('League V1');
    expect(second.candidates[0].league).toBe('League V1');
  });

  it('picks up NEW club metadata immediately after invalidateCache("clubs.json") — the memoization must not serve a stale snapshot forever', () => {
    mockAdminData([{ name: 'Test FC', league: 'League V1', logoUrl: 'http://v1/logo.png' }]);

    const s1 = draftSession('ROOM1', 'sess-1');
    inject(gameService, s1);
    const before = gameService.pickSlot('ROOM1', 'p1', 't1', 0) as { candidates: { league?: string; clubLogoUrl?: string }[] };
    expect(before.candidates[0].league).toBe('League V1');

    // Simulate an admin editing the club through the real write path this
    // fix must stay compatible with: admin.service.ts's writeJson() calls
    // invalidateCache('clubs.json') unconditionally on every write.
    mockAdminData([{ name: 'Test FC', league: 'League V2', logoUrl: 'http://v2/logo.png' }]);
    invalidateCache('clubs.json');

    const s2 = draftSession('ROOM2', 'sess-2');
    inject(gameService, s2);
    const after = gameService.pickSlot('ROOM2', 'p1', 't1', 0) as { candidates: { league?: string; clubLogoUrl?: string }[] };

    expect(after.candidates[0].league).toBe('League V2');
    expect(after.candidates[0].clubLogoUrl).toBe('http://v2/logo.png');
  });

  it('picks up a NEW players.json snapshot immediately after invalidateCache("players.json")', () => {
    mockAdminData([{ name: 'Test FC', league: 'League V1', logoUrl: 'http://v1/logo.png' }]);

    const s1 = draftSession('ROOM1', 'sess-1');
    inject(gameService, s1);
    const before = gameService.pickSlot('ROOM1', 'p1', 't1', 0) as { candidates: { cardId: string }[] };
    expect(before.candidates[0].cardId).toBe('x1');

    (fs.readFileSync as jest.Mock).mockImplementation((filePath: string) => {
      const p = String(filePath);
      if (p.endsWith('players.json')) {
        return JSON.stringify([
          { id: 'x2', name: 'X Two', club: 'Test FC', positions: ['GK'], rating: 85, nationality: 'Testland' },
        ]);
      }
      if (p.endsWith('clubs.json')) {
        return JSON.stringify([{ name: 'Test FC', league: 'League V1', logoUrl: 'http://v1/logo.png' }]);
      }
      return '[]';
    });
    invalidateCache('players.json');

    const s2 = draftSession('ROOM2', 'sess-2');
    inject(gameService, s2);
    const after = gameService.pickSlot('ROOM2', 'p1', 't1', 0) as { candidates: { cardId: string }[] };

    expect(after.candidates[0].cardId).toBe('x2');
  });
});
