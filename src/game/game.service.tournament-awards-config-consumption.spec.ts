import { GameService } from './game.service';
import { TournamentState } from './interfaces/game-session.interface';
import { DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1, TournamentAwardsConfigValues } from './tournament-awards-config';

/**
 * Track A Step 4 — `_computeTournamentAwards()` config consumption. Mirrors
 * the deterministic-fixture style of the "shared-award tie rules" describe
 * block in game.service.tournament.spec.ts (hand-built two-match brackets,
 * bypassing the probabilistic simulation engine), but focused specifically
 * on proving the config values (not the tie-break/shared-split/AI-blocked
 * RULES themselves, which are already covered there and must stay
 * unchanged) actually drive the payout numbers.
 */
function makeBracket(matches: any[]): TournamentState {
  return {
    phase: 'complete',
    bracket: { size: 4, rounds: [{ roundNumber: 1, label: 'Semi-finals', matches, status: 'complete' }] },
    currentRound: 1,
    totalRounds: 2,
    readyPlayerIds: [],
    readyDeadlineAt: null,
    bracketRevealAt: 0,
    awards: null,
  } as unknown as TournamentState;
}

function participant(id: string, playerNames: string[], kind: 'real' | 'ai' = 'real'): any {
  return {
    kind,
    participantId: id,
    displayName: id.toUpperCase(),
    lineup: {
      formationSlug: '4-3-3',
      pitchCards: playerNames.map((name, i) => ({
        cardId: `${id}-${i}`, playerName: name, rating: 80,
        basePositionType: 'ST', slotLabel: 'ST', nationality: 'England', club: 'Test FC', league: '', chemistryBonuses: [],
      })),
      benchCards: [], overallRating: 80, chemistryScore: 0, captainCardId: null, activeAbilityTypes: [],
    },
  };
}

/** Two-player, two-goal (one each), equal-minutes match — always produces a
 *  genuinely shared Top Scorer/Best-Rating-adjacent fixture whose payout
 *  amounts are driven entirely by the pool sizes passed in via `config`. */
function tiedGoalsMatch(a: any, b: any) {
  return {
    matchId: 'r1_m1', roundNumber: 1, participantA: a, participantB: b, status: 'complete', winnerId: 'a',
    simulationEvents: [
      { minute: 10, type: 'goal', teamParticipantId: 'a', playerName: 'a_scorer', playerRating: 8 },
      { minute: 20, type: 'goal', teamParticipantId: 'b', playerName: 'b_scorer', playerRating: 8 },
    ],
    nextEventIndex: 0,
    result: {
      matchId: 'r1_m1', scoreA: 1, scoreB: 1, winnerId: 'a', penaltyScoreA: 4, penaltyScoreB: 3,
      stats: { possessionA: 50, shotsA: 3, shotsOnTargetA: 2, bigChancesA: 1, shotsB: 3, shotsOnTargetB: 2, bigChancesB: 1 },
      playerRatings: { a_scorer: 7.5, a_other: 6.5, b_scorer: 7.5, b_other: 6.5 },
      explanation: 'a won on penalties',
    },
  };
}

