import * as fs from 'fs';
import { getCached, invalidateCache, clearAllCache } from './admin-data-cache';
import { AdminService } from '../admin/admin.service';

// Node's built-in `fs` module exposes non-configurable property descriptors
// under this project's ts-jest/ESM-interop setup — jest.spyOn(fs, '...')
// fails with "Cannot redefine property" rather than installing a spy.
// Mocking the whole module (replacing the registry entry, not redefining a
// property on the existing frozen object) sidesteps the issue. Each fn
// starts as a thin in-memory stand-in; the one test below that needs real
// file-shaped behavior configures these directly rather than delegating to
// the real implementation, since it must never touch the real admin-data
// seed files on disk.
jest.mock('fs', () => ({
  ...jest.requireActual('fs'),
  existsSync: jest.fn(),
  mkdirSync: jest.fn(),
  readFileSync: jest.fn(),
  writeFileSync: jest.fn(),
}));

describe('admin-data-cache (Task 2.2)', () => {
  afterEach(() => {
    clearAllCache();
  });

  it('getCached only invokes the loader once across multiple calls (cache hit on the second call)', () => {
    const loader = jest.fn(() => ({ value: 'loaded-once' }));

    const first = getCached('test-key', loader);
    const second = getCached('test-key', loader);

    expect(loader).toHaveBeenCalledTimes(1);
    expect(first).toBe(second); // same cached reference, not just equal value
  });

  it('different keys are cached independently', () => {
    const loaderA = jest.fn(() => 'a');
    const loaderB = jest.fn(() => 'b');

    getCached('key-a', loaderA);
    getCached('key-b', loaderB);
    getCached('key-a', loaderA);

    expect(loaderA).toHaveBeenCalledTimes(1);
    expect(loaderB).toHaveBeenCalledTimes(1);
  });

  it('invalidateCache forces the next call to re-run the loader (fresh data, not stale)', () => {
    let counter = 0;
    const loader = jest.fn(() => ++counter);

    expect(getCached('test-key', loader)).toBe(1);
    expect(getCached('test-key', loader)).toBe(1); // still cached

    invalidateCache('test-key');

    expect(getCached('test-key', loader)).toBe(2); // re-loaded after invalidation
    expect(loader).toHaveBeenCalledTimes(2);
  });

  it('invalidating a key that was never cached is a harmless no-op', () => {
    expect(() => invalidateCache('never-cached-key')).not.toThrow();
  });

  it('clearAllCache forces every key to be re-loaded on the next call', () => {
    const loaderA = jest.fn(() => 'a');
    const loaderB = jest.fn(() => 'b');
    getCached('key-a', loaderA);
    getCached('key-b', loaderB);

    clearAllCache();

    getCached('key-a', loaderA);
    getCached('key-b', loaderB);

    expect(loaderA).toHaveBeenCalledTimes(2);
    expect(loaderB).toHaveBeenCalledTimes(2);
  });
});

/**
 * Cross-module integration: a real AdminService write must invalidate the
 * cache key GameService's load*() helpers use for that same file, so the
 * very next read picks up fresh data instead of stale cached data. Mocks
 * the fs layer entirely (not a temp directory) so this test cannot touch the
 * real admin-data/*.json seed files on disk.
 */
describe('AdminService write → admin-data-cache invalidation (Task 2.2 integration)', () => {
  afterEach(() => {
    clearAllCache();
    jest.restoreAllMocks();
  });

  it('AdminService.createPlayer() invalidates the players.json cache key', () => {
    let stored: unknown[] = [];
    (fs.existsSync as jest.Mock).mockReturnValue(true);
    (fs.mkdirSync as jest.Mock).mockReturnValue(undefined);
    (fs.readFileSync as jest.Mock).mockImplementation(() => JSON.stringify(stored));
    (fs.writeFileSync as jest.Mock).mockImplementation((_path: unknown, data: unknown) => {
      stored = JSON.parse(data as string);
    });

    // Prime the cache under the exact key game.service.ts's loadPlayerPool
    // uses for this same file, using the real getCached() — proving the
    // invalidation below is reaching the real shared cache, not a copy.
    const loader = jest.fn(() => 'cached-players-snapshot');
    expect(getCached('players.json', loader)).toBe('cached-players-snapshot');
    expect(loader).toHaveBeenCalledTimes(1);

    const adminService = new AdminService();
    adminService.createPlayer({
      name: 'New Player',
      club: 'Test FC',
      positions: ['ST'],
      rating: 80,
    } as never);

    // The write must have invalidated the cache — the next getCached() call
    // for the same key re-runs the loader instead of returning the stale value.
    expect(getCached('players.json', loader)).toBe('cached-players-snapshot');
    expect(loader).toHaveBeenCalledTimes(2);
  });
});
