import { validateScoringConfigValues, DEFAULT_SCORING_CONFIG_V1 } from './scoring-config';
import { ScoringConfigValues } from './scoring-config';

/**
 * validateScoringConfigValues — the one piece of real, publish-gating logic
 * added in Phase C. Never run on draft saves, only at publish time (see
 * AdminService.publishScoringConfig) — these tests exercise the pure
 * function directly, independent of that wiring.
 */
describe('validateScoringConfigValues', () => {
  it('the v1 default config is always valid', () => {
    expect(validateScoringConfigValues(DEFAULT_SCORING_CONFIG_V1)).toEqual([]);
  });

  it('rejects a negative value', () => {
    const v: ScoringConfigValues = {
      ...DEFAULT_SCORING_CONFIG_V1,
      abilityEffects: { ...DEFAULT_SCORING_CONFIG_V1.abilityEffects, yellowPenalty: -5 },
    };
    const errors = validateScoringConfigValues(v);
    expect(errors.some((e) => e.includes('Yellow card penalty'))).toBe(true);
  });

  it('rejects a non-integer value', () => {
    const v: ScoringConfigValues = {
      ...DEFAULT_SCORING_CONFIG_V1,
      lineLeader: { bonusPerLine: 2.5 },
    };
    const errors = validateScoringConfigValues(v);
    expect(errors.some((e) => e.includes('Line Leader bonus per line'))).toBe(true);
  });

  it('rejects a value above its upper bound', () => {
    const v: ScoringConfigValues = {
      ...DEFAULT_SCORING_CONFIG_V1,
      userChallenges: { rewardPerChallenge: 100000 },
    };
    const errors = validateScoringConfigValues(v);
    expect(errors.some((e) => e.includes('User challenge reward'))).toBe(true);
  });

  it('rejects captainMultiplier below 1 (must always at least count the card once)', () => {
    const v: ScoringConfigValues = {
      ...DEFAULT_SCORING_CONFIG_V1,
      abilityEffects: { ...DEFAULT_SCORING_CONFIG_V1.abilityEffects, captainMultiplier: 0 },
    };
    const errors = validateScoringConfigValues(v);
    expect(errors.some((e) => e.includes('Captain multiplier'))).toBe(true);
  });

  it('rejects tier rewards that are not non-decreasing (hard < easy)', () => {
    const v: ScoringConfigValues = {
      ...DEFAULT_SCORING_CONFIG_V1,
      cardChemistry: {
        ...DEFAULT_SCORING_CONFIG_V1.cardChemistry,
        tierRewards: { easy: 10, medium: 4, hard: 2 },
      },
    };
    const errors = validateScoringConfigValues(v);
    expect(errors.some((e) => e.includes('non-decreasing'))).toBe(true);
  });

  it('accepts equal tier rewards (non-decreasing allows ties)', () => {
    const v: ScoringConfigValues = {
      ...DEFAULT_SCORING_CONFIG_V1,
      cardChemistry: {
        ...DEFAULT_SCORING_CONFIG_V1.cardChemistry,
        tierRewards: { easy: 5, medium: 5, hard: 5 },
      },
    };
    expect(validateScoringConfigValues(v)).toEqual([]);
  });

  it('reports every violation at once, not just the first', () => {
    const v: ScoringConfigValues = {
      ...DEFAULT_SCORING_CONFIG_V1,
      abilityEffects: { yellowPenalty: -1, captainMultiplier: -1 },
      lineLeader: { bonusPerLine: -1 },
    };
    const errors = validateScoringConfigValues(v);
    expect(errors.length).toBeGreaterThanOrEqual(3);
  });
});
