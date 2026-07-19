import { Formation, SlotLabel, BasePositionType } from './formation.interface';
import { DraftCard } from './draft-card.interface';
import { Pitch } from './pitch.interface';
import { GameResult } from './game-result.interface';
import { SimulationSpeed } from '../../rooms/interfaces/room.interface';
import { ChemistryBonus } from '../data/league-bonus-pools.js';
import { UserChemistryChallenge } from '../data/user-challenge-pools.js';
import { ScoringConfigValues } from '../scoring-config.js';
import { TournamentAwardsConfigValues } from '../tournament-awards-config.js';
import {
  AbilityDraftState,
  PlayerAbility,
  AbilityActivation,
} from './ability.interface.js';

export type TurnPhase =
  | 'selecting_position'
  | 'selecting_card'
  | 'first_player_order'    // first player orders remaining cards after their pick
  | 'hidden_pick'           // subsequent players pick face-down slots
  | 'hidden_pick_reveal';   // brief reveal window after each hidden pick before turn advances
export type GameStatus =
  | 'waiting'
  | 'ability_draft' // face-down ability pick, before the player draft
  | 'drafting'
  // Track B reordered flow: drafting -> bench_selection -> ability_activation
  // -> lineup_edit -> tournament/finished. bench_selection and lineup_edit
  // are two halves of what used to be a single 'subs' phase — see
  // GameSession.subsPhase's doc comment for why they still share one
  // underlying SubsPhase/UserSubstitutions structure.
  | 'bench_selection' // choose 3 (att/mid/def) bench players via spin/pick — no free swapping yet
  | 'ability_activation' // use/discard abilities, after bench selection, before lineup editing
  | 'lineup_edit' // free swap pitch<->bench, Extra Bench's bonus spin/pick, and final confirmLineup
  | 'tournament' // knockout tournament, after lineup_edit, before finished (tournament mode only)
  | 'finished';

export type SubPositionGroup = 'att' | 'mid' | 'def' | 'extra';

/** One end of a free "swap any card with any card" operation in the subs phase. */
export type RosterEndpoint =
  | { kind: 'pitch'; index: number }
  | { kind: 'bench'; group: SubPositionGroup };

export interface SubSlot {
  positionGroup: SubPositionGroup;
  spinResultClub?: string;
  chosenPlayerId?: string;
  chosenPlayerName?: string;
  chosenPlayerRating?: number;
  chosenPlayerPosition?: string;
  /** Server-only: full DraftCard for the chosen sub, used for swap mechanics. */
  chosenCard?: DraftCard;
  /** Server-only: DraftCard of the starter currently benched via swap. */
  benchedCard?: DraftCard;
  /** Index in pitch.slots where the sub card was placed. Undefined = no swap yet. */
  swappedSlotIndex?: number;
  /** Snapshot fields sent to the client (derived from benchedCard). */
  benchedPlayerId?: string;
  benchedPlayerName?: string;
  benchedPlayerRating?: number;
  benchedPlayerPosition?: string;
}

/**
 * Shared across BOTH `bench_selection` (att/mid/def spin/pick only) and
 * `lineup_edit` (free swap + Extra Bench's bonus `extra` spin/pick +
 * confirmLineup) — one continuous per-player record spanning both halves of
 * the Track B reordered flow, populated first by `_enterBenchSelectionPhase`
 * and then merged into (not replaced by) `_enterLineupEditPhase`.
 */
export interface UserSubstitutions {
  att?: SubSlot;
  mid?: SubSlot;
  def?: SubSlot;
  /**
   * Extra any-position bench sub, granted by the Extra Bench ability card.
   * Only ever populated during `lineup_edit` — `hasExtraBench` isn't known
   * until ability_activation resolves, which now happens strictly after
   * bench_selection.
   */
  extra?: SubSlot;
  /** True when this player activated the Extra Bench card (gets a 4th sub, available during `lineup_edit`). */
  hasExtraBench?: boolean;
  /**
   * Means "every group CURRENTLY required is picked" — during
   * bench_selection this is att/mid/def only; once `lineup_edit` begins and
   * `hasExtraBench` is merged in, this is recomputed against the (possibly
   * now 4-group) requirement, so it can flip back to false for an
   * Extra-Bench holder until they've also picked their bonus sub.
   */
  isComplete: boolean;
  lineupConfirmed: boolean;
}

