import { GameService } from './game.service';
import { GameSession } from './interfaces/game-session.interface';
import { PitchSlot, Pitch } from './interfaces/pitch.interface';
import { DraftCard } from './interfaces/draft-card.interface';
import { BasePositionType, SlotLabel } from './interfaces/formation.interface';
import { clearAllCache } from './admin-data-cache';
import {
  TournamentAwardsConfigFile,
  TournamentAwardsConfigVersion,
  DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1,
} from './tournament-awards-config';
import { DEFAULT_SCORING_CONFIG_V1 } from './scoring-config';

/**
 * Session snapshot safety (Track A Step 3): `GameService.beginTournament()`
 * must read the currently-published tournament awards config exactly ONCE,
 * at tournament start, and store a plain-value copy on the session
 * (`GameSession.tournamentAwardsConfig` / `tournamentAwardsConfigVersion`) —
 * same snapshot-safety principle as `game.service.scoring-config-snapshot.spec.ts`,
 * just triggered at tournament start instead of session creation (see the
 * GameSession.tournamentAwardsConfig doc comment for why there's no
 * session-creation-time equivalent for tournaments).
 *
 * These tests prove the actual guarantee: a config change published AFTER a
 * tournament already began must have zero effect on that session, while a
 * tournament begun AFTER the change picks up the new values. `fs` is fully
 * mocked (not spied) so each test controls exactly what "the
 * currently-published config" is at each point in time.
 */
jest.mock('fs', () => ({
  ...jest.requireActual('fs'),
  existsSync: jest.fn(),
  readFileSync: jest.fn(),
}));

import * as fs from 'fs';

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

function card(cardId: string, base: BasePositionType, rating: number): DraftCard {
  return {
    cardId, playerName: cardId, basePositionType: base, rating,
    pace: rating, shooting: rating, passing: rating, dribbling: rating, defending: rating, physical: rating,
    nationality: 'England', club: 'Test FC', altPositions: [], naturalPositions: [base],
    chemistryBonuses: [],
  };
}

function fullLineup(prefix: string, rating: number): PitchSlot[] {
  return FORMATION_SLOTS.map((s, index) => ({
    index, label: s.label, basePositionType: s.base, card: card(`${prefix}-${s.base}-${index}`, s.base, rating),
  }));
}

function pitch(playerId: string, slots: PitchSlot[]): Pitch {
  return { playerId, slots, filledCount: slots.filter((s) => s.card).length };
}

/** A finished-subs, tournament-enabled, 4-real-player session — mirrors
 *  game.service.tournament.spec.ts's tournamentSession() fixture. */
function tournamentSession(roomCode: string, sessionId: string): GameSession {
  const ids = ['p1', 'p2', 'p3', 'p4'];
  const pitches: Record<string, Pitch> = {};
  const userSubs: Record<string, { isComplete: boolean; lineupConfirmed: boolean }> = {};
  ids.forEach((id, i) => {
    pitches[id] = pitch(id, fullLineup(id, 90 - i * 2));
    userSubs[id] = { isComplete: true, lineupConfirmed: true };
  });

  return {
    sessionId,
    roomCode,
    createdAt: Date.now(),
    leagues: [],
    playerBonusCache: new Map(),
    userChallengeCache: new Map(),
    scoringConfig: DEFAULT_SCORING_CONFIG_V1,
    scoringConfigVersion: 1,
    formation: {
      name: '4-3-3',
      slug: '4-3-3',
      slots: FORMATION_SLOTS.map((s, index) => ({ index, label: s.label, basePositionType: s.base })),
    } as any,
    players: ids.map((id, i) => ({ id, displayName: id.toUpperCase(), isHost: i === 0, isConnected: true } as any)),
    pitches,
    baseTurnOrder: [...ids],
    currentRound: 12,
    totalRounds: 11,
    currentTurnIndex: 0,
    currentRoundSlotIndex: null,
    draftedCardIds: new Set(),
    roundCandidates: [],
    orderedHiddenDeck: [],
    hiddenPicksTaken: new Set(),
    lastRoundLeftovers: [],
    hiddenPicksMap: new Map(),
    hiddenPickReveal: null,
    turn: { turnId: 't1', phase: 'selecting_position', activePlayerId: 'p1', activeSlotIndex: null, candidates: [], turnStartedAt: null },
    turnTimeoutPolicy: { enabled: false, turnSeconds: null, onExpiry: null },
    status: 'lineup_edit',
    abilityDraft: null,
    playerAbilities: {},
    abilityActivations: [],
    abilityActivationRevealed: false,
    subSwappedCardIds: new Set(),
    coachedPositions: {},
    isFinished: false,
    subsPhase: { userSubs: userSubs as any },
    subsTimerSeconds: null,
    subsDeadlineAt: null,
    abilityActivationDeadlineAt: null,
    abilityTimerSeconds: null,
    tournamentEnabled: true,
    simulationSpeed: 'normal',
    tournament: null,
    tournamentAwardsConfig: null,
    tournamentAwardsConfigVersion: null,
    result: null,
  } as GameSession;
}

