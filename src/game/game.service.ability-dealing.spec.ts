import { GameService } from './game.service';
import { AbilityType, AbilityCard } from './interfaces/ability.interface';

/**
 * The no-repeat dealing rule: when playerCount <= the number of DISTINCT
 * enabled abilities, every player must draw a different ability. Repeats are
 * only introduced once there aren't enough distinct abilities for everyone.
 *
 * This exercises the private buildAbilityPool directly (same private-access
 * pattern the other game.service specs use) because it is the single source of
 * the rule; loadEnabledAbilityTypes (disk) feeds it a de-duplicated list, and
 * buildAbilityPool de-dupes again so the guarantee holds for any caller.
 */
function build(
  gs: GameService,
  playerCount: number,
  enabled: AbilityType[],
): AbilityCard[] {
  return (
    gs as unknown as {
      buildAbilityPool(n: number, e: AbilityType[]): AbilityCard[];
    }
  ).buildAbilityPool(playerCount, enabled);
}

describe('GameService — ability dealing (no-repeat rule)', () => {
  let gs: GameService;
  beforeEach(() => {
    gs = new GameService();
  });

  it('2 enabled + 2 players → each player gets a DIFFERENT ability (the exact reported bug)', () => {
    // Run many times to defeat shuffle luck — must be unique EVERY time.
    for (let i = 0; i < 200; i++) {
      const pool = build(gs, 2, ['sub', 'coach']);
      expect(pool).toHaveLength(2);
      const types = pool.map((c) => c.type);
      expect(new Set(types).size).toBe(2); // no repeats
      expect(types).toContain('sub');
      expect(types).toContain('coach');
    }
  });

  it('N enabled + N players (N <= distinct) → all distinct, no repeats', () => {
    for (let i = 0; i < 100; i++) {
      const pool = build(gs, 5, ['captain', 'yellow', 'red', 'sub', 'coach']);
      expect(new Set(pool.map((c) => c.type)).size).toBe(5);
    }
  });

  it('fewer enabled than players → repeats ONLY then (1 enabled + 2 players)', () => {
    const pool = build(gs, 2, ['coach']);
    expect(pool).toHaveLength(2);
    expect(pool.every((c) => c.type === 'coach')).toBe(true);
  });

  it('duplicate entries in the enabled list do NOT break uniqueness (dedupe guard)', () => {
    // A malformed abilities.json could list the same type twice. Even so, with
    // 2 DISTINCT abilities and 2 players, both players must still differ.
    for (let i = 0; i < 200; i++) {
      const pool = build(gs, 2, ['sub', 'sub', 'coach']);
      expect(pool).toHaveLength(2);
      expect(new Set(pool.map((c) => c.type)).size).toBe(2);
    }
  });

  it('3 distinct enabled + 5 players → the 3 distinct all appear, extras repeat only to fill', () => {
    const pool = build(gs, 5, ['captain', 'sub', 'coach']);
    expect(pool).toHaveLength(5);
    const types = new Set(pool.map((c) => c.type));
    // All 3 distinct abilities must be present; the 2 extra slots are repeats.
    expect(types).toEqual(new Set(['captain', 'sub', 'coach']));
  });
});