export interface SubsPhase {
  userSubs: Record<string, UserSubstitutions>;
}

export interface GamePlayer {
  id: string;
  displayName: string;
  isHost: boolean;
  isConnected: boolean;
}

export interface TurnTimeoutPolicy {
  enabled: boolean;
  turnSeconds: number | null;
  onExpiry: 'skip_turn' | 'auto_pick_random' | null;
}

export interface ActiveTurn {
  turnId: string;
  phase: TurnPhase;
  activePlayerId: string;
  activeSlotIndex: number | null;
  candidates: DraftCard[]; // server-only — NEVER broadcast
  /** Wall-clock ms when the current timer was armed. Null when no timer or game has no timer. */
  turnStartedAt: number | null;
}

export interface GameSession {
  sessionId: string;
  roomCode: string;
  /** Wall-clock ms when the session was created — used to compute
   *  durationSeconds for match-history records (Task 2.3). */
  createdAt: number;
  /** League slugs selected for this game. Empty = all leagues allowed. */
  leagues: string[];
  /** playerId (pool) → 3 card chemistry bonuses. Built once at session start. */
  playerBonusCache: Map<string, import('../data/league-bonus-pools.js').ChemistryBonus[]>;
  /** gamePlayerId → 5 user chemistry challenges. Built once at session start. */
  userChallengeCache: Map<string, UserChemistryChallenge[]>;
  /**
   * Admin-configured scoring values, snapshotted from the currently-published
   * scoring-config.json at session creation. Built once at session start —
   * exactly like playerBonusCache/userChallengeCache above — so a later admin
   * publish never changes an in-progress session's scoring, even mid-tournament.
   */
  scoringConfig: ScoringConfigValues;
  /** Which published scoring-config version this session's `scoringConfig` came from. */
  scoringConfigVersion: number;
  formation: Formation;
  players: GamePlayer[];
  pitches: Record<string, Pitch>;
  baseTurnOrder: string[];
  currentRound: number;
  totalRounds: number;
  currentTurnIndex: number;
  currentRoundSlotIndex: number | null; // shared slot chosen by first player each round
  /** Stable player IDs that have been drafted in this session — never broadcast to clients. */
  draftedCardIds: Set<string>;
  /**
   * Full candidate pool generated when the first player picks the round slot
   * (size = playerCount + 2). The first player picks one card from this pool;
   * the remainder becomes the hidden ordered deck after they submit their order.
   * Cleared when the round wraps. Server-only — NEVER broadcast raw to clients.
   */
  roundCandidates: DraftCard[];
  /**
   * The ordered hidden deck set by the first player via `order_hidden_deck`.
   * Indexed 0..n-1; players pick by index. Server-only.
   */
  orderedHiddenDeck: DraftCard[];
  /**
   * Set of 0-based indices in `orderedHiddenDeck` that have already been
   * picked this round. Server-only.
   */
  hiddenPicksTaken: Set<number>;
  /**
   * The cards no one picked in the round that just ended (the "final" leftovers
   * from the hidden deck). Revealed to all players and shown until the next
   * round wraps. Empty before the first round ends and once the subs phase
   * begins. Safe to broadcast — these cards are out of play.
   */
  lastRoundLeftovers: DraftCard[];
  /**
   * Maps hidden deck slot index → { playerId, playerName } for each slot that
   * has been picked this round. Populated in `pickHiddenSlot`; cleared each
   * round alongside `hiddenPicksTaken`. Server-only — used by `buildSnapshot`
   * to construct per-player filtered `hiddenSlots` arrays.
   */
  hiddenPicksMap: Map<number, { playerId: string; playerName: string }>;
  /**
   * Set when a hidden pick is recorded; cleared when `confirmHiddenReveal` advances
   * the turn. Drives the `hidden_pick_reveal` phase that gives all players a
   * 5-second window to see the revealed card before the next picker is prompted.
   */
  hiddenPickReveal: {
    pickerPlayerId: string;
    timeoutAt: number; // Date.now() + 5000
  } | null;
  turn: ActiveTurn;
  turnTimeoutPolicy: TurnTimeoutPolicy;
  status: GameStatus;
  /** Face-down ability draft; non-null only during `ability_draft`. */
  abilityDraft: AbilityDraftState | null;
  /** gamePlayerId → the ability that player chose (and its lifecycle). Empty
   *  until each player picks during `ability_draft`. */
  playerAbilities: Record<string, PlayerAbility>;
  /** Public log of activated abilities, announced to all players. */
  abilityActivations: AbilityActivation[];
  /** Card ids swapped between squads by a Sub card — the swap badge follows
   *  these cards wherever they end up (including the bench after a sub). */
  subSwappedCardIds: Set<string>;
  /**
   * cardId → the extra (non-GK) position a Coach card granted that card for the
   * rest of the match. Applied at ability reveal (like `sub`'s deferred swap):
   * the position is also pushed onto that card's own `naturalPositions`/
   * `altPositions` so every position-fit path (chemistry, swap/confirm
   * validation, the client's fit logic) treats it as a real alt with no
   * further wiring — this map is the audit record + the once-per-card guard
   * (a given card can be coached at most once) + what the snapshot exposes so
   * the client can badge a coached position if it wants. Keyed by cardId so it
   * follows the player through swaps/bench moves, exactly like captain. */
  coachedPositions: Record<string, BasePositionType>;
  isFinished: boolean;
  subsPhase: SubsPhase | null;
  /** Seconds for the whole subs/bench phase. Null = no limit. */
  subsTimerSeconds: number | null;
  /** Epoch ms when the subs phase auto-confirms. Null until subs phase starts
   *  or when there is no subs timer. */
  subsDeadlineAt: number | null;
  /**
   * Epoch ms when the ability-activation phase force-resolves any player who
   * hasn't acted yet (auto-discarding their card). Set when the phase begins
   * (see `_enterActivationPhase`); null outside that phase. Exists so this
   * phase can never hang forever on a single abandoned player, mirroring
   * `subsDeadlineAt` / `forceFinalizeLineupEdit` for lineup_edit.
   */
  abilityActivationDeadlineAt: number | null;
  /** Host-chosen seconds per player for the ability-activation phase (see
   *  Room.abilityTimerSeconds). Null = no limit — see `_enterActivationPhase`. */
  abilityTimerSeconds: number | null;
  /**
   * True once `_revealAbilityActivations` has run for this activation phase.
   * Every player's choice is committed silently (see `PlayerAbility.
   * pendingSummary`) — nothing is applied to the board or published into
   * `abilityActivations` until this flips true, which happens once, in
   * `baseTurnOrder`, right after the last player locks in. Also guards
   * against double-applying a `sub` swap if a forced timeout races a manual
   * reveal. Reset to false whenever `_enterActivationPhase` runs.
   */
  abilityActivationRevealed: boolean;
  /** Whether this session runs a knockout tournament after the subs phase.
   *  Set once at session creation from the room setting; never mutated.
   *  When false the game behaves exactly as before (subs → finished). */
  tournamentEnabled: boolean;
  /** Host-chosen pacing for tournament live-event delivery. Set once at
   *  session creation from the room setting; never mutated. Purely a
   *  presentation speed — never changes the simulated result. */
  simulationSpeed: SimulationSpeed;
  /** Non-null from the moment the tournament begins until the session finishes.
   *  Always null when `tournamentEnabled` is false. */
  tournament: TournamentState | null;
  /**
   * Admin-configured tournament award values, snapshotted from the
   * currently-published tournament-awards-config.json at the moment
   * `beginTournament()` runs — same snapshot-safety principle as
   * `scoringConfig` above, just triggered at tournament start instead of
   * session creation (tournaments are optional/per-room, so there is no
   * session-creation-time equivalent). Null until the tournament begins;
   * once set, never re-read for the rest of this session, so a later admin
   * publish cannot change an in-progress tournament's payouts.
   */
  tournamentAwardsConfig: TournamentAwardsConfigValues | null;
  /** Which published tournament-awards-config version `tournamentAwardsConfig` came from. Null until the tournament begins. */
  tournamentAwardsConfigVersion: number | null;
  result: GameResult | null;
}

