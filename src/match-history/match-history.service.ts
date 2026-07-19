import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { InjectPinoLogger, PinoLogger } from 'nestjs-pino';
import Database from 'better-sqlite3';
import * as path from 'path';

export interface PlayerMatchResult {
  playerId: string;
  displayName: string;
  score: number | null;
  rank: number;
}

export interface MatchRecord {
  id: number;
  roomCode: string;
  playedAt: number;
  durationSeconds: number | null;
  playerCount: number;
  results: PlayerMatchResult[];
}

interface Migration {
  version: number;
  sql: string;
}

/**
 * Ordered, integer-versioned schema migrations (Task 3.3) — a lightweight
 * alternative to a full migration-library/ORM, appropriate here since this
 * is a single table with a handful of columns, not a complex relational
 * schema. Version 1 is the original `CREATE TABLE IF NOT EXISTS matches`
 * statement from Task 2.3, moved here unchanged (its own IF NOT EXISTS
 * keeps it safe to re-run against an already-migrated database, the same
 * idempotency the whole migration runner relies on). Future schema changes
 * (a new column, a new index) get appended as version 2, 3, etc. — never
 * edit an already-shipped migration's SQL after it's been released, since a
 * database that already recorded that version as applied would silently
 * never re-run it.
 */
const MIGRATIONS: Migration[] = [
  {
    version: 1,
    sql: `
      CREATE TABLE IF NOT EXISTS matches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        room_code TEXT NOT NULL,
        played_at INTEGER NOT NULL,
        duration_seconds INTEGER,
        player_count INTEGER NOT NULL,
        results TEXT NOT NULL
      )
    `,
  },
  {
    version: 2,
    sql: `CREATE INDEX IF NOT EXISTS idx_matches_played_at ON matches(played_at DESC)`,
  },
];

/**
 * One row per completed game, written once at the moment a session ends —
 * the only durable record of a match once its in-memory GameSession is torn
 * down (everything else in this app lives in Maps and is gone on restart by
 * design, see PROJECT_AUDIT_REPORT.md). better-sqlite3 is synchronous and
 * embedded (no separate process, no network round-trip) — appropriate here
 * specifically because the one write this service does happens at game-end,
 * not inside any per-action hot path.
 */
@Injectable()
export class MatchHistoryService implements OnModuleInit, OnModuleDestroy {
  private db!: Database.Database;

  constructor(
    @InjectPinoLogger(MatchHistoryService.name)
    private readonly logger: PinoLogger = new PinoLogger({ pinoHttp: { level: 'silent' } }),
  ) {}

  onModuleInit(): void {
    const dbPath = process.env.DB_PATH ?? path.resolve(process.cwd(), 'match-history.db');
    this.db = new Database(dbPath);

    // Unconditional, before any other init — schema_migrations itself has
    // no migration (it must exist before version-checking logic can run).
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY,
        applied_at INTEGER NOT NULL
      )
    `);

    this._runMigrations();

    this.logger.info({ dbPath, schemaVersion: this.getMigrationVersion() }, 'Match history database ready');
  }

  onModuleDestroy(): void {
    this.db?.close();
  }

  /**
   * Applies every migration whose version is greater than the currently
   * recorded schema version, in ascending order, each in its own
   * transaction — so a mid-migration failure on a fresh database doesn't
   * leave a half-applied table with no record of it. Re-running this
   * against an already-migrated database is a no-op (the version filter
   * leaves nothing pending).
   */
  private _runMigrations(): void {
    const currentVersion = this.getMigrationVersion();
    const pending = MIGRATIONS.filter((m) => m.version > currentVersion).sort(
      (a, b) => a.version - b.version,
    );

    for (const migration of pending) {
      const applyMigration = this.db.transaction(() => {
        this.db.exec(migration.sql);
        this.db
          .prepare('INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)')
          .run(migration.version, Date.now());
      });
      applyMigration();
      this.logger.info({ version: migration.version }, 'Applied schema migration');
    }
  }

  /** Currently-applied schema version (0 if no migration has ever run). */
  getMigrationVersion(): number {
    const row = this.db.prepare('SELECT MAX(version) AS v FROM schema_migrations').get() as {
      v: number | null;
    };
    return row?.v ?? 0;
  }

  /**
   * Inserts one match record. Fire-and-forget by contract — callers (see
   * GameService.endSession) must never let a write failure here propagate
   * and break the actual game-end flow, so this catches and logs internally
   * rather than throwing. A lost match-history row is a real but acceptable
   * loss; a broken game-end broadcast is not.
   */
  recordMatch(roomCode: string, durationSeconds: number | null, results: PlayerMatchResult[]): void {
    try {
      if (!this.db) {
        // Never initialized (onModuleInit didn't run — e.g. a standalone,
        // non-DI construction, the same defaulted pattern used elsewhere in
        // this codebase for test instantiation). Same contract as a real
        // write failure: log and move on, never throw into the caller.
        this.logger.warn({ roomCode }, 'Match history DB not initialized — skipping write');
        return;
      }
      this.db
        .prepare(
          `INSERT INTO matches (room_code, played_at, duration_seconds, player_count, results)
           VALUES (?, ?, ?, ?, ?)`,
        )
        .run(roomCode, Date.now(), durationSeconds, results.length, JSON.stringify(results));
    } catch (err) {
      this.logger.error({ roomCode, err }, 'Failed to record match history — game flow continues unaffected');
    }
  }

  /**
   * Total recorded matches. For /metrics (Task 3.4) — same "never throw"
   * contract as recordMatch: an uninitialized service (no onModuleInit, the
   * same defaulted test/non-DI shape used elsewhere in this file) reports 0
   * rather than throwing.
   */
  getMatchCount(): number {
    if (!this.db) return 0;
    const row = this.db.prepare('SELECT COUNT(*) AS count FROM matches').get() as { count: number };
    return row.count;
  }

  getRecentMatches(limit = 20): MatchRecord[] {
    const rows = this.db
      .prepare(
        `SELECT id, room_code AS roomCode, played_at AS playedAt, duration_seconds AS durationSeconds,
                player_count AS playerCount, results
         FROM matches
         ORDER BY played_at DESC
         LIMIT ?`,
      )
      .all(Math.max(0, limit)) as Array<{
      id: number;
      roomCode: string;
      playedAt: number;
      durationSeconds: number | null;
      playerCount: number;
      results: string;
    }>;

    return rows
      .map((row) => {
        try {
          return {
            ...row,
            results: JSON.parse(row.results) as PlayerMatchResult[],
          };
        } catch (err) {
          this.logger.warn({ id: row.id, err }, 'Skipping corrupt match-history row');
          return null;
        }
      })
      .filter((row): row is MatchRecord => row !== null);
  }
}
