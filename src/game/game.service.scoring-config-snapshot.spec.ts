import { GameService } from './game.service';
import { Room, Player } from '../rooms/interfaces/room.interface';
import { clearAllCache } from './admin-data-cache';
import {
  ScoringConfigFile,
  ScoringConfigVersion,
  DEFAULT_SCORING_CONFIG_V1,
} from './scoring-config';

/**
 * Session snapshot safety (Phase A): `GameService.createSession()` must read
 * the currently-published scoring config exactly ONCE, at session creation,
 * and store a plain-value copy on the session (`GameSession.scoringConfig` /
 * `scoringConfigVersion`) — mirroring the existing `playerBonusCache`/
 * `userChallengeCache` "built once at session start" pattern this file's
 * sibling specs already cover for those two caches.
 *
 * These tests prove the actual guarantee the design spec depends on: a
 * config change published AFTER a session already exists must have zero
 * effect on that session, while a session created AFTER the change picks up
 * the new values. `fs` is fully mocked (not spied) so each test controls
 * exactly what "the currently-published config" is at each point in time.
 */
jest.mock('fs', () => ({
  ...jest.requireActual('fs'),
  existsSync: jest.fn(),
  readFileSync: jest.fn(),
}));

import * as fs from 'fs';

const PLAYERS_JSON = [
  { id: 'x1', name: 'X One', club: 'Test FC', positions: ['GK'], rating: 80, nationality: 'Testland' },
  { id: 'x2', name: 'X Two', club: 'Test FC', positions: ['ST'], rating: 80, nationality: 'Testland' },
];

function scoringConfigFile(
  version: number,
  yellowPenalty: number,
): ScoringConfigFile {
  const now = new Date().toISOString();
  const v: ScoringConfigVersion = {
    version,
    status: 'published',
    createdAt: now,
    publishedAt: now,
    values: {
      ...DEFAULT_SCORING_CONFIG_V1,
      abilityEffects: { ...DEFAULT_SCORING_CONFIG_V1.abilityEffects, yellowPenalty },
    },
  };
  return { draft: v, published: v, history: [] };
}

/** Mocks admin-data/*.json reads; `scoringConfig: null` simulates a missing/malformed file. */
function mockAdminData(scoringConfig: ScoringConfigFile | null): void {
  (fs.existsSync as jest.Mock).mockReturnValue(true);
  (fs.readFileSync as jest.Mock).mockImplementation((filePath: string) => {
    const p = String(filePath);
    if (p.endsWith('scoring-config.json')) {
      return scoringConfig ? JSON.stringify(scoringConfig) : '{ "not": "valid" }';
    }
    if (p.endsWith('players.json')) return JSON.stringify(PLAYERS_JSON);
    return '[]';
  });
}

function minimalRoom(code: string): Room {
  const players: Player[] = [
    { id: 'p1', displayName: 'Alice', isHost: true, isConnected: true, socketId: 's1' },
    { id: 'p2', displayName: 'Bob', isHost: false, isConnected: true, socketId: 's2' },
  ];
  return {
    code,
    players,
    spectators: [],
    isStarted: false,
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
  } as Room;
}

describe('GameService — scoring config session snapshot safety', () => {
  let gameService: GameService;

  beforeEach(() => {
    clearAllCache();
    gameService = new GameService();
  });

  it('a session created under v1 keeps v1 even after a v2 is published afterward', () => {
    mockAdminData(scoringConfigFile(1, 20));
    const session1 = gameService.createSession(minimalRoom('ROOM1'));
    expect(session1.scoringConfigVersion).toBe(1);
    expect(session1.scoringConfig.abilityEffects.yellowPenalty).toBe(20);

    // Admin publishes a drastically different v2 AFTER session1 was created —
    // clearAllCache() mirrors admin.service.ts's writeJson() -> invalidateCache().
    clearAllCache();
    mockAdminData(scoringConfigFile(2, 999));

    // session1's own snapshot must be completely untouched by the change.
    expect(session1.scoringConfigVersion).toBe(1);
    expect(session1.scoringConfig.abilityEffects.yellowPenalty).toBe(20);
  });

  it('a session created AFTER a new version is published picks up the new version', () => {
    mockAdminData(scoringConfigFile(1, 20));
    gameService.createSession(minimalRoom('ROOM1'));

    clearAllCache();
    mockAdminData(scoringConfigFile(2, 999));
    const session2 = gameService.createSession(minimalRoom('ROOM2'));

    expect(session2.scoringConfigVersion).toBe(2);
    expect(session2.scoringConfig.abilityEffects.yellowPenalty).toBe(999);
  });

  it('a missing/malformed scoring-config.json never crashes createSession and falls back to v1 defaults', () => {
    mockAdminData(null);
    expect(() => gameService.createSession(minimalRoom('ROOM3'))).not.toThrow();

    clearAllCache();
    mockAdminData(null);
    const session = gameService.createSession(minimalRoom('ROOM4'));
    expect(session.scoringConfigVersion).toBe(1);
    expect(session.scoringConfig).toEqual(DEFAULT_SCORING_CONFIG_V1);
  });
});