// ── Tournament mode ────────────────────────────────────────────────────────────

export type TournamentPhase =
  | 'bracket_reveal'
  | 'ready_check'
  | 'simulating'
  | 'round_result'
  | 'complete';

/** Round labels span all supported bracket sizes (4/8/16). */
export type TournamentRoundLabel =
  | 'Round of 16'
  | 'Quarter-finals'
  | 'Semi-finals'
  | 'Final';

/** Top-level tournament state attached to the session under `status: 'tournament'`. */
export interface TournamentState {
  phase: TournamentPhase;
  bracket: TournamentBracket;
  /** 1-indexed; 1 = the earliest round (QF/SF/etc.), `totalRounds` = the Final. */
  currentRound: number;
  /** log2(bracket.size): 2 for a 4-bracket, 3 for 8, 4 for 16. */
  totalRounds: number;
  /** Real participantIds who have pressed Ready (or been auto-readied) this round. */
  readyPlayerIds: string[];
  /** Epoch ms when the ready check auto-readies remaining players; null outside ready_check. */
  readyDeadlineAt: number | null;
  /** Epoch ms when bracket_reveal auto-advances. Set at tournament start. */
  bracketRevealAt: number;
  /** End-of-tournament awards; null until `phase === 'complete'`. */
  awards: TournamentAwards | null;
}

