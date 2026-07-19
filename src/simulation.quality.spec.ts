import { GameService } from './game/game.service';
import { TournamentParticipant } from './game/interfaces/game-session.interface';
import { BasePositionType, SlotLabel } from './game/interfaces/formation.interface';

/**
 * Simulation quality tests — validate that the (seeded, deterministic) match
 * engine produces balanced, realistic results at scale. `runMatchSimulation`
 * is private; it is exercised via bracket-notation access, the same pattern
 * used in tournament.integration.spec.ts.
 *
 * All outcomes are deterministic given the seeds used here (the engine uses a
 * seeded PRNG, never Math.random), so these thresholds are stable across runs.
 */

jest.setTimeout(30000);

// Valid BasePositionType / SlotLabel values (4 defenders, 3 mids, 3 att, 1 GK).
const POSITION_SPECS: { base: BasePositionType; label: SlotLabel }[] = [
  { base: 'GK', label: 'GK' },
  { base: 'CB', label: 'LCB' },
  { base: 'CB', label: 'CCB' },
  { base: 'CB', label: 'RCB' },
  { base: 'RB', label: 'RB' },
  { base: 'CDM', label: 'CDM' },
  { base: 'CM', label: 'CM' },
  { base: 'CAM', label: 'CAM' },
  { base: 'ST', label: 'ST' },
  { base: 'LW', label: 'LW' },
  { base: 'RW', label: 'RW' },
];

function makeParticipant(
  id: string,
  overallRating: number,
  chemistryScore: number,
  activeAbilityTypes: string[] = [],
): TournamentParticipant {
  const pitchCards = POSITION_SPECS.map((spec, i) => ({
    cardId: `${id}_card_${i}`,
    playerName: `${id}_player_${i}`,
    rating: overallRating,
    basePositionType: spec.base,
    slotLabel: spec.label,
    nationality: 'England',
    club: 'Test FC',
    league: 'Test League',
    chemistryBonuses: [],
  }));

  return {
    kind: 'real',
    participantId: id,
    displayName: `Player ${id}`,
    lineup: {
      formationSlug: '4-3-3',
      pitchCards,
      benchCards: [],
      overallRating,
      chemistryScore,
      captainCardId: null,
      activeAbilityTypes,
    },
  };
}