function inject(gameService: GameService, session: GameSession): void {
  (gameService as unknown as { sessions: Map<string, GameSession> }).sessions.set(session.sessionId, session);
  (gameService as unknown as { roomToSession: Map<string, string> }).roomToSession.set(session.roomCode, session.sessionId);
}

function awardsConfigFile(version: number, championPoints: number): TournamentAwardsConfigFile {
  const now = new Date().toISOString();
  const v: TournamentAwardsConfigVersion = {
    version,
    status: 'published',
    createdAt: now,
    publishedAt: now,
    values: { ...DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1, championPoints },
  };
  return { draft: v, published: v, history: [] };
}

const PLAYERS_JSON = [
  { id: 'x1', name: 'X One', club: 'Test FC', positions: ['GK'], rating: 80, nationality: 'Testland' },
];

/** Mocks admin-data/*.json reads; `awardsConfig: null` simulates a missing/malformed file. */
function mockAdminData(awardsConfig: TournamentAwardsConfigFile | null): void {
  (fs.existsSync as jest.Mock).mockReturnValue(true);
  (fs.readFileSync as jest.Mock).mockImplementation((filePath: string) => {
    const p = String(filePath);
    if (p.endsWith('tournament-awards-config.json')) {
      return awardsConfig ? JSON.stringify(awardsConfig) : '{ "not": "valid" }';
    }
    if (p.endsWith('players.json')) return JSON.stringify(PLAYERS_JSON);
    return '[]';
  });
}

describe('GameService — tournament awards config session snapshot safety', () => {
  let gameService: GameService;

  beforeEach(() => {
    clearAllCache();
    gameService = new GameService();
  });

  it('a tournament begun under v1 gets the published values snapshotted onto the session', () => {
    mockAdminData(awardsConfigFile(1, 50));
    const session = tournamentSession('ROOM1', 'sess1');
    inject(gameService, session);

    gameService.beginTournament(session.roomCode);

    expect(session.tournamentAwardsConfig).not.toBeNull();
    expect(session.tournamentAwardsConfig!.championPoints).toBe(50);
  });

  it('a tournament begun under v1 gets the published version snapshotted onto the session', () => {
    mockAdminData(awardsConfigFile(1, 50));
    const session = tournamentSession('ROOM1', 'sess1');
    inject(gameService, session);

    gameService.beginTournament(session.roomCode);

    expect(session.tournamentAwardsConfigVersion).toBe(1);
  });

  it('publishing a new config AFTER a tournament has begun does not mutate the existing session snapshot', () => {
    mockAdminData(awardsConfigFile(1, 50));
    const session1 = tournamentSession('ROOM1', 'sess1');
    inject(gameService, session1);
    gameService.beginTournament(session1.roomCode);

    expect(session1.tournamentAwardsConfigVersion).toBe(1);
    expect(session1.tournamentAwardsConfig!.championPoints).toBe(50);

    // Admin publishes a drastically different v2 AFTER the tournament already
    // began — clearAllCache() mirrors admin.service.ts's writeJson() ->
    // invalidateCache().
    clearAllCache();
    mockAdminData(awardsConfigFile(2, 999));

    // session1's own snapshot must be completely untouched by the change.
    expect(session1.tournamentAwardsConfigVersion).toBe(1);
    expect(session1.tournamentAwardsConfig!.championPoints).toBe(50);
  });

  it('a later tournament begun AFTER a new version is published picks up the newer config', () => {
    mockAdminData(awardsConfigFile(1, 50));
    const session1 = tournamentSession('ROOM1', 'sess1');
    inject(gameService, session1);
    gameService.beginTournament(session1.roomCode);

    clearAllCache();
    mockAdminData(awardsConfigFile(2, 999));
    const session2 = tournamentSession('ROOM2', 'sess2');
    inject(gameService, session2);
    gameService.beginTournament(session2.roomCode);

    expect(session2.tournamentAwardsConfigVersion).toBe(2);
    expect(session2.tournamentAwardsConfig!.championPoints).toBe(999);

    // session1 is still untouched by session2's later tournament start.
    expect(session1.tournamentAwardsConfigVersion).toBe(1);
    expect(session1.tournamentAwardsConfig!.championPoints).toBe(50);
  });

  it('a missing/malformed tournament-awards-config.json never crashes beginTournament and falls back to v1 defaults', () => {
    mockAdminData(null);
    const session = tournamentSession('ROOM3', 'sess3');
    inject(gameService, session);

    expect(() => gameService.beginTournament(session.roomCode)).not.toThrow();
    expect(session.tournamentAwardsConfigVersion).toBe(1);
    expect(session.tournamentAwardsConfig).toEqual(DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1);
  });
});