/** The full bracket structure: every round, every matchup. */
export interface TournamentBracket {
  size: 4 | 8 | 16;
  /** index 0 = earliest round (QF/SF/etc.); last index = the Final. */
  rounds: TournamentRound[];
}

export interface TournamentRound {
  /** 1-indexed, matches TournamentState.currentRound. */
  roundNumber: number;
  label: TournamentRoundLabel;
  matches: TournamentMatch[];
  status: 'pending' | 'in_progress' | 'complete';
}

/** A single matchup: two participants, its round, status, and result. */
export interface TournamentMatch {
  matchId: string; // stable, e.g. 'r1_m1', 'r2_m1'
  roundNumber: number;
  participantA: TournamentParticipant;
  participantB: TournamentParticipant;
  status: 'pending' | 'ready_check' | 'simulating' | 'complete';
  /**
   * @internal SERVER-ONLY. Pre-generated full event list from the simulation
   * engine. Streamed to clients one item at a time during `simulating`. Must
   * NEVER be serialised into a `tournament_state` payload (see
   * `buildTournamentStatePayload`, which omits it explicitly).
   */
  simulationEvents: MatchEvent[];
  /**
   * @internal SERVER-ONLY. Delivery cursor into `simulationEvents`. Must NEVER
   * be serialised into a `tournament_state` payload.
   */
  nextEventIndex: number;
  result: MatchSimulationResult | null;
  /** participantId of the winner; null until `status === 'complete'`. */
  winnerId: string | null;
}

/**
 * Either a real player or an AI club. Discriminated on `kind` — same pattern as
 * the existing `RosterEndpoint` union in this file.
 *
 * Note: not-yet-decided ("TBD") future-round slots carry `lineup: null` as a
 * placeholder until the winner of the feeding match advances into them. AI
 * participants are real clubs (see `AiTeamFactory`) with a real generated
 * `lineup`, frozen at tournament start exactly like a human's confirmed
 * squad — `lineup: null` for an AI participant only happens in the
 * (practically unreachable) case where the room's leagues have no players
 * at all, which `AiTeamFactory.selectAiClub` reports by returning `null`.
 */
export type TournamentParticipant =
  | {
      kind: 'real';
      participantId: string;
      displayName: string;
      lineup: ParticipantLineup | null;
      clubLogoUrl?: string;
    }
  | {
      kind: 'ai';
      participantId: string;
      displayName: string;
      lineup: ParticipantLineup | null;
      /** The AI club's badge, when the pool has one for the chosen club. */
      clubLogoUrl?: string;
    };

/** A frozen snapshot of one participant's confirmed lineup at bracket creation. */
export interface ParticipantLineup {
  formationSlug: string;
  /** 11 starters in slot order (slot 0 = GK). */
  pitchCards: FrozenCard[];
  /** 0–4 bench cards from the completed subs phase. */
  benchCards: FrozenCard[];
  /** Mean of the 11 pitchCards' ratings (1 dp). */
  overallRating: number;
  /** ScoreBreakdown.finalScore equivalent, computed at bracket creation. */
  chemistryScore: number;
  captainCardId: string | null;
  /** Ability type strings for abilities that are 'activated'. */
  activeAbilityTypes: string[];
}

/** A single player card frozen into a tournament lineup. */
export interface FrozenCard {
  cardId: string;
  playerName: string;
  rating: number;
  basePositionType: BasePositionType;
  slotLabel: SlotLabel;
  nationality: string;
  club: string;
  league: string;
  chemistryBonuses: ChemistryBonus[];
}

