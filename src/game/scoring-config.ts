/**
 * Admin-configurable scoring/chemistry values — Phase A (numeric-only).
 *
 * See "Chemistry Scoring — Admin-Configurable Design Spec" for the full
 * design and its implementation plan. This file defines the config shape and
 * the exact v1 defaults, which MUST equal today's pre-existing hardcoded
 * scoring constants byte-for-byte — publishing v1 must change no gameplay
 * behavior at all. Every field below cites where that value used to live.
 */

export interface ScoringConfigValues {
  userChallenges: {
    /** Points per satisfied user-level challenge. Was: flat 5 for all 9 challenge types (user-challenge-shuffle.ts). */
    rewardPerChallenge: number;
  };
  cardChemistry: {
    /** Points per per-card tier. Was: league-bonus-pools.ts TIER_REWARD. */
    tierRewards: { easy: number; medium: number; hard: number };
    /**
     * Fallback thresholds used only when a ChemistryBonus's own `params`
     * doesn't carry an explicit count — chemistry-shuffle.ts always sets one
     * explicitly today, so in practice these are a safety net, not an active
     * tuning knob, in v1. Was: evaluateCardBonus's `?? N` literals (scoring.ts).
     */
    thresholds: {
      sameClubCount: number;
      sameNationCount: number;
      sameLeagueCount: number;
      positionGroupCount: number;
      clubAndPositionClubCount: number;
      clubAndPositionGroupCount: number;
      nationAndPositionNationCount: number;
      nationAndPositionGroupCount: number;
    };
  };
  lineLeader: {
    /** Points per line won (DEF/MID/ATK). Was: flat 2 (scoring.ts computeLineLeaderAwards). */
    bonusPerLine: number;
  };
  abilityEffects: {
    /** Points docked per Yellow card activation. Was: flat 20 (scoring.ts extractAbilityEffects). */
    yellowPenalty: number;
    /** Multiplier applied to a Captain's card-chem. Was: implicit 2x "doubling" (scoring.ts computeCardChemWithCaptain). */
    captainMultiplier: number;
  };
}

export interface ScoringConfigVersion {
  version: number;
  status: 'draft' | 'published';
  createdAt: string;
  publishedAt?: string;
  note?: string;
  values: ScoringConfigValues;
}

/** On-disk shape of admin-data/scoring-config.json. */
export interface ScoringConfigFile {
  draft: ScoringConfigVersion;
  published: ScoringConfigVersion;
  history: ScoringConfigVersion[];
}

/**
 * v1 — exactly today's hardcoded values. Never edit these numbers to "fix"
 * behavior; that's what publishing a new version is for (a later phase).
 * This constant is (a) the seed for a fresh scoring-config.json and (b) the
 * fallback a session snapshots if the file is missing/unreadable/absent from
 * a hand-built test fixture at scoring time — both cases must reproduce
 * today's exact scoring, unchanged.
 */
export const DEFAULT_SCORING_CONFIG_V1: ScoringConfigValues = {
  userChallenges: { rewardPerChallenge: 5 },
  cardChemistry: {
    tierRewards: { easy: 2, medium: 4, hard: 6 },
    thresholds: {
      sameClubCount: 2,
      sameNationCount: 2,
      sameLeagueCount: 3,
      positionGroupCount: 2,
      clubAndPositionClubCount: 2,
      clubAndPositionGroupCount: 2,
      nationAndPositionNationCount: 2,
      nationAndPositionGroupCount: 2,
    },
  },
  lineLeader: { bonusPerLine: 2 },
  abilityEffects: { yellowPenalty: 20, captainMultiplier: 2 },
};

// ── Publish-time validation (Phase C) ──────────────────────────────────────────
//
// Only ever run when PUBLISHING a draft (see AdminService.publishScoringConfig)
// — saving a draft is never validated, since it has no gameplay effect until
// published. Returns every violation found (not just the first) so the admin
// UI can show a complete list in one round trip, and never throws itself —
// callers decide what to do with a non-empty result (the admin service turns
// it into a BadRequestException).

function checkRange(
  errors: string[],
  label: string,
  n: unknown,
  min: number,
  max: number,
): void {
  if (typeof n !== 'number' || !Number.isInteger(n)) {
    errors.push(`${label} must be a whole number.`);
    return;
  }
  if (n < min || n > max) {
    errors.push(`${label} must be between ${min} and ${max}.`);
  }
}

export function validateScoringConfigValues(v: ScoringConfigValues): string[] {
  const errors: string[] = [];

  checkRange(errors, 'User challenge reward', v?.userChallenges?.rewardPerChallenge, 0, 999);

  const tiers = v?.cardChemistry?.tierRewards;
  checkRange(errors, 'Easy tier reward', tiers?.easy, 0, 999);
  checkRange(errors, 'Medium tier reward', tiers?.medium, 0, 999);
  checkRange(errors, 'Hard tier reward', tiers?.hard, 0, 999);
  if (
    typeof tiers?.easy === 'number' &&
    typeof tiers?.medium === 'number' &&
    typeof tiers?.hard === 'number' &&
    !(tiers.easy <= tiers.medium && tiers.medium <= tiers.hard)
  ) {
    errors.push('Tier rewards must be non-decreasing: easy ≤ medium ≤ hard.');
  }

  const t = v?.cardChemistry?.thresholds;
  checkRange(errors, 'Same club threshold', t?.sameClubCount, 0, 99);
  checkRange(errors, 'Same nation threshold', t?.sameNationCount, 0, 99);
  checkRange(errors, 'Same league threshold', t?.sameLeagueCount, 0, 99);
  checkRange(errors, 'Position group threshold', t?.positionGroupCount, 0, 99);
  checkRange(errors, 'Club+position club threshold', t?.clubAndPositionClubCount, 0, 99);
  checkRange(errors, 'Club+position group threshold', t?.clubAndPositionGroupCount, 0, 99);
  checkRange(errors, 'Nation+position nation threshold', t?.nationAndPositionNationCount, 0, 99);
  checkRange(errors, 'Nation+position group threshold', t?.nationAndPositionGroupCount, 0, 99);

  checkRange(errors, 'Line Leader bonus per line', v?.lineLeader?.bonusPerLine, 0, 999);

  checkRange(errors, 'Yellow card penalty', v?.abilityEffects?.yellowPenalty, 0, 999);
  checkRange(errors, 'Captain multiplier', v?.abilityEffects?.captainMultiplier, 1, 10);

  return errors;
}
