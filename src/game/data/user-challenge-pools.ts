/**
 * User-level chemistry challenge definitions.
 *
 * Each game player gets 5 shuffled challenges assigned at session creation.
 * Challenges 1-4 are randomly picked from the pool; challenge 5 is always
 * ALL_CHALLENGES_MET. Each satisfied challenge awards +5 to the player's score.
 */

export type UserChallengeType =
  | 'NATION_COUNT'        // ≥N players of one nationality
  | 'TWO_NATIONS_COMBO'   // ≥N of nation A AND ≥N of nation B
  | 'CLUB_COUNT'          // ≥N players from one club
  | 'TWO_CLUBS_COMBO'     // ≥1 of club A AND ≥1 of club B
  | 'LEAGUE_COUNT'        // ≥N players from one league
  | 'TWO_LEAGUES_COMBO'   // ≥N from league A AND ≥N from league B
  | 'NATION_AND_CLUB'     // ≥N players who share BOTH a nation AND club
  | 'POSITION_GROUP'      // ≥N players in DEF/MID/ATK
  | 'ALL_CHALLENGES_MET'; // bonus when all 4 other challenges are satisfied

export interface UserChemistryChallenge {
  type: UserChallengeType;
  params: Record<string, unknown>;
  label: string;
  reward: number; // always 5
}