/** One event in a simulated match. */
export interface MatchEvent {
  /**
   * 1–90 for regulation events. A penalty shootout's individual kicks use
   * 121, 122, 123… (120 + kick number) purely as a sortable/orderable marker
   * — clients should render these as "P1", "P2", … rather than a real minute.
   */
  minute: number;
  type: 'goal' | 'yellow_card' | 'red_card' | 'big_chance_missed' | 'penalty_scored' | 'penalty_missed';
  /** participantId of the team this event belongs to. */
  teamParticipantId: string;
  playerName: string;
  playerRating: number;
  /** Goals only, optional. */
  assistPlayerName?: string;
}

export interface MatchStats {
  /** 0–100; possessionB is implicitly 100 − possessionA. */
  possessionA: number;
  shotsA: number;
  shotsOnTargetA: number;
  bigChancesA: number;
  shotsB: number;
  shotsOnTargetB: number;
  bigChancesB: number;
}

/** The output of one simulated match. */
export interface MatchSimulationResult {
  matchId: string;
  /** Regulation-time score. Never adjusted for a shootout. */
  scoreA: number;
  scoreB: number;
  /** participantId; no draws (a level scoreA/scoreB is resolved by penalties). */
  winnerId: string;
  /** Null unless scoreA === scoreB, in which case a real shootout decided it. */
  penaltyScoreA: number | null;
  penaltyScoreB: number | null;
  stats: MatchStats;
  /** playerName → match rating 0.0–10.0. Shootout kicks never affect this. */
  playerRatings: Record<string, number>;
  /** 1–2 sentence narrative summary. */
  explanation: string;
}

/**
 * A per-player stat award entry. Awards can be SHARED — see
 * GameService._computeTournamentAwards' tie-break documentation — so every
 * category is an array (length 1 in the common case, 2+ when genuinely tied).
 */
export interface TournamentStatLeader {
  playerName: string;
  participantId: string;
  /** Total minutes this player featured across the whole tournament. */
  minutesPlayed: number;
}

/** End-of-tournament awards. */
export interface TournamentAwards {
  champion: TournamentParticipant;
  runnerUp: TournamentParticipant;
  /** Empty array if nobody scored. Length > 1 = a shared award. */
  topScorer: (TournamentStatLeader & { goals: number })[];
  /** Empty array if nobody assisted. Length > 1 = a shared award. */
  mostAssists: (TournamentStatLeader & { assists: number })[];
  /** goals + assists. Empty array if nobody contributed. Length > 1 = shared. */
  topContributions: (TournamentStatLeader & { goals: number; assists: number; contributions: number })[];
  /**
   * The individual player with the highest average match rating across the
   * tournament — a genuine per-player award, tie-broken the same way as
   * every other stat category (fewer minutes played, then shared).
   * Empty array if nobody has a recorded rating yet. Length > 1 = shared.
   */
  highestAvgRating: (TournamentStatLeader & { avgRating: number })[];
  /**
   * Credited to the actual goalkeeper (the pitch-slot 'GK' card) of a
   * participant whose side conceded 0 in a completed match — never the
   * participant/team display name. Empty array if nobody kept a clean
   * sheet. Length > 1 = shared.
   */
  cleanSheets: (TournamentStatLeader & { cleanSheets: number })[];
  /** Points awarded to real participants only. Key = participantId (50 / 20). */
  pointsAwarded: Record<string, number>;
  /**
   * Category labels (e.g. "Top Scorer") where an AI participant was among
   * the (possibly tied) leaders, so the bonus paid no human at all — not
   * even a human sharing that same tie. Lets clients explain a blocked
   * payout instead of a human leader's bonus silently not appearing.
   */
  blockedCategories: string[];
  /**
   * The exact tournament awards config values used to compute THIS result
   * (Track A Step 5) — i.e. `GameSession.tournamentAwardsConfig` as it stood
   * when `_computeTournamentAwards()` ran, not a live/re-fetched value. Lets
   * clients render the correct point amounts for this specific tournament
   * without needing their own config fetch/cache, and without ever risking
   * drift from what was actually paid out.
   */
  pointsConfig: TournamentAwardsConfigValues;
}