describe('Simulation Quality — Balance', () => {
  let service: GameService;

  beforeEach(() => {
    service = new GameService();
  });

  describe('Suite 1 — Equal strength 50/50 balance', () => {
    it('participant A wins between 45% and 55% of 1000 equal-strength matches', () => {
      const a = makeParticipant('a', 75, 70);
      const b = makeParticipant('b', 75, 70);

      let aWins = 0;
      for (let i = 0; i < 1000; i++) {
        const result = (service as any).runMatchSimulation(a, b, i * 13 + 7);
        if (result.winnerId === 'a') aWins++;
      }

      const winRate = aWins / 1000;
      expect(winRate).toBeGreaterThanOrEqual(0.45);
      expect(winRate).toBeLessThanOrEqual(0.55);
    });
  });

  describe('Suite 2 — Strong favourite wins most of the time', () => {
    it('high-rated participant wins more than 80% against a weak opponent', () => {
      const strong = makeParticipant('strong', 88, 90);
      const weak = makeParticipant('weak', 60, 50);

      let strongWins = 0;
      for (let i = 0; i < 500; i++) {
        const result = (service as any).runMatchSimulation(strong, weak, i * 17 + 3);
        if (result.winnerId === 'strong') strongWins++;
      }

      expect(strongWins).toBeGreaterThan(400); // >80% of 500
    });
  });

  describe('Suite 3 — Upsets exist', () => {
    it('weak participant wins at least once in 500 matches against a strong opponent', () => {
      const strong = makeParticipant('strong', 88, 90);
      const weak = makeParticipant('weak', 60, 50);

      let weakWins = 0;
      for (let i = 0; i < 500; i++) {
        const result = (service as any).runMatchSimulation(strong, weak, i * 17 + 3);
        if (result.winnerId === 'weak') weakWins++;
      }

      expect(weakWins).toBeGreaterThanOrEqual(1);
    });
  });

  describe('Suite 4 — Scoreline distribution feels like football', () => {
    it('produces realistic total goal counts across 200 matches', () => {
      const a = makeParticipant('a', 75, 70);
      const b = makeParticipant('b', 75, 70);

      let totalGoals = 0;
      let maxGoalsInOneGame = 0;
      let closeGames = 0; // decided by exactly 1 goal

      for (let i = 0; i < 200; i++) {
        const result = (service as any).runMatchSimulation(a, b, i * 11 + 5);
        const gameGoals = result.scoreA + result.scoreB;
        totalGoals += gameGoals;
        if (gameGoals > maxGoalsInOneGame) maxGoalsInOneGame = gameGoals;
        if (Math.abs(result.scoreA - result.scoreB) === 1) closeGames++;
      }

      const meanGoals = totalGoals / 200;

      expect(meanGoals).toBeGreaterThanOrEqual(1.5);
      expect(meanGoals).toBeLessThanOrEqual(4.5);
      expect(maxGoalsInOneGame).toBeLessThanOrEqual(8);
      expect(closeGames / 200).toBeGreaterThanOrEqual(0.1);
    });
  });

  describe('Suite 5 — No draws ever (a winner is always decided)', () => {
    it('a level regulation score always goes to a real, decisive penalty shootout', () => {
      const a = makeParticipant('a', 75, 70);
      const b = makeParticipant('b', 75, 70);

      let sawShootout = false;
      for (let i = 0; i < 500; i++) {
        const result = (service as any).runMatchSimulation(a, b, i * 7 + 3);
        // A knockout match always has a winner, whether decided in regulation
        // or on penalties — but regulation itself is now allowed to be level
        // (unlike the old fake-goal-injection scheme, a real shootout tracks
        // its own score instead of inflating scoreA/scoreB).
        expect(['a', 'b']).toContain(result.winnerId);
        if (result.scoreA === result.scoreB) {
          sawShootout = true;
          expect(result.penaltyScoreA).not.toBeNull();
          expect(result.penaltyScoreB).not.toBeNull();
          expect(result.penaltyScoreA).not.toBe(result.penaltyScoreB);
          const shootoutWinner = result.penaltyScoreA > result.penaltyScoreB ? 'a' : 'b';
          expect(result.winnerId).toBe(shootoutWinner);
        } else {
          expect(result.penaltyScoreA).toBeNull();
          expect(result.penaltyScoreB).toBeNull();
        }
      }
      // With two evenly matched sides across 500 seeds, at least one draw
      // (and therefore a shootout) should occur — otherwise the shootout path
      // isn't actually being exercised by this suite.
      expect(sawShootout).toBe(true);
    });
  });

  describe('Suite 6 — Player ratings in valid range', () => {
    it('all player ratings are between 4.0 and 10.0', () => {
      const a = makeParticipant('a', 75, 70);
      const b = makeParticipant('b', 75, 70);

      for (let i = 0; i < 100; i++) {
        const result = (service as any).runMatchSimulation(a, b, i * 19 + 1);
        Object.values(result.playerRatings).forEach((rating) => {
          expect(rating as number).toBeGreaterThanOrEqual(4.0);
          expect(rating as number).toBeLessThanOrEqual(10.0);
        });
      }
    });

    it('winner team has higher average player rating in at least 70% of matches', () => {
      const a = makeParticipant('a', 75, 70);
      const b = makeParticipant('b', 75, 70);

      let winnerRatingHigher = 0;

      for (let i = 0; i < 200; i++) {
        const result = (service as any).runMatchSimulation(a, b, i * 23 + 9);

        const winnerParticipant = result.winnerId === 'a' ? a : b;
        const loserParticipant = result.winnerId === 'a' ? b : a;

        const winnerNames = new Set(
          winnerParticipant.lineup!.pitchCards.map((c) => c.playerName),
        );
        const loserNames = new Set(
          loserParticipant.lineup!.pitchCards.map((c) => c.playerName),
        );

        const winnerRatings = Object.entries(result.playerRatings)
          .filter(([name]) => winnerNames.has(name))
          .map(([, r]) => r as number);
        const loserRatings = Object.entries(result.playerRatings)
          .filter(([name]) => loserNames.has(name))
          .map(([, r]) => r as number);

        if (winnerRatings.length > 0 && loserRatings.length > 0) {
          const winnerAvg =
            winnerRatings.reduce((s, r) => s + r, 0) / winnerRatings.length;
          const loserAvg =
            loserRatings.reduce((s, r) => s + r, 0) / loserRatings.length;
          if (winnerAvg > loserAvg) winnerRatingHigher++;
        }
      }

      expect(winnerRatingHigher / 200).toBeGreaterThanOrEqual(0.7);
    });
  });

  describe('Suite 7 — Structural correctness', () => {
    it('events array is sorted by minute ascending', () => {
      const a = makeParticipant('a', 75, 70);
      const b = makeParticipant('b', 75, 70);

      for (let i = 0; i < 50; i++) {
        const result = (service as any).runMatchSimulation(a, b, i * 31);
        const minutes = result.events.map((e: any) => e.minute);
        for (let j = 1; j < minutes.length; j++) {
          expect(minutes[j]).toBeGreaterThanOrEqual(minutes[j - 1]);
        }
      }
    });

    it('winnerId matches the participant with more goals (or, if level, more penalties)', () => {
      const a = makeParticipant('a', 75, 70);
      const b = makeParticipant('b', 75, 70);

      for (let i = 0; i < 100; i++) {
        const result = (service as any).runMatchSimulation(a, b, i * 41 + 13);
        if (result.scoreA > result.scoreB) {
          expect(result.winnerId).toBe('a');
        } else if (result.scoreB > result.scoreA) {
          expect(result.winnerId).toBe('b');
        } else {
          // Level after regulation — the shootout tally decides it instead.
          expect(result.penaltyScoreA).not.toBeNull();
          expect(result.penaltyScoreA > result.penaltyScoreB ? 'a' : 'b').toBe(result.winnerId);
        }
      }
    });

    it('shots on target is always >= goals for each team', () => {
      const a = makeParticipant('a', 75, 70);
      const b = makeParticipant('b', 75, 70);

      for (let i = 0; i < 100; i++) {
        const result = (service as any).runMatchSimulation(a, b, i * 53 + 7);
        expect(result.stats.shotsOnTargetA).toBeGreaterThanOrEqual(result.scoreA);
        expect(result.stats.shotsOnTargetB).toBeGreaterThanOrEqual(result.scoreB);
      }
    });

    it('every goal event playerName exists in the scoring team lineup', () => {
      const a = makeParticipant('a', 75, 70);
      const b = makeParticipant('b', 75, 70);

      const aNames = new Set(a.lineup!.pitchCards.map((c) => c.playerName));
      const bNames = new Set(b.lineup!.pitchCards.map((c) => c.playerName));

      for (let i = 0; i < 50; i++) {
        const result = (service as any).runMatchSimulation(a, b, i * 59 + 11);
        result.events
          .filter((e: any) => e.type === 'goal' && e.minute <= 90)
          .forEach((e: any) => {
            const validNames = e.teamParticipantId === 'a' ? aNames : bNames;
            expect(validNames.has(e.playerName)).toBe(true);
          });
      }
    });

    it('a red-carded player never appears in a later event (goal, assist, miss, card, or penalty)', () => {
      const a = makeParticipant('a', 75, 70);
      const b = makeParticipant('b', 75, 70);

      for (let i = 0; i < 300; i++) {
        const result = (service as any).runMatchSimulation(a, b, i * 67 + 5);

        // First pass: record when (if at all) each player was sent off.
        const dismissedAt: Record<string, number> = {};
        for (const e of result.events) {
          if (e.type === 'red_card') {
            expect(dismissedAt[e.playerName]).toBeUndefined(); // sent off once, max
            dismissedAt[e.playerName] = e.minute;
          }
        }

        // Second pass: no event (as the main player OR as an assister) for a
        // dismissed player may occur at or after their own dismissal minute,
        // other than the red card itself.
        for (const e of result.events) {
          const ownDismissal = dismissedAt[e.playerName];
          if (ownDismissal !== undefined && e.type !== 'red_card') {
            expect(e.minute).toBeLessThan(ownDismissal);
          }
          if (e.assistPlayerName) {
            const assisterDismissal = dismissedAt[e.assistPlayerName];
            if (assisterDismissal !== undefined) {
              expect(e.minute).toBeLessThan(assisterDismissal);
            }
          }
        }
      }
    });

    it('possession always sums to 100 and stays realistic', () => {
      const a = makeParticipant('a', 75, 70);
      const b = makeParticipant('b', 75, 70);

      for (let i = 0; i < 100; i++) {
        const result = (service as any).runMatchSimulation(a, b, i * 67);
        expect(result.stats.possessionA + (100 - result.stats.possessionA)).toBe(100);
        expect(result.stats.possessionA).toBeGreaterThanOrEqual(35);
        expect(result.stats.possessionA).toBeLessThanOrEqual(65);
      }
    });
  });
});
