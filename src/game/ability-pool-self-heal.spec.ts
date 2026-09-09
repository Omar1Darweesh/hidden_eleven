import * as fs from 'fs';
import * as path from 'path';
import { loadEnabledAbilityTypes } from './game.service';
import { clearAllCache } from './admin-data-cache';

/**
 * REGRESSION: a persisted `abilities.json` written before a new ability type
 * existed must not permanently hide that type from real games.
 *
 * This is exactly what happened when `protect`/`freeze` were added: any
 * already-running deployment already has an 8→6-short `abilities.json` on
 * disk. `loadEnabledAbilityTypes` used to only ever enable a type that was
 * *explicitly listed* in that file — so the two new abilities would type-check,
 * pass every unit test that builds its own in-memory session, and still never
 * once be dealt in an actual game until an admin happened to open the
 * Abilities page and save something. The admin panel's own `getAbilities()`
 * already self-heals for missing types; this brings the game-dealing path in
 * line with that same guarantee.
 */
describe('loadEnabledAbilityTypes — self-heal for types added after deployment', () => {
  const dataDir = path.resolve(process.cwd(), 'admin-data');
  const file = path.join(dataDir, 'abilities.json');
  let hadFile: boolean;
  let original: string | null = null;

  beforeEach(() => {
    hadFile = fs.existsSync(file);
    if (hadFile) original = fs.readFileSync(file, 'utf8');
  });

  afterEach(() => {
    if (hadFile && original !== null) {
      fs.writeFileSync(file, original);
    } else if (!hadFile && fs.existsSync(file)) {
      fs.unlinkSync(file);
    }
    clearAllCache();
  });

  it('a legacy 6-entry file (predating protect/freeze) still enables both new types', () => {
    fs.mkdirSync(dataDir, { recursive: true });
    fs.writeFileSync(
      file,
      JSON.stringify([
        { type: 'captain', enabled: true },
        { type: 'yellow', enabled: true },
        { type: 'red', enabled: true },
        { type: 'extra_bench', enabled: true },
        { type: 'sub', enabled: true },
        { type: 'coach', enabled: true },
      ]),
    );
    clearAllCache();

    const enabled = loadEnabledAbilityTypes();

    expect(enabled).toContain('protect');
    expect(enabled).toContain('freeze');
    expect(enabled).toHaveLength(8);
  });

  it('an explicit enabled:false for an existing type is still honoured — self-heal only fills GAPS, never overrides a real choice', () => {
    fs.mkdirSync(dataDir, { recursive: true });
    fs.writeFileSync(
      file,
      JSON.stringify([
        { type: 'captain', enabled: true },
        { type: 'yellow', enabled: false },
        { type: 'red', enabled: true },
        { type: 'extra_bench', enabled: true },
        { type: 'sub', enabled: true },
        { type: 'coach', enabled: true },
      ]),
    );
    clearAllCache();

    const enabled = loadEnabledAbilityTypes();

    expect(enabled).not.toContain('yellow');
    expect(enabled).toContain('protect');
    expect(enabled).toContain('freeze');
    expect(enabled).toHaveLength(7);
  });

  it('an explicit enabled:false already present for a new type is honoured, not healed away', () => {
    fs.mkdirSync(dataDir, { recursive: true });
    fs.writeFileSync(
      file,
      JSON.stringify([
        { type: 'captain', enabled: true },
        { type: 'yellow', enabled: true },
        { type: 'red', enabled: true },
        { type: 'extra_bench', enabled: true },
        { type: 'sub', enabled: true },
        { type: 'coach', enabled: true },
        { type: 'protect', enabled: false },
        { type: 'freeze', enabled: true },
      ]),
    );
    clearAllCache();

    const enabled = loadEnabledAbilityTypes();

    expect(enabled).not.toContain('protect');
    expect(enabled).toContain('freeze');
    expect(enabled).toHaveLength(7);
  });
});
