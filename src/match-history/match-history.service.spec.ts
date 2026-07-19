import { MatchHistoryService } from './match-history.service';
import Database from 'better-sqlite3';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';

describe('MatchHistoryService (Task 2.3)', () => {
  let service: MatchHistoryService;
  const ORIGINAL_ENV = process.env;

  beforeEach(() => {
    // In-memory DB — never touches the real match-history.db file on disk.
    process.env = { ...ORIGINAL_ENV, DB_PATH: ':memory:' };
    service = new MatchHistoryService();
    service.onModuleInit();
  });

  afterEach(() => {
    service.onModuleDestroy();
    process.env = ORIGINAL_ENV;
  });

  it('recordMatch writes a row that getRecentMatches returns', () => {
    service.recordMatch('ABCDEF', 754, [
      { playerId: 'p1', displayName: 'Alice', score: 92, rank: 1 },
      { playerId: 'p2', displayName: 'Bob', score: 81, rank: 2 },
    ]);

    const recent = service.getRecentMatches();
    expect(recent).toHaveLength(1);
    expect(recent[0]).toMatchObject({
      roomCode: 'ABCDEF',
      durationSeconds: 754,
      playerCount: 2,
      results: [
        { playerId: 'p1', displayName: 'Alice', score: 92, rank: 1 },
        { playerId: 'p2', displayName: 'Bob', score: 81, rank: 2 },
      ],
    });
    expect(typeof recent[0].id).toBe('number');
    expect(typeof recent[0].playedAt).toBe('number');
  });

  it('a recordMatch failure (DB closed) is swallowed and logged, never thrown', () => {
    service.onModuleDestroy(); // closes the DB out from under the service

    expect(() =>
      service.recordMatch('ABCDEF', 100, [{ playerId: 'p1', displayName: 'Alice', score: 50, rank: 1 }]),
    ).not.toThrow();
  });

  it('recordMatch on a never-initialized service (no onModuleInit) does not throw', () => {
    const uninitialized = new MatchHistoryService();
    expect(() =>
      uninitialized.recordMatch('ABCDEF', 100, [{ playerId: 'p1', displayName: 'Alice', score: 50, rank: 1 }]),
    ).not.toThrow();
  });

  it('getRecentMatches respects the limit even when more rows exist', () => {
    for (let i = 0; i < 5; i++) {
      service.recordMatch(`ROOM${i}`, 100, [{ playerId: 'p1', displayName: 'Alice', score: 50, rank: 1 }]);
    }

    expect(service.getRecentMatches(2)).toHaveLength(2);
  });

  it('getRecentMatches returns the most recent matches first', () => {
    service.recordMatch('FIRST', 100, [{ playerId: 'p1', displayName: 'Alice', score: 50, rank: 1 }]);
    // played_at uses Date.now() — force a distinct, later timestamp for the second row.
    jest.spyOn(Date, 'now').mockReturnValue(Date.now() + 10_000);
    service.recordMatch('SECOND', 100, [{ playerId: 'p1', displayName: 'Alice', score: 50, rank: 1 }]);
    jest.restoreAllMocks();

    const recent = service.getRecentMatches();
    expect(recent[0].roomCode).toBe('SECOND');
    expect(recent[1].roomCode).toBe('FIRST');
  });

  it('getRecentMatches defaults to 20 and never throws on a 0 or negative limit', () => {
    service.recordMatch('ABCDEF', 100, [{ playerId: 'p1', displayName: 'Alice', score: 50, rank: 1 }]);
    expect(() => service.getRecentMatches(0)).not.toThrow();
    expect(() => service.getRecentMatches(-5)).not.toThrow();
  });
});

describe('MatchHistoryService — schema migrations (Task 3.3)', () => {
  const ORIGINAL_ENV = process.env;
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'h11-migrations-'));
  });

  afterEach(() => {
    process.env = ORIGINAL_ENV;
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it('fresh database: onModuleInit applies all migrations, getMigrationVersion returns the latest version', () => {
    process.env = { ...ORIGINAL_ENV, DB_PATH: ':memory:' };
    const service = new MatchHistoryService();
    service.onModuleInit();

    // MIGRATIONS defines version 1 (matches table) and version 2 (played_at index).
    expect(service.getMigrationVersion()).toBe(2);
    expect(() =>
      service.recordMatch('ABCDEF', 100, [{ playerId: 'p1', displayName: 'Alice', score: 50, rank: 1 }]),
    ).not.toThrow();

    service.onModuleDestroy();
  });

  it('already-migrated database: re-running onModuleInit is idempotent (no duplicate rows, no error)', () => {
    const dbPath = path.join(tmpDir, 'match-history.db');
    process.env = { ...ORIGINAL_ENV, DB_PATH: dbPath };

    const first = new MatchHistoryService();
    first.onModuleInit();
    expect(first.getMigrationVersion()).toBe(2);
    first.onModuleDestroy();

    const second = new MatchHistoryService();
    expect(() => second.onModuleInit()).not.toThrow();
    expect(second.getMigrationVersion()).toBe(2);

    // Re-running must not insert duplicate schema_migrations rows.
    const raw = new Database(dbPath);
    const rows = raw.prepare('SELECT version FROM schema_migrations ORDER BY version').all() as Array<{ version: number }>;
    expect(rows).toEqual([{ version: 1 }, { version: 2 }]);
    raw.close();

    // The `matches` table must still be usable after the second init.
    expect(() =>
      second.recordMatch('GHIJKL', 100, [{ playerId: 'p1', displayName: 'Bob', score: 40, rank: 1 }]),
    ).not.toThrow();
    expect(second.getRecentMatches()).toHaveLength(1);

    second.onModuleDestroy();
  });

  it('a database already at version 1 only applies pending migrations, never reapplies version 1', () => {
    const dbPath = path.join(tmpDir, 'match-history.db');

    // Simulate a database already migrated through version 1 (with matches table).
    const seed = new Database(dbPath);
    seed.exec(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY,
        applied_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS matches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        room_code TEXT NOT NULL,
        played_at INTEGER NOT NULL,
        duration_seconds INTEGER,
        player_count INTEGER NOT NULL,
        results TEXT NOT NULL
      );
    `);
    seed.prepare('INSERT INTO schema_migrations (version, applied_at) VALUES (1, ?)').run(Date.now());
    seed.close();

    process.env = { ...ORIGINAL_ENV, DB_PATH: dbPath };
    const service = new MatchHistoryService();
    service.onModuleInit();

    expect(service.getMigrationVersion()).toBe(2);

    const raw = new Database(dbPath);
    const index = raw
      .prepare("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_matches_played_at'")
      .get();
    expect(index).toBeDefined();

    const rows = raw.prepare('SELECT version FROM schema_migrations ORDER BY version').all() as Array<{ version: number }>;
    expect(rows).toEqual([{ version: 1 }, { version: 2 }]);
    raw.close();

    service.onModuleDestroy();
  });
});
