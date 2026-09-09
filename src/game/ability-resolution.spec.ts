import {
  resolveAbilityLayers,
  abilityTakesEffect,
  fizzleReason,
} from './ability-resolution';
import { AbilityType, PlayerAbility } from './interfaces/ability.interface';
import { GameSession } from './interfaces/game-session.interface';

/**
 * The full resolution matrix for Protection and Freeze.
 *
 * Activation is simultaneous and hidden, so priority is an explicit rule
 * rather than a timing artefact:
 *
 *      freeze  >  protect  >  everything else
 *
 * These tests pin every combination that rule has to answer — above all the
 * headline case, where a third player's freeze strips a protection and lets an
 * unrelated attack through.
 */

function ability(
  type: AbilityType,
  targetUserId?: string,
  status: PlayerAbility['status'] = 'used',
): PlayerAbility {
  return { type, status, targetUserId };
}

/** Minimal session shape — the resolver only reads `playerAbilities`. */
function session(
  playerAbilities: Record<string, PlayerAbility>,
): GameSession {
  return { playerAbilities } as unknown as GameSession;
}

describe('resolveAbilityLayers', () => {
  describe('Layer 0 — freeze always resolves', () => {
    it('freezes its target', () => {
      const r = resolveAbilityLayers(
        session({ a: ability('freeze', 'b'), b: ability('red', 'c') }),
      );
      expect(r.frozenPlayerIds.has('b')).toBe(true);
    });

    it('a protected player can still be frozen — protection never shields itself', () => {
      const r = resolveAbilityLayers(
        session({ a: ability('freeze', 'b'), b: ability('protect') }),
      );
      expect(r.frozenPlayerIds.has('b')).toBe(true);
      expect(r.protectedUserIds.has('b')).toBe(false);
    });

    it('mutual freeze — both land, both abilities die', () => {
      const r = resolveAbilityLayers(
        session({ a: ability('freeze', 'b'), b: ability('freeze', 'a') }),
      );
      expect(r.frozenPlayerIds.has('a')).toBe(true);
      expect(r.frozenPlayerIds.has('b')).toBe(true);
    });

    it("a frozen player's own freeze still resolves (Layer 0 is simultaneous)", () => {
      const r = resolveAbilityLayers(
        session({
          a: ability('freeze', 'b'),
          b: ability('freeze', 'c'),
          c: ability('protect'),
        }),
      );
      expect(r.frozenPlayerIds.has('b')).toBe(true);
      // b was frozen, but b's freeze on c still went off.
      expect(r.frozenPlayerIds.has('c')).toBe(true);
      expect(r.protectedUserIds.has('c')).toBe(false);
    });

    it('two freezes on the same target are redundant, not cumulative', () => {
      const r = resolveAbilityLayers(
        session({
          a: ability('freeze', 'c'),
          b: ability('freeze', 'c'),
          c: ability('protect'),
        }),
      );
      expect(r.frozenPlayerIds.size).toBe(1);
      expect(r.frozenPlayerIds.has('c')).toBe(true);
    });

    it('a self-freeze is ignored even if it reaches the resolver', () => {
      const r = resolveAbilityLayers(session({ a: ability('freeze', 'a') }));
      expect(r.frozenPlayerIds.size).toBe(0);
    });

    it('a discarded freeze does nothing', () => {
      const r = resolveAbilityLayers(
        session({
          a: ability('freeze', 'b', 'discarded'),
          b: ability('protect'),
        }),
      );
      expect(r.frozenPlayerIds.size).toBe(0);
      expect(r.protectedUserIds.has('b')).toBe(true);
    });
  });

  describe('Layer 1 — protect', () => {
    it('an unfrozen protector is protected', () => {
      const r = resolveAbilityLayers(session({ b: ability('protect') }));
      expect(r.protectedUserIds.has('b')).toBe(true);
    });

    it('protection with nobody attacking still resolves (simply unused)', () => {
      const r = resolveAbilityLayers(
        session({ a: ability('captain'), b: ability('protect') }),
      );
      expect(r.protectedUserIds.has('b')).toBe(true);
    });
  });

  it('is order-independent — declaration order never changes the outcome', () => {
    const forward = resolveAbilityLayers(
      session({
        a: ability('red', 'b'),
        b: ability('protect'),
        c: ability('freeze', 'b'),
      }),
    );
    const reverse = resolveAbilityLayers(
      session({
        c: ability('freeze', 'b'),
        b: ability('protect'),
        a: ability('red', 'b'),
      }),
    );
    expect([...forward.frozenPlayerIds]).toEqual([...reverse.frozenPlayerIds]);
    expect([...forward.protectedUserIds]).toEqual([
      ...reverse.protectedUserIds,
    ]);
  });
});

