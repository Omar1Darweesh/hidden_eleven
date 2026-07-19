/**
 * Server-outbound tournament event payload shapes. These are NOT validated DTOs
 * (the server constructs them, clients only receive them) — they are plain
 * TypeScript interfaces documenting exactly what each `tournament_*` event
 * carries. The client-safe bracket snapshot deliberately omits the server-only
 * `simulationEvents` / `nextEventIndex` fields that live on `TournamentMatch`.
 */
import {
  TournamentPhase,
  MatchEvent,
  MatchStats,
  TournamentStatLeader,
} from '../../game/interfaces/game-session.interface';
import { TournamentAwardsConfigValues } from '../../game/tournament-awards-config';

export interface ParticipantSnapshot {
  kind: 'real' | 'ai';
  participantId: string;
  displayName: string;
  overallRating: number;
  /** Club badge URL — populated for AI participants when the pool has one. */
  clubLogoUrl?: string;
}

export interface CompletedMatchSnapshot {
  scoreA: number;
  scoreB: number;
  /** Null unless the match was drawn after regulation and went to penalties. */
  penaltyScoreA: number | null;
  penaltyScoreB: number | null;
  stats: MatchStats;
  explanation: string;
}

export interface MatchSnapshot {
  matchId: string;
  roundNumber: number;
  participantA: ParticipantSnapshot;
  participantB: ParticipantSnapshot;
  status: 'pending' | 'ready_check' | 'simulating' | 'complete';
  result: CompletedMatchSnapshot | null;
  winnerId: string | null;
}

export interface RoundSnapshot {
  roundNumber: number;
  label: string;
  status: 'pending' | 'in_progress' | 'complete';
  matches: MatchSnapshot[];
}

export interface BracketSnapshot {
  size: 4 | 8 | 16;
  rounds: RoundSnapshot[];
}

export interface TournamentAwardsSnapshot {
  champion: ParticipantSnapshot;
  runnerUp: ParticipantSnapshot;
  /** May contain more than one entry — a genuinely tied award is SHARED. */
  topScorer: (TournamentStatLeader & { goals: number })[];
  mostAssists: (TournamentStatLeader & { assists: number })[];
  topContributions: (TournamentStatLeader & { goals: number; assists: number; contributions: number })[];
  /** Per-player award — the individual with the highest average match rating. */
  highestAvgRating: (TournamentStatLeader & { avgRating: number })[];
  /** Credited to the actual goalkeeper, never the participant/team name. */
  cleanSheets: (TournamentStatLeader & { cleanSheets: number })[];
  pointsAwarded: Record<string, number>;
  /** Category labels where an AI leader blocked the bonus from any human. */
  blockedCategories: string[];
  /** The exact config values used to compute this result — see the server's
   *  TournamentAwards.pointsConfig doc comment. */
  pointsConfig: TournamentAwardsConfigValues;
}

/** The main state push — like `game_state` is for the draft. */
export interface TournamentStatePayload {
  phase: TournamentPhase;
  currentRound: number;
  totalRounds: number;
  readyPlayerIds: string[];
  readyDeadlineAt: number | null;
  bracketRevealAt: number | null;
  bracket: BracketSnapshot;
  awards: TournamentAwardsSnapshot | null;
}

/** One live simulation event during the `simulating` phase. */
export interface TournamentMatchEventPayload {
  matchId: string;
  roundNumber: number;
  event: MatchEvent;
  currentScoreA: number;
  currentScoreB: number;
}

/** The full result of one match, sent once when its event stream ends. */
export interface TournamentMatchResultPayload {
  matchId: string;
  roundNumber: number;
  scoreA: number;
  scoreB: number;
  winnerId: string;
  penaltyScoreA: number | null;
  penaltyScoreB: number | null;
  stats: MatchStats;
  playerRatings: Record<string, number>;
  explanation: string;
}

/** The final tournament result (champion, awards, points). */
export interface TournamentCompletePayload {
  champion: ParticipantSnapshot;
  runnerUp: ParticipantSnapshot;
  topScorer: (TournamentStatLeader & { goals: number })[];
  mostAssists: (TournamentStatLeader & { assists: number })[];
  topContributions: (TournamentStatLeader & { goals: number; assists: number; contributions: number })[];
  highestAvgRating: (TournamentStatLeader & { avgRating: number })[];
  cleanSheets: (TournamentStatLeader & { cleanSheets: number })[];
  pointsAwarded: Record<string, number>;
  blockedCategories: string[];
  /** The exact config values used to compute this result — see the server's
   *  TournamentAwards.pointsConfig doc comment. */
  pointsConfig: TournamentAwardsConfigValues;
  finalMatch: CompletedMatchSnapshot;
}

/** Cosmetic notice that a participant was auto-readied (AI or 60s timeout). */
export interface TournamentAutoReadyPayload {
  participantId: string;
  reason: 'ai' | 'timeout';
}
