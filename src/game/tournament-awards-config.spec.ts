import { validateTournamentAwardsConfigValues, DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1 } from './tournament-awards-config';
import { TournamentAwardsConfigValues } from './tournament-awards-config';

/**
 * validateTournamentAwardsConfigValues — the publish-gating logic for
 * tournament awards config, mirroring scoring-config.spec.ts. Never run on
 * draft saves, only at publish time (see
 * AdminService.publishTournamentAwardsConfig) — these tests exercise the
 * pure function directly, independent of that wiring.
 */
describe('validateTournamentAwardsConfigValues', () => {
  it('the v1 default config is always valid', () => {
    expect(validateTournamentAwardsConfigValues(DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1)).toEqual([]);
  });

  it('rejects a negative value', () => {
    const v: TournamentAwardsConfigValues = {
      ...DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1,
      championPoints: -5,
    };
    const errors = validateTournamentAwardsConfigValues(v);
    expect(errors.some((e) => e.includes('Champion points'))).toBe(true);
  });

  it('rejects a non-integer value', () => {
    const v: TournamentAwardsConfigValues = {
      ...DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1,
      topScorerBonus: 15.5,
    };
    const errors = validateTournamentAwardsConfigValues(v);
    expect(errors.some((e) => e.includes('Top scorer bonus'))).toBe(true);
  });

  it('rejects a value above its upper bound', () => {
    const v: TournamentAwardsConfigValues = {
      ...DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1,
      runnerUpPoints: 100000,
    };
    const errors = validateTournamentAwardsConfigValues(v);
    expect(errors.some((e) => e.includes('Runner-up points'))).toBe(true);
  });

  it('accepts zero for every field (whole integers >= 0)', () => {
    const v: TournamentAwardsConfigValues = {
      championPoints: 0,
      runnerUpPoints: 0,
      topScorerBonus: 0,
      mostAssistsBonus: 0,
      highestRatingBonus: 0,
    };
    expect(validateTournamentAwardsConfigValues(v)).toEqual([]);
  });

  it('reports every violation at once, not just the first', () => {
    const v: TournamentAwardsConfigValues = {
      championPoints: -1,
      runnerUpPoints: -1,
      topScorerBonus: -1,
      mostAssistsBonus: 2.5,
      highestRatingBonus: 100000,
    };
    const errors = validateTournamentAwardsConfigValues(v);
    expect(errors.length).toBeGreaterThanOrEqual(5);
  });
});
