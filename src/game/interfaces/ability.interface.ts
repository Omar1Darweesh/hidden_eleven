import { BasePositionType } from './formation.interface';

/**
 * Ability cards — a face-down draft at the start of a game. Each player picks
 * one secret ability (turn order), then later activates or discards it in the
 * dedicated activation phase between the draft and the subs phase.
 *
 * The originals:
 *  - captain     : double one of your own players' chemistry points.
 *  - yellow      : subtract 20 points from a chosen user's final score.
 *  - red         : nullify the chemistry of one player in another user's lineup
 *                  (rating still counts; contributes 0 chemistry in any direction).
 *  - extra_bench : an extra bench player usable for ANY position (not one line).
 *  - sub         : swap one of your players with another user's player in the
 *                  same position.
 *  - coach       : add one new (non-GK) playable position to one of your OWN
 *                  (non-GK) players for the rest of the match. From then on that
 *                  player is treated exactly as if they naturally had it — full
 *                  chemistry when fielded there, valid for swap/placement checks.
 *                  Purely additive: it grants no protection from red/yellow/etc.
 */
export type AbilityType =
  | 'captain'
  | 'yellow'
  | 'red'
  | 'extra_bench'
  | 'sub'
  | 'coach';

export const ABILITY_ORIGINALS: AbilityType[] = [
  'captain',
  'yellow',
  'red',
  'extra_bench',
  'sub',
  'coach',
];

/**
 * Every base position a Coach card may add / target, i.e. all of
 * `BasePositionType` except `GK`. GK is fully excluded on both sides: you can
 * neither coach a goalkeeper nor add GK as the new position.
 */
export const COACHABLE_POSITIONS: BasePositionType[] = [
  'LB', 'CB', 'RB',
  'CDM', 'CM', 'CAM',
  'LM', 'RM',
  'LW', 'RW',
  'CF', 'ST',
];

/** One face-down card in the ability-draft pool for a single game. */
export interface AbilityCard {
  /** Stable id within this game's pool (0-based). */
  id: number;
  type: AbilityType;
  /** Player id who picked this card, or null while still face-down. */
  pickedBy: string | null;
}

/** Turn-order face-down ability draft, active only during `ability_draft`. */
export interface AbilityDraftState {
  /** Face-down pool; length === player count. */
  pool: AbilityCard[];
  /** Player ids in pick order (mirrors the draft's base turn order). */
  pickOrder: string[];
  /** Index into pickOrder whose turn it is to pick. */
  currentPickIndex: number;
}

/** A player's chosen ability and its lifecycle for the rest of the game. */
export interface PlayerAbility {
  type: AbilityType;
  /** 'pending' until the activation phase resolves it. */
  status: 'pending' | 'used' | 'discarded';
  // ── Activation targets (filled when used; meaning depends on type) ──
  /** red: the targeted card id (in the rival's lineup). coach: the caster's
   *  own targeted card id (the coached position follows this card wherever it
   *  moves, exactly like captain/red track by card id). */
  targetPlayerId?: string;
  /** captain/sub/coach: the local pitch slot index of the targeted own card. */
  sourceSlotIndex?: number;
  /** coach: the new (non-GK) position added to the targeted own player. */
  coachedPosition?: BasePositionType;
  /** red/sub: the targeted slot index in the rival's lineup (pitch). */
  targetSlotIndex?: number;
  /** yellow/red/sub: the targeted user (game player id). */
  targetUserId?: string;
  /**
   * red/sub: rival bench group (`att`/`mid`/`def`) when targeting a bench
   * card instead of a pitch slot. Mutually exclusive with `targetSlotIndex`.
   * `extra` is never valid here — Extra Bench picks happen in lineup_edit.
   */
  targetBenchGroup?: 'att' | 'mid' | 'def';
  /**
   * coach: own bench group when coaching a bench card instead of a pitch
   * slot. Mutually exclusive with `sourceSlotIndex`.
   */
  sourceBenchGroup?: 'att' | 'mid' | 'def';
  /**
   * Public announcement text, frozen the moment this ability is committed
   * (used or discarded) — but NOT published into `session.abilityActivations`
   * until the activation phase's reveal pass runs. This is what makes
   * activation hidden/simultaneous: every player's choice (and, for `sub`,
   * its board effect) is withheld from everyone else until all players have
   * locked in, then revealed together. See `_revealAbilityActivations`.
   */
  pendingSummary?: string;
}

/** A publicly-announced ability activation (shown to all players). */
export interface AbilityActivation {
  byPlayerId: string;
  byName: string;
  type: AbilityType;
  /** Public one-line summary, e.g. "Red Card on J. Stones (Omar)". */
  summary: string;
  /** Targeted user (red/yellow/sub) — lets the client compute live impact. */
  targetUserId?: string;
  /** Targeted slot in the rival's lineup (red/sub pitch targets). */
  targetSlotIndex?: number;
  /** Rival bench group when red/sub targeted a bench card. */
  targetBenchGroup?: 'att' | 'mid' | 'def';
}
