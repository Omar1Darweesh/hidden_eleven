/**
 * Admin-configurable tournament awards values — Track A Step 1 (server config
 * engine only, no gameplay wiring yet).
 *
 * Mirrors scoring-config.ts's shape and conventions exactly. This file
 * defines the config shape and the exact v1 defaults, which MUST equal
 * today's pre-existing hardcoded tournament award constants byte-for-byte —
 * publishing v1 must change no gameplay behavior at all. See
 * GameService._computeTournamentAwards for where these values currently
 * live hardcoded (TOP_SCORER_BONUS/MOST_ASSISTS_BONUS/HIGHEST_RATING_BONUS
 * locals, and the inline 50/20 champion/runner-up literals).
 */

export interface TournamentAwardsConfigValues {
  /** Points for winning the tournament. Was: inline literal 50 (game.service.ts _computeTournamentAwards). */
  championPoints: number;
  /** Points for losing the final. Was: inline literal 20 (game.service.ts _computeTournamentAwards). */
  runnerUpPoints: number;
  /** Points for the tournament's top scorer (shared: split, rounded UP, equally). Was: TOP_SCORER_BONUS = 15. */
  topScorerBonus: number;
  /** Points for the tournament's most assists (shared: split, rounded UP, equally). Was: MOST_ASSISTS_BONUS = 10. */
  mostAssistsBonus: number;
  /** Points for the tournament's highest average rating (shared: split, rounded UP, equally). Was: HIGHEST_RATING_BONUS = 10. */
  highestRatingBonus: number;
}

export interface TournamentAwardsConfigVersion {
  version: number;
  status: 'draft' | 'published';
  createdAt: string;
  publishedAt?: string;
  note?: string;
  values: TournamentAwardsConfigValues;
}

/** On-disk shape of admin-data/tournament-awards-config.json. */
export interface TournamentAwardsConfigFile {
  draft: TournamentAwardsConfigVersion;
  published: TournamentAwardsConfigVersion;
  history: TournamentAwardsConfigVersion[];
}

/**
 * v1 — exactly today's hardcoded values. Never edit these numbers to "fix"
 * behavior; that's what publishing a new version is for (a later phase).
 * This constant is (a) the seed for a fresh tournament-awards-config.json and
 * (b) the fallback value the snapshot wiring would use if the file is
 * missing/unreadable — both cases must reproduce today's exact tournament
 * award payouts, unchanged.
 */
export const DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1: TournamentAwardsConfigValues = {
  championPoints: 50,
  runnerUpPoints: 20,
  topScorerBonus: 15,
  mostAssistsBonus: 10,
  highestRatingBonus: 10,
};

// ── Publish-time validation ─────────────────────────────────────────────────
//
// Only ever run when PUBLISHING a draft (see
// AdminService.publishTournamentAwardsConfig) — saving a draft is never
// validated, since it has no gameplay effect until published. Returns every
// violation found (not just the first) so the admin UI can show a complete
// list in one round trip, and never throws itself — callers decide what to
// do with a non-empty result (the admin service turns it into a
// BadRequestException).

function checkNonNegativeInt(errors: string[], label: string, n: unknown, max: number): void {
  if (typeof n !== 'number' || !Number.isInteger(n)) {
    errors.push(`${label} must be a whole number.`);
    return;
  }
  if (n < 0 || n > max) {
    errors.push(`${label} must be between 0 and ${max}.`);
  }
}

export function validateTournamentAwardsConfigValues(v: TournamentAwardsConfigValues): string[] {
  const errors: string[] = [];

  checkNonNegativeInt(errors, 'Champion points', v?.championPoints, 999);
  checkNonNegativeInt(errors, 'Runner-up points', v?.runnerUpPoints, 999);
  checkNonNegativeInt(errors, 'Top scorer bonus', v?.topScorerBonus, 999);
  checkNonNegativeInt(errors, 'Most assists bonus', v?.mostAssistsBonus, 999);
  checkNonNegativeInt(errors, 'Highest rating bonus', v?.highestRatingBonus, 999);

  return errors;
}