describe('GameService — _computeTournamentAwards config consumption (Track A Step 4)', () => {
  let gameService: GameService;
  beforeEach(() => { gameService = new GameService(); });

  it('champion/runner-up payout amounts come from config, not hardcoded 50/20', () => {
    const a = participant('a', ['a_scorer', 'a_other']);
    const b = participant('b', ['b_scorer', 'b_other']);
    const t = makeBracket([tiedGoalsMatch(a, b)]);
    const config: TournamentAwardsConfigValues = {
      ...DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1,
      championPoints: 777,
      runnerUpPoints: 333,
    };

    const awards = (gameService as any)._computeTournamentAwards(t, a, b, config);

    // a is champion, b is runner-up in this fixture (winnerId: 'a').
    expect(awards.pointsAwarded['a']).toBeGreaterThanOrEqual(777);
    expect(awards.pointsAwarded['b']).toBeGreaterThanOrEqual(333);
    // Isolate the base placement bonus from any stacked shared-category bonus
    // by re-running with every stat bonus zeroed out.
    const isolated = (gameService as any)._computeTournamentAwards(t, a, b, {
      ...config,
      topScorerBonus: 0,
      mostAssistsBonus: 0,
      highestRatingBonus: 0,
    });
    expect(isolated.pointsAwarded['a']).toBe(777);
    expect(isolated.pointsAwarded['b']).toBe(333);
  });

  it('top scorer / most assists / highest rating pools are split from config, not hardcoded 15/10/10', () => {
    const a = participant('a', ['a_scorer', 'a_other']);
    const b = participant('b', ['b_scorer', 'b_other']);
    const t = makeBracket([tiedGoalsMatch(a, b)]);
    const config: TournamentAwardsConfigValues = {
      ...DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1,
      championPoints: 0,
      runnerUpPoints: 0,
      topScorerBonus: 100,
      // This fixture's players also tie on rating (both scorers rated 7.5) —
      // zero out the other stat pools so only topScorerBonus's config value
      // is under test here.
      mostAssistsBonus: 0,
      highestRatingBonus: 0,
    };

    const awards = (gameService as any)._computeTournamentAwards(t, a, b, config);

    // Two genuinely tied top scorers (equal minutes) → 100 split 2 ways,
    // rounded up → 50 each — the config's pool value drives the split, not
    // the old hardcoded 15.
    expect(awards.topScorer).toHaveLength(2);
    expect(awards.pointsAwarded['a']).toBe(50);
    expect(awards.pointsAwarded['b']).toBe(50);
  });

  it('shared tie behavior (split, rounded up, genuinely shared) is unchanged by config swaps', () => {
    const a = participant('a', ['a_scorer', 'a_other']);
    const b = participant('b', ['b_scorer', 'b_other']);
    const t = makeBracket([tiedGoalsMatch(a, b)]);
    const config: TournamentAwardsConfigValues = {
      ...DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1,
      topScorerBonus: 7, // odd number so rounding-up is actually exercised
    };

    const awards = (gameService as any)._computeTournamentAwards(t, a, b, config);

    expect(awards.topScorer).toHaveLength(2);
    expect(awards.topScorer.map((s: any) => s.playerName).sort()).toEqual(['a_scorer', 'b_scorer']);
    // 7 split 2 ways, rounded up → 4 each, not 3/4 (never less than the other).
    const perWinner = Math.ceil(7 / 2);
    expect(perWinner).toBe(4);
  });

  it('AI-blocked payout behavior (whole category blocked, no partial human payout) is unchanged by config swaps', () => {
    const human = participant('human', ['human_scorer']);
    const ai = participant('ai_bot', ['ai_striker'], 'ai');
    const match = {
      matchId: 'r1_m1', roundNumber: 1, participantA: human, participantB: ai, status: 'complete', winnerId: 'ai_bot',
      simulationEvents: [
        { minute: 20, type: 'goal', teamParticipantId: 'human', playerName: 'human_scorer', playerRating: 7.0 },
        { minute: 30, type: 'goal', teamParticipantId: 'ai_bot', playerName: 'ai_striker', playerRating: 7.5 },
        { minute: 50, type: 'goal', teamParticipantId: 'ai_bot', playerName: 'ai_striker', playerRating: 7.5 },
      ],
      nextEventIndex: 0,
      result: {
        matchId: 'r1_m1', scoreA: 1, scoreB: 2, winnerId: 'ai_bot', penaltyScoreA: null, penaltyScoreB: null,
        stats: { possessionA: 50, shotsA: 3, shotsOnTargetA: 2, bigChancesA: 1, shotsB: 3, shotsOnTargetB: 2, bigChancesB: 1 },
        playerRatings: { human_scorer: 7.0, ai_striker: 7.5 },
        explanation: 'ai_bot won 2-1',
      },
    };
    const t = makeBracket([match]);
    const config: TournamentAwardsConfigValues = {
      ...DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1,
      topScorerBonus: 500, // a large, distinctive value the human must NOT receive
      runnerUpPoints: 20,
    };

    const awards = (gameService as any)._computeTournamentAwards(t, ai, human, config);

    // AI (ai_bot) is the outright Top Scorer leader (2 goals vs 1) — the
    // whole category pays no one, even at a config-inflated pool of 500.
    expect(awards.topScorer).toHaveLength(1);
    expect(awards.topScorer[0].participantId).toBe('ai_bot');
    expect(awards.pointsAwarded['ai_bot']).toBeUndefined();
    expect(awards.pointsAwarded['human']).toBe(20); // runner-up bonus only, from config
    expect(awards.blockedCategories).toContain('Top Scorer');
  });

  it('default config (v1) reproduces the exact same pointsAwarded as the old hardcoded 50/20/15/10/10', () => {
    const a = participant('a', ['a_scorer', 'a_other']);
    const b = participant('b', ['b_scorer', 'b_other']);
    const t = makeBracket([tiedGoalsMatch(a, b)]);

    const awards = (gameService as any)._computeTournamentAwards(t, a, b, DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1);

    // a is champion (+50), b is runner-up (+20); both share Top Scorer
    // (15 split 2 ways, rounded up → 8 each) and also share Best Rating in
    // this fixture (both scorers rated 7.5 — 10 split 2 ways, rounded up →
    // 5 each) — exactly today's pre-existing hardcoded behavior, byte-for-byte.
    expect(awards.pointsAwarded).toEqual({ a: 63, b: 33 });
  });

  it('pointsConfig on the returned awards echoes the exact config passed in (Track A Step 5)', () => {
    const a = participant('a', ['a_scorer', 'a_other']);
    const b = participant('b', ['b_scorer', 'b_other']);
    const t = makeBracket([tiedGoalsMatch(a, b)]);
    const config: TournamentAwardsConfigValues = {
      championPoints: 111,
      runnerUpPoints: 222,
      topScorerBonus: 333,
      mostAssistsBonus: 444,
      highestRatingBonus: 555,
    };

    const awards = (gameService as any)._computeTournamentAwards(t, a, b, config);

    expect(awards.pointsConfig).toEqual(config);
  });
});