describe('abilityTakesEffect — the scenario matrix', () => {
  it('#1 protection blocks yellow', () => {
    const s = session({ a: ability('yellow', 'b'), b: ability('protect') });
    const r = resolveAbilityLayers(s);
    expect(abilityTakesEffect('a', 'yellow', 'b', r)).toBe(false);
  });

  it('#2 protection blocks red', () => {
    const s = session({ a: ability('red', 'b'), b: ability('protect') });
    const r = resolveAbilityLayers(s);
    expect(abilityTakesEffect('a', 'red', 'b', r)).toBe(false);
  });

  it('#3 protection blocks sub', () => {
    const s = session({ a: ability('sub', 'b'), b: ability('protect') });
    const r = resolveAbilityLayers(s);
    expect(abilityTakesEffect('a', 'sub', 'b', r)).toBe(false);
  });

  it('#7 HEADLINE: A red-cards B, B protects, C freezes B → the red card lands', () => {
    const s = session({
      a: ability('red', 'b'),
      b: ability('protect'),
      c: ability('freeze', 'b'),
    });
    const r = resolveAbilityLayers(s);

    expect(r.frozenPlayerIds.has('b')).toBe(true);
    expect(r.protectedUserIds.has('b')).toBe(false);
    // The whole point: A's attack is unaffected and resolves normally.
    expect(abilityTakesEffect('a', 'red', 'b', r)).toBe(true);
    expect(fizzleReason('a', 'red', 'b', r)).toBeNull();
    // B's protection is reported as frozen, not silently missing.
    expect(fizzleReason('b', 'protect', undefined, r)).toBe('frozen');
  });

  it('#9 protection blocks EVERY attack aimed at its owner, not just one', () => {
    const s = session({
      a: ability('red', 'b'),
      d: ability('yellow', 'b'),
      b: ability('protect'),
    });
    const r = resolveAbilityLayers(s);
    expect(abilityTakesEffect('a', 'red', 'b', r)).toBe(false);
    expect(abilityTakesEffect('d', 'yellow', 'b', r)).toBe(false);
  });

  it('#11 a frozen self-buff (captain/coach/extra_bench) never applies', () => {
    const s = session({
      a: ability('freeze', 'b'),
      b: ability('captain'),
    });
    const r = resolveAbilityLayers(s);
    expect(abilityTakesEffect('b', 'captain', undefined, r)).toBe(false);
    expect(abilityTakesEffect('b', 'coach', undefined, r)).toBe(false);
    expect(abilityTakesEffect('b', 'extra_bench', undefined, r)).toBe(false);
  });

  it('#12 a frozen attacker\'s sub never happens', () => {
    const s = session({ a: ability('freeze', 'b'), b: ability('sub', 'c') });
    const r = resolveAbilityLayers(s);
    expect(abilityTakesEffect('b', 'sub', 'c', r)).toBe(false);
  });

  it('protection does NOT shield an unrelated third party', () => {
    const s = session({ a: ability('red', 'c'), b: ability('protect') });
    const r = resolveAbilityLayers(s);
    expect(abilityTakesEffect('a', 'red', 'c', r)).toBe(true);
  });

  it('an attack on an unprotected, unfrozen target resolves normally', () => {
    const s = session({ a: ability('red', 'b') });
    const r = resolveAbilityLayers(s);
    expect(abilityTakesEffect('a', 'red', 'b', r)).toBe(true);
  });

  it('freeze itself is never blocked by protection (it is not "hostile" for shielding)', () => {
    const s = session({ a: ability('freeze', 'b'), b: ability('protect') });
    const r = resolveAbilityLayers(s);
    expect(abilityTakesEffect('a', 'freeze', 'b', r)).toBe(true);
  });
});

describe('fizzleReason — the reveal must state the real cause', () => {
  it('reports "blocked" when protection stopped an attack', () => {
    const s = session({ a: ability('red', 'b'), b: ability('protect') });
    const r = resolveAbilityLayers(s);
    expect(fizzleReason('a', 'red', 'b', r)).toBe('blocked');
  });

  it('reports "frozen" when the caster was frozen', () => {
    const s = session({ a: ability('freeze', 'b'), b: ability('red', 'c') });
    const r = resolveAbilityLayers(s);
    expect(fizzleReason('b', 'red', 'c', r)).toBe('frozen');
  });

  it('frozen outranks blocked when both would apply', () => {
    // b is frozen AND aiming at a protected c — frozen is the true cause.
    const s = session({
      a: ability('freeze', 'b'),
      b: ability('red', 'c'),
      c: ability('protect'),
    });
    const r = resolveAbilityLayers(s);
    expect(fizzleReason('b', 'red', 'c', r)).toBe('frozen');
  });

  it('returns null when the ability resolved normally', () => {
    const s = session({ a: ability('red', 'b') });
    const r = resolveAbilityLayers(s);
    expect(fizzleReason('a', 'red', 'b', r)).toBeNull();
  });
});
