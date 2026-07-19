/**
 * In-memory cache for the admin-data/*.json files game.service.ts's load*()
 * helpers read from disk. Before this, every game start (and several
 * mid-game calls — sub spins, candidate generation) re-read and
 * JSON.parse'd the full player pool from disk, even though admin-data only
 * changes when an admin explicitly edits something through the admin API.
 *
 * Plain module-level state (not a NestJS-managed singleton) deliberately —
 * the load*() functions in game.service.ts are themselves plain functions,
 * not class methods, and admin.service.ts lives in a completely different
 * module. A shared in-memory Map at the module level is naturally a
 * singleton within one Node process either way; routing it through Nest's
 * DI container would add ceremony (a service, an import in two unrelated
 * modules) for no behavioral benefit over importing two plain functions.
 *
 * Invalidation is keyed by filename (e.g. 'players.json') and hooked into
 * admin.service.ts's single writeJson() choke point — every admin write of
 * any admin-data file invalidates that file's cache entry unconditionally.
 * Invalidating a filename that was never cached (e.g. 'nations.json', which
 * no load*() helper here reads) is a harmless no-op (Map.delete on a missing
 * key), so this stays correct automatically if a new cached loader is added
 * later without needing to also update a manual "which write affects which
 * cache key" list.
 */
import { PinoLogger } from 'nestjs-pino';

const _cache = new Map<string, unknown>();

// Standalone (not DI-injected) for the same reason the cache itself is a
// plain module — see the file-level comment. Silent under Jest (NODE_ENV=test,
// set automatically by the test runner) so importing this module in a test
// never produces stray output, matching the silent-by-default fallback
// loggers used elsewhere (rooms.gateway.ts, rooms.service.ts, game.service.ts).
const _cacheLogLevel =
  process.env.NODE_ENV === 'test' ? 'silent' : process.env.NODE_ENV === 'production' ? 'info' : 'debug';
const _logger = new PinoLogger({ pinoHttp: { level: _cacheLogLevel } });
_logger.setContext('AdminDataCache');

export function getCached<T>(key: string, loader: () => T): T {
  if (_cache.has(key)) {
    _logger.debug({ key, result: 'hit' }, 'Admin-data cache hit');
    return _cache.get(key) as T;
  }
  const value = loader();
  _cache.set(key, value);
  _logger.debug({ key, result: 'miss' }, 'Admin-data cache miss — read from disk');
  return value;
}

export function invalidateCache(key: string): void {
  if (_cache.delete(key)) {
    _logger.info({ key }, 'Admin-data cache invalidated');
  }
}

export function clearAllCache(): void {
  _cache.clear();
}
