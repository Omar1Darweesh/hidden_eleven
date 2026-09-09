import { AbilityType, HOSTILE_ABILITIES } from './interfaces/ability.interface';
import { GameSession } from './interfaces/game-session.interface';

/**
 * The outcome of resolving one activation phase's declarations.
 *
 * Deliberately a plain, derived value object: both the reveal pass (which
 * mutates the board) and scoring (which reads declaratively, much later) call
 * the same resolver, so the two can never disagree about who was frozen or
 * protected. Storing only the inputs and re-deriving is what keeps a
 * reconnect, a re-score, or a replay from producing a different answer.
 */
export interface AbilityResolution {
  /** Players whose ability was cancelled by a `freeze`. */
  frozenPlayerIds: Set<string>;
  /** Users shielded from `yellow` / `red` / `sub` this activation. */
  protectedUserIds: Set<string>;
}

/**
 * Resolves the activation phase's layers.
 *
 * Activation is simultaneous and hidden — every player locks in secretly and
 * nothing is revealed until all have — so there is no turn-based priority
 * window to decide who "responds last". Priority is an explicit rule instead:
 *
 *      Layer 0  freeze    — always resolves
 *      Layer 1  protect   — unless the protector was frozen
 *      Layer 2  sub       — board mutation, skipped if caster frozen or target protected
 *      Layer 3  yellow / red / captain / coach / extra_bench
 *
 * **Every layer reads the ORIGINAL declarations, never the previous layer's
 * output.** That is the whole trick. If protection could block the freeze
 * aimed at it, you get a circular definition — protect survives, so the freeze
 * never happened, so protect wasn't needed — with no stable answer. Freeze
 * therefore always lands, and a protected player can still be frozen.
 *
 * Consequences that fall out of this and are covered by tests:
 *  - Mutual freeze (A freezes B, B freezes A) → both land, both abilities dead.
 *  - A frozen player's own freeze STILL resolves — it was declared before
 *    anything resolved, and Layer 0 is simultaneous.
 *  - Protection blocks EVERY hostile ability aimed at its owner, not one.
 *    With simultaneous activation, "absorb one attack" would need an arbitrary
 *    tiebreak to pick which — and the only available order (`baseTurnOrder`)
 *    is invisible to players, so it would read as random.
 *
 * Pure and order-independent: iterating the declarations in any order yields
 * the same result.
 */
export function resolveAbilityLayers(session: GameSession): AbilityResolution {
  const frozenPlayerIds = new Set<string>();
  const protectedUserIds = new Set<string>();

  const abilities = Object.entries(session.playerAbilities ?? {});

  // ── Layer 0: freeze ──────────────────────────────────────────────────────
  // Computed from declarations alone, so nothing can prevent a freeze.
  for (const [casterId, ability] of abilities) {
    if (ability?.status !== 'used' || ability.type !== 'freeze') continue;
    const target = ability.targetUserId;
    // Self-freeze is rejected at validation; guard anyway so a malformed
    // payload can't disable the caster.
    if (!target || target === casterId) continue;
    frozenPlayerIds.add(target);
  }

  // ── Layer 1: protect ─────────────────────────────────────────────────────
  // A frozen protector grants nothing. This is the line that makes the
  // headline case work: A red-cards B, B protects, C freezes B → B is not
  // protected, so the red card lands normally.
  for (const [casterId, ability] of abilities) {
    if (ability?.status !== 'used' || ability.type !== 'protect') continue;
    if (frozenPlayerIds.has(casterId)) continue;
    protectedUserIds.add(casterId);
  }

  return { frozenPlayerIds, protectedUserIds };
}

/**
 * Whether a used ability should take effect at all.
 *
 * Answers both halves in one place so the reveal pass and scoring can't drift:
 * a frozen caster does nothing, and a hostile ability aimed at a protected
 * user fizzles.
 */
export function abilityTakesEffect(
  casterId: string,
  type: AbilityType,
  targetUserId: string | undefined,
  resolution: AbilityResolution,
): boolean {
  if (resolution.frozenPlayerIds.has(casterId)) return false;
  if (
    targetUserId &&
    HOSTILE_ABILITIES.includes(type) &&
    resolution.protectedUserIds.has(targetUserId)
  ) {
    return false;
  }
  return true;
}

/**
 * Why an ability did nothing, for the public reveal text — or null when it
 * resolved normally.
 *
 * The reveal must state the real reason: a player who spent their card needs
 * to see whether they were frozen or walled off, not just that nothing
 * happened.
 */
export function fizzleReason(
  casterId: string,
  type: AbilityType,
  targetUserId: string | undefined,
  resolution: AbilityResolution,
): 'frozen' | 'blocked' | null {
  if (resolution.frozenPlayerIds.has(casterId)) return 'frozen';
  if (
    targetUserId &&
    HOSTILE_ABILITIES.includes(type) &&
    resolution.protectedUserIds.has(targetUserId)
  ) {
    return 'blocked';
  }
  return null;
}
