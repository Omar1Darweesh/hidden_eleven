jest.mock('fs', () => ({
  ...jest.requireActual('fs'),
  existsSync: jest.fn(),
  readFileSync: jest.fn(),
  writeFileSync: jest.fn(),
  mkdirSync: jest.fn(),
}));

import * as fs from 'fs';
import { AdminService } from './admin.service';
import { clearAllCache } from '../game/admin-data-cache';

/**
 * getAbilities()/updateAbility() had zero test coverage before this file —
 * this backstops the pre-existing self-heal/merge behavior (already relied
 * on historically to backfill `color` into legacy files, per the doc
 * comment on getAbilities()) at the same moment `description` is added as
 * a second field that needs the identical backfill. `fs` is fully mocked
 * so each test controls exactly what "abilities.json" contains, without
 * touching this repo's real admin-data/ files.
 */
describe('AdminService — abilities self-heal and editing', () => {
  let service: AdminService;
  let storedFile: string | null;

  beforeEach(() => {
    clearAllCache();
    storedFile = null;
    (fs.existsSync as jest.Mock).mockImplementation((p: string) => {
      if (String(p).endsWith('abilities.json')) return storedFile !== null;
      return true;
    });
    (fs.readFileSync as jest.Mock).mockImplementation((p: string) => {
      if (String(p).endsWith('abilities.json')) return storedFile ?? '[]';
      return '[]';
    });
    (fs.writeFileSync as jest.Mock).mockImplementation((p: string, data: string) => {
      if (String(p).endsWith('abilities.json')) storedFile = data;
    });
    (fs.mkdirSync as jest.Mock).mockImplementation(() => undefined);
    service = new AdminService();
  });

  it('self-heals a legacy abilities.json missing `description` on every entry', () => {
    // Simulates every real pre-existing deployment: a file written before
    // `description` existed, same as the historical `color` backfill case
    // this exact merge logic was already built to handle.
    storedFile = JSON.stringify([
      { type: 'captain', name: 'Captain Card', enabled: true, color: '#FFC83D' },
      { type: 'yellow', name: 'Yellow Card', enabled: false, color: '#F2C037' },
    ]);

    const abilities = service.getAbilities();

    expect(abilities).toHaveLength(6); // all 6 types present, not just the 2 stored
    for (const a of abilities) {
      expect(typeof a.description).toBe('string');
      expect(a.description.length).toBeGreaterThan(0);
    }
    // Stored fields (enabled/color) are preserved exactly, not overwritten
    // by the seed defaults, even while description gets backfilled.
    const yellow = abilities.find((a) => a.type === 'yellow')!;
    expect(yellow.enabled).toBe(false);
    expect(yellow.color).toBe('#F2C037');
  });

  it('the seeded description for captain/yellow references the chemistry placeholders, not a hardcoded number', () => {
    const abilities = service.getAbilities();
    const captain = abilities.find((a) => a.type === 'captain')!;
    const yellow = abilities.find((a) => a.type === 'yellow')!;
    expect(captain.description).toContain('{captainMultiplier}');
    expect(captain.description).not.toMatch(/\bdouble\b/i);
    expect(yellow.description).toContain('{yellowPenalty}');
    expect(yellow.description).not.toMatch(/\b20\b/);
  });

  it('updateAbility persists description without disturbing other fields on that or other entries', () => {
    service.getAbilities(); // establishes the seeded file on first read
    const updated = service.updateAbility('coach', {
      description: 'A custom admin-authored description.',
    });

    expect(updated.description).toBe('A custom admin-authored description.');
    expect(updated.name).toBe('Coach Card'); // untouched
    expect(updated.color).toBe('#A55CFF'); // untouched
    expect(updated.enabled).toBe(true); // untouched

    const reloaded = service.getAbilities();
    const coach = reloaded.find((a) => a.type === 'coach')!;
    expect(coach.description).toBe('A custom admin-authored description.');
    // Sibling entries unaffected by the write — still their seeded default.
    const sub = reloaded.find((a) => a.type === 'sub')!;
    expect(sub.description).toBe('Swap a player with a rival’s same-position player.');
  });

  it('updateAbility can save name/color/description together in one call', () => {
    const updated = service.updateAbility('red', {
      name: 'Straight Red',
      color: '#FF0000',
      description: 'Sends a rival player off for the rest of the match.',
    });

    expect(updated).toMatchObject({
      type: 'red',
      name: 'Straight Red',
      color: '#FF0000',
      description: 'Sends a rival player off for the rest of the match.',
    });
  });

  it('updateAbility on an unknown type still throws NotFoundException', () => {
    expect(() => service.updateAbility('not_a_real_type', { name: 'x' })).toThrow(
      'Ability not found: not_a_real_type',
    );
  });
});
