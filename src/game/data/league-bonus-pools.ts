/**
 * Per-card chemistry challenge definitions.
 *
 * Every player card carries exactly 3 chemistry challenges graded by tier
 * (easy/medium/hard). The reward per tier is admin-configurable — see
 * ScoringConfigValues.cardChemistry.tierRewards (scoring-config.ts) — and is
 * plugged in by ChemistryShuffleService at cache-build time, not hardcoded
 * here.
 *
 * Each challenge is derived from the player's own data (league / club / nation /
 * position) by the ChemistryShuffleService — see chemistry-shuffle.ts.
 */

export type ChemistryBonusType =
  | 'SAME_CLUB'           // ≥N players from this player's club
  | 'SAME_NATION'         // ≥N players sharing this player's nationality
  | 'SAME_LEAGUE'         // ≥N players from this player's league
  | 'POSITION_GROUP'      // ≥N players in this player's position group (DEF/MID/ATK)
  | 'CLUB_AND_POSITION'   // ≥X from club AND ≥Y in position group
  | 'NATION_AND_POSITION'; // ≥X from nation AND ≥Y in position group

export type ChemistryTier = 'easy' | 'medium' | 'hard';

export interface ChemistryBonus {
  /** Difficulty tier — drives the reward. */
  tier: ChemistryTier;
  /** Points awarded when satisfied: 2 (easy) / 4 (medium) / 6 (hard). */
  reward: number;
  type: ChemistryBonusType;
  params: Record<string, unknown>;
  label: string;
}

// ── Position groups used by POSITION_GROUP / *_AND_POSITION challenges ─────────

export const POSITION_GROUPS: Record<string, string[]> = {
  DEF: ['GK', 'LB', 'CB', 'RB'],
  MID: ['CDM', 'CM', 'CAM', 'LM', 'RM'],
  ATK: ['LW', 'RW', 'CF', 'ST'],
};
