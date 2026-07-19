import type { TournamentAwards } from './game-session.interface';

export type GameEndReason = 'completed' | 'forfeit' | 'abandoned';

/** One line item in a ScoreBreakdown's itemized explanation (see `lines`). */
export interface ScoreBreakdownLine {
  key: string;
  label: string;
  /** Signed; penalties are negative. */
  amount: number;
  detail?: string;
}

export interface ScoreBreakdown {
  /** Average rating of GK + defensive line (rounded integer) */
  defAvg: number;
  /** Average rating of midfield line (rounded integer) */
  midAvg: number;
  /** Average rating of attacking line (rounded integer) */
  atkAvg: number;
  /** Sum of the three line averages: defAvg + midAvg + atkAvg */
  linesTotal: number;
  /** Total from user-level chemistry challenges (admin-configurable reward per challenge) */
  userChemTotal: number;
  /** Total from per-card tiered challenges (admin-configurable reward per tier) */
  cardChemTotal: number;
  /** Admin-configurable bonus per line for the highest-rated card in DEF (incl. GK), MID, ATK */
  lineLeaderBonus: number;
  /** Extra card-chem from a Captain card (0 if none). */
  captainBonus?: number;
  /** Points docked by Yellow card(s) aimed at this player (0 if none). */
  yellowPenalty?: number;
  /** True if a Red card disabled one of this player's cards' chemistry. */
  redApplied?: boolean;
  /** linesTotal + userChemTotal + cardChemTotal + captainBonus + lineLeaderBonus − yellowPenalty */
  finalScore: number;
  /** Which published scoring-config version scored this game (see scoring-config.ts). 0 = not applicable (e.g. emptyBreakdown()). */
  scoringConfigVersion: number;
  /**
   * Itemized, human-readable explanation of finalScore — the same source of
   * truth as the scalar fields above. Not yet rendered by any client UI.
   */
  lines: ScoreBreakdownLine[];
}

export interface PlayerResult {
  playerId: string;
  displayName: string;
  rank: number;
  score: number | null;
  /** Full breakdown included at game end; null for partial/legacy results */
  scoreBreakdown?: ScoreBreakdown;
}

export interface GameResult {
  reason: GameEndReason;
  players: PlayerResult[];
  /** Present when a tournament was played; carries the end-of-tournament awards. */
  tournament?: TournamentAwards;
}
