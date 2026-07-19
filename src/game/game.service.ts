import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { v4 as uuidv4 } from 'uuid';
import { InjectPinoLogger, PinoLogger } from 'nestjs-pino';
import * as fs from 'fs';
import * as path from 'path';
import { Room } from '../rooms/interfaces/room.interface';
import {
  GameSession,
  GamePlayer,
  ActiveTurn,
  TurnTimeoutPolicy,
  SubPositionGroup,
  SubSlot,
  SubsPhase,
  UserSubstitutions,
  RosterEndpoint,
  TournamentState,
  TournamentPhase,
  TournamentBracket,
  TournamentRound,
  TournamentRoundLabel,
  TournamentMatch,
  TournamentParticipant,
  ParticipantLineup,
  FrozenCard,
  MatchEvent,
  MatchSimulationResult,
  TournamentAwards,
} from './interfaces/game-session.interface';
import { Formation, BasePositionType, SlotLabel } from './interfaces/formation.interface';
import {
  AbilityCard,
  AbilityType,
  AbilityActivation,
  ABILITY_ORIGINALS,
  COACHABLE_POSITIONS,
} from './interfaces/ability.interface';
import { DraftCard } from './interfaces/draft-card.interface';
import { Pitch, PitchSlot } from './interfaces/pitch.interface';
import { GameResult, PlayerResult } from './interfaces/game-result.interface';
import { FORMATIONS } from './data/formations';
import { PLAYER_POOL, PlayerCardDefinition } from './data/player-pool';
import { computeAllScores, computeLivePreview, emptyBreakdown, CLUB_LEAGUE, cardFitsSlot } from './scoring';
import { ChemistryShuffleService } from './chemistry-shuffle';
import { UserChallengeShuffleService } from './user-challenge-shuffle';
import { ScoringConfigValues, ScoringConfigFile, DEFAULT_SCORING_CONFIG_V1 } from './scoring-config';
import { TournamentAwardsConfigValues, TournamentAwardsConfigFile, DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1 } from './tournament-awards-config';
import { AiTeamFactory } from './ai-team-factory';
import { getCached, clearAllCache } from './admin-data-cache';
import { MatchHistoryService } from '../match-history/match-history.service';

const ADMIN_DATA_DIR = path.resolve(process.cwd(), 'admin-data');

/**
 * Club → league map edited via the admin portal (admin-data/clubs.json). Lets
 * club/league moderation take effect in games; empty when the file is absent.
 */
interface ClubMeta {
  league?: string;
  logoUrl?: string;
}

/**
 * Loads the active formations the admin enabled (admin-data/formations.json).
 * Falls back to the full static FORMATIONS list when the file is missing,
 * unreadable, or leaves zero formations active.
 */
function loadActiveFormations(): Formation[] {
  return getCached('formations.json', () => {
    const file = path.join(ADMIN_DATA_DIR, 'formations.json');
    if (!fs.existsSync(file)) return FORMATIONS;
    try {
      const raw = JSON.parse(fs.readFileSync(file, 'utf8')) as {
        name: string;
        active?: boolean;
        slots: Formation['slots'];
      }[];
      const active = raw
        .filter((f) => f.active !== false && Array.isArray(f.slots) && f.slots.length === 11)
        .map((f) => ({ slug: (f as any).slug as string | undefined, name: f.name, slots: f.slots }));
      return active.length > 0 ? active : FORMATIONS;
    } catch {
      return FORMATIONS;
    }
  });
}

/**
 * The ability types the admin left enabled (admin-data/abilities.json). Falls
 * back to all 5 originals when the file is missing or unreadable. May return an
 * empty list if the admin disabled every ability — callers then skip the draft.
 */
function loadEnabledAbilityTypes(): AbilityType[] {
  return getCached('abilities.json', () => {
    const file = path.join(ADMIN_DATA_DIR, 'abilities.json');
    if (!fs.existsSync(file)) return [...ABILITY_ORIGINALS];
    try {
      const raw = JSON.parse(fs.readFileSync(file, 'utf8')) as {
        type: string;
        enabled?: boolean;
      }[];
      // De-duplicate: the no-repeat dealing rule (buildAbilityPool) counts the
      // number of DISTINCT enabled abilities. A malformed/hand-edited
      // abilities.json with the same type listed twice would otherwise inflate
      // that count and let the "unique slice" branch pick the same type twice
      // (e.g. two `sub` entries → 2 players could both draw sub even though two
      // distinct abilities appear enabled). Uniqueness here guarantees it.
      const enabled = [
        ...new Set(
          raw
            .filter(
              (a) =>
                a.enabled !== false &&
                ABILITY_ORIGINALS.includes(a.type as AbilityType),
            )
            .map((a) => a.type as AbilityType),
        ),
      ];
      return enabled;
    } catch {
      return [...ABILITY_ORIGINALS];
    }
  });
}

function loadClubMetaMap(): Record<string, ClubMeta> {
  return getCached('clubs.json', () => {
    const file = path.join(ADMIN_DATA_DIR, 'clubs.json');
    if (!fs.existsSync(file)) return {};
    try {
      const clubs = JSON.parse(fs.readFileSync(file, 'utf8')) as {
        name?: string;
        league?: string;
        logoUrl?: string;
      }[];
      const map: Record<string, ClubMeta> = {};
      for (const c of clubs) {
        if (c.name) map[c.name] = { league: c.league, logoUrl: c.logoUrl };
      }
      return map;
    } catch {
      return {};
    }
  });
}

/**
 * Load players from admin JSON if available; falls back to the static pool.
 * Each player is enriched with the league AND club logo their club is assigned
 * in the admin portal so club edits (admin-data/clubs.json) flow into game
 * logic (league filters, sub spins, chemistry, scoring) and into card visuals
 * (an admin-set club logo overrides the client name-based fallback).
 */
/**
 * Raw, un-enriched player rows, cached independently from the clubMeta
 * enrichment below — split out specifically so a clubs.json admin write
 * (which doesn't touch players.json at all) still produces freshly-enriched
 * results without needing players.json's own cache entry to also be
 * invalidated.
 */
function loadRawPlayerPool(): PlayerCardDefinition[] {
  return getCached('players.json', () => {
    const file = path.join(ADMIN_DATA_DIR, 'players.json');
    if (!fs.existsSync(file)) return PLAYER_POOL;
    try {
      const raw = JSON.parse(fs.readFileSync(file, 'utf8')) as PlayerCardDefinition[];
      return raw.length > 0 ? raw : PLAYER_POOL;
    } catch {
      return PLAYER_POOL;
    }
  });
}

/**
 * Loads the currently-published scoring config (admin-data/scoring-config.json).
 * Falls back to DEFAULT_SCORING_CONFIG_V1 (version 1) when the file is
 * missing, unreadable, or has no valid `published` entry — v1's values equal
 * today's pre-existing hardcoded scoring constants exactly, so a missing file
 * never changes gameplay. Read once per createSession() call and snapshotted
 * onto the session (see GameSession.scoringConfig) — never re-read mid-game.
 */
function loadPublishedScoringConfig(): { values: ScoringConfigValues; version: number } {
  return getCached('scoring-config.json', () => {
    const file = path.join(ADMIN_DATA_DIR, 'scoring-config.json');
    if (!fs.existsSync(file)) return { values: DEFAULT_SCORING_CONFIG_V1, version: 1 };
    try {
      const raw = JSON.parse(fs.readFileSync(file, 'utf8')) as ScoringConfigFile;
      if (!raw.published?.values) return { values: DEFAULT_SCORING_CONFIG_V1, version: 1 };
      return { values: raw.published.values, version: raw.published.version };
    } catch {
      return { values: DEFAULT_SCORING_CONFIG_V1, version: 1 };
    }
  });
}

/**
 * Loads the currently-published tournament awards config
 * (admin-data/tournament-awards-config.json). Falls back to
 * DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1 (version 1) when the file is missing,
 * unreadable, or has no valid `published` entry — v1's values equal today's
 * pre-existing hardcoded tournament award constants exactly, so a missing
 * file never changes gameplay. Read once per beginTournament() call and
 * snapshotted onto the session (see GameSession.tournamentAwardsConfig) —
 * never re-read for the rest of that tournament.
 */
function loadPublishedTournamentAwardsConfig(): { values: TournamentAwardsConfigValues; version: number } {
  return getCached('tournament-awards-config.json', () => {
    const file = path.join(ADMIN_DATA_DIR, 'tournament-awards-config.json');
    if (!fs.existsSync(file)) return { values: DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1, version: 1 };
    try {
      const raw = JSON.parse(fs.readFileSync(file, 'utf8')) as TournamentAwardsConfigFile;
      if (!raw.published?.values) return { values: DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1, version: 1 };
      return { values: raw.published.values, version: raw.published.version };
    } catch {
      return { values: DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1, version: 1 };
    }
  });
}

// Memoizes loadPlayerPool()'s enrichment .map() against the two cached
// inputs it derives from, by reference — NOT a getCached() entry of its own,
// so no third invalidateCache() call site needs to know this derived value
// exists. getCached() only ever returns a NEW array/object reference after
// invalidateCache() forces a real recompute (see admin-data-cache.ts), and
// the SAME reference on every hit in between — so comparing references here
// is exactly equivalent to "has players.json or clubs.json actually changed
// since I last enriched", with no explicit wiring required.
//
// This exists because a full 5000+ row .map() (allocating a new object with
// a full property spread per row) run on every single generateCandidates /
// sub-spin / AI-pool call was a measured, real CPU cost under load — see
// LOAD_TEST_RESULTS.md's medium-concurrency findings: game duration and even
// unrelated /metrics requests degraded ~3x at 30 concurrent games, root-caused
// to this recomputing on every gameplay message across every concurrent game.
let _enrichedPoolCache: {
  raw: PlayerCardDefinition[];
  clubMeta: Record<string, ClubMeta>;
  result: PlayerCardDefinition[];
} | null = null;

function loadPlayerPool(): PlayerCardDefinition[] {
  const players = loadRawPlayerPool();
  const clubMeta = loadClubMetaMap();
  if (Object.keys(clubMeta).length === 0) return players;

  if (
    _enrichedPoolCache &&
    _enrichedPoolCache.raw === players &&
    _enrichedPoolCache.clubMeta === clubMeta
  ) {
    return _enrichedPoolCache.result;
  }

  const result = players.map((p) => {
    const meta = clubMeta[p.club];
    return {
      ...p,
      league: meta?.league ?? (p as any).league ?? CLUB_LEAGUE[p.club],
      // An admin-set club logo wins; otherwise keep whatever the player had
      // (often empty → client falls back to its name-based lookup).
      clubLogoUrl: meta?.logoUrl ?? p.clubLogoUrl,
    };
  });
  _enrichedPoolCache = { raw: players, clubMeta, result };
  return result;
}

// ── Return types ──────────────────────────────────────────────────────────────

export interface PickCardResult {
  session: GameSession;
  /** Cards the first player must order (multi-player). Null in solo game. */
  orderPromptCards: DraftCard[] | null;
}

export interface OrderHiddenDeckResult {
  session: GameSession;
  /**
   * Slot indices the next player may choose from. Absent when every
   * remaining player this round was disconnected (Task 6) — the round (or
   * the whole draft) already wrapped past hidden-pick entirely and there's
   * no next picker to prompt.
   */
  availableSlots?: number[];
}

export interface PickHiddenSlotResult {
  session: GameSession;
  revealedCard: DraftCard;
  /** Present when the round continues: available slots for the NEXT hidden picker. */
  nextAvailableSlots?: number[];
}

export interface ConfirmHiddenRevealResult {
  session: GameSession;
  /** Present when the round continues: available slots for the NEXT hidden picker. */
  nextAvailableSlots?: number[];
}

export interface RemovePlayerResult {
  session: GameSession;
  /** When the removed player was the hidden-pick orderer, new available slots. */
  autoHiddenPickSlots?: number[];
  /**
   * Set when the removed player was part of an in-progress ability draft.
   * Mirrors pickAbilityCard's own `{ session, allPicked }` shape so the
   * gateway can run the exact same post-pick orchestration a real pick
   * would (reveal-window timing, draft-timer clear/rearm — see
   * `_afterAbilityPick` in rooms.gateway.ts) instead of duplicating it.
   */
  abilityDraftAllPicked?: boolean;
  /**
   * Set when the removed player was the LAST pending ability during
   * ability_activation. Mirrors activateAbility/discardAbility's own
   * `{ session, allResolved }` shape so the gateway can run the exact same
   * reveal-then-hold orchestration a real commit would (see
   * `_afterAbilityActivation` in rooms.gateway.ts) instead of duplicating it.
   */
  abilityActivationAllResolved?: boolean;
  /**
   * Set when removing this player was the LAST confirmation needed to
   * complete lineup_edit, AND the session is tournament-enabled — mirrors
   * confirmLineup/forceFinalizeLineupEdit's own `tournamentStarting` flag so
   * the gateway can call beginBracketReveal the same way it does for a real
   * confirm_lineup/timeout. Undefined in every other case (including a
   * non-tournament session reaching the same completion, which is finalized
   * directly instead — see removePlayer's lineup_edit-phase handling).
   */
  subsTournamentStarting?: boolean;
  /**
   * Set (to true or false) when the removed player was a real participant
   * in the CURRENT tournament round's ready_check — mirrors
   * recordTournamentReady's own `allReady` return so the gateway can
   * broadcast the updated tournament_state and, if this removal was the
   * last ready needed, start simulating immediately instead of waiting out
   * the 60s auto-ready timeout for someone who's no longer in the room.
   * Undefined whenever the removal has nothing to do with an in-progress
   * ready_check (wrong phase, or the removed player wasn't in this round).
   */
  tournamentAllReadyAfterRemoval?: boolean;
}

// ── Service ───────────────────────────────────────────────────────────────────

@Injectable()
export class GameService implements OnModuleDestroy {
  private sessions = new Map<string, GameSession>();
  private roomToSession = new Map<string, string>(); // roomCode → sessionId
  private readonly chemistryShuffle = new ChemistryShuffleService();
  private readonly userChallengeShuffle = new UserChallengeShuffleService();

  /** Task 2.2: drop the admin-data JSON cache on clean teardown. */
  onModuleDestroy(): void {
    clearAllCache();
  }

  // Defaulted (not required) so every existing `new GameService()` test
  // instantiation keeps working unchanged — see the same pattern in
  // RoomsGateway's constructor for the full rationale.
  constructor(
    // Silent by default — this fallback only ever runs in a test/non-DI
    // context (production always gets the real, app-configured logger via
    // DI), and a silent default keeps test output clean.
    @InjectPinoLogger(GameService.name)
    private readonly logger: PinoLogger = new PinoLogger({ pinoHttp: { level: 'silent' } }),
    // Defaulted the same way — a standalone `new MatchHistoryService()`
    // never has onModuleInit() run (that's a DI-container-only lifecycle
    // hook), so its `db` stays uninitialized; recordMatch() handles that
    // safely (logs + no-ops) rather than throwing, by the same "must never
    // break the game flow" contract described on that method.
    private readonly matchHistoryService: MatchHistoryService = new MatchHistoryService(),
  ) {}

  /** Number of currently active game sessions. For /metrics (Task 3.4). */
  getActiveSessionCount(): number {
    return this.sessions.size;
  }

  // ── Create ────────────────────────────────────────────────────────────────

  createSession(room: Room): GameSession {
    const formation = this.pickFormation(room.formationSlug);

    const players: GamePlayer[] = room.players
      .filter((p) => p.isConnected)
      .map((p) => ({
        id: p.id,
        displayName: p.displayName,
        isHost: p.isHost,
        isConnected: p.isConnected,
      }));

    const pitches = this.buildPitches(players.map((p) => p.id), formation);
    const baseTurnOrder = this.shuffle(players.map((p) => p.id));

    // Abilities the admin left enabled. When empty, the ability draft is skipped.
    const enabledAbilities = loadEnabledAbilityTypes();
    const hasAbilities = enabledAbilities.length > 0;

    const turn: ActiveTurn = {
      turnId: uuidv4(),
      phase: 'selecting_position',
      activePlayerId: baseTurnOrder[0],
      activeSlotIndex: null,
      candidates: [],
      turnStartedAt: null,
    };

    const turnTimerSeconds = room.turnTimerSeconds ?? null;
    const turnTimeoutPolicy: TurnTimeoutPolicy = {
      enabled: turnTimerSeconds !== null,
      turnSeconds: turnTimerSeconds,
      onExpiry: turnTimerSeconds !== null ? 'auto_pick_random' : null,
    };

    const sessionId = uuidv4();
    const leagues = room.leagues ?? [];
    const pool = loadPlayerPool();
    // Snapshot the currently-published scoring config once, here, so nothing
    // later in this session ever re-reads scoring-config.json — see the
    // GameSession.scoringConfig doc comment for why this matters.
    const scoringConfig = loadPublishedScoringConfig();
    const playerBonusCache = this.chemistryShuffle.buildBonusCache(
      sessionId,
      leagues,
      pool,
      scoringConfig.values.cardChemistry.tierRewards,
    );
    const userChallengeCache = this.userChallengeShuffle.buildCache(
      players.map(p => p.id),
      room.code,
      pool,
      leagues,
      scoringConfig.values.userChallenges.rewardPerChallenge,
    );

    const session: GameSession = {
      sessionId,
      roomCode: room.code,
      createdAt: Date.now(),
      leagues,
      playerBonusCache,
      userChallengeCache,
      scoringConfig: scoringConfig.values,
      scoringConfigVersion: scoringConfig.version,
      formation,
      players,
      pitches,
      baseTurnOrder,
      currentRound: 1,
      totalRounds: 11,
      currentTurnIndex: 0,
      currentRoundSlotIndex: null,
      draftedCardIds: new Set<string>(),
      roundCandidates: [],
      orderedHiddenDeck: [],
      hiddenPicksTaken: new Set<number>(),
      lastRoundLeftovers: [],
      hiddenPicksMap: new Map(),
      hiddenPickReveal: null,
      turn,
      turnTimeoutPolicy,
      // The game opens with the face-down ability draft (unless the admin
      // disabled every ability, in which case it starts straight in drafting).
      status: hasAbilities ? 'ability_draft' : 'drafting',
      abilityDraft: hasAbilities
        ? {
            pool: this.buildAbilityPool(baseTurnOrder.length, enabledAbilities),
            pickOrder: baseTurnOrder,
            currentPickIndex: 0,
          }
        : null,
      playerAbilities: {},
      abilityActivations: [],
      abilityActivationRevealed: false,
      subSwappedCardIds: new Set<string>(),
      coachedPositions: {},
      isFinished: false,
      subsPhase: null,
      subsTimerSeconds: room.subsTimerSeconds ?? null,
      subsDeadlineAt: null,
      abilityActivationDeadlineAt: null,
      abilityTimerSeconds: room.abilityTimerSeconds ?? null,
      tournamentEnabled: room.tournamentEnabled ?? false,
      simulationSpeed: room.simulationSpeed ?? 'normal',
      tournament: null,
      // Snapshotted later, in beginTournament() — tournaments are optional/
      // per-room, so unlike scoringConfig there's no session-creation-time
      // equivalent. Null until the tournament actually begins.
      tournamentAwardsConfig: null,
      tournamentAwardsConfigVersion: null,
      result: null,
    };

    this.sessions.set(session.sessionId, session);
    this.roomToSession.set(room.code, session.sessionId);
    return session;
  }

  // ── Ability draft ──────────────────────────────────────────────────────────

  /**
   * Builds the face-down ability pool for a game.
   *  • count === playerCount.
   *  • ≤ 5 players → a random subset of the 5 originals, NO duplicates (so some
   *    abilities may not appear that game).
   *  • > 5 players → all 5 originals PLUS random duplicates to reach playerCount.
   */
  private buildAbilityPool(
    playerCount: number,
    enabled: AbilityType[],
  ): AbilityCard[] {
    // Deal from the DISTINCT enabled abilities. Deduping here (in addition to
    // loadEnabledAbilityTypes) makes the no-repeat guarantee hold for ANY
    // caller, not just the disk loader: when playerCount <= the number of
    // distinct abilities, every player draws a different one; repeats are
    // introduced (the else branch) ONLY once there aren't enough distinct
    // abilities to give everyone a unique card.
    const unique = [...new Set(enabled)];
    let types: AbilityType[];
    if (playerCount <= unique.length) {
      types = this.shuffle(unique).slice(0, playerCount);
    } else {
      const extras: AbilityType[] = Array.from(
        { length: playerCount - unique.length },
        () => unique[Math.floor(Math.random() * unique.length)],
      );
      types = this.shuffle([...unique, ...extras]);
    }
    return types.map((type, id) => ({ id, type, pickedBy: null }));
  }

  /**
   * Records a player's ability pick (turn order enforced). When the last player
   * has picked, the session transitions into the normal player draft.
   */
  pickAbilityCard(
    roomCode: string,
    playerId: string,
    cardId: number,
  ): { error: string } | { session: GameSession; allPicked: boolean } {
    const session = this.getSessionByRoomCode(roomCode);
    if (!session) return { error: 'SESSION_NOT_FOUND' };
    if (session.status !== 'ability_draft' || !session.abilityDraft) {
      return { error: 'NOT_ABILITY_DRAFT' };
    }
    const ad = session.abilityDraft;
    if (ad.pickOrder[ad.currentPickIndex] !== playerId) {
      return { error: 'NOT_YOUR_TURN' };
    }
    const card = ad.pool.find((c) => c.id === cardId);
    if (!card || card.pickedBy) return { error: 'INVALID_CARD' };

    card.pickedBy = playerId;
    session.playerAbilities[playerId] = { type: card.type, status: 'pending' };
    ad.currentPickIndex += 1;

    // When the last player picks we do NOT start the draft immediately — a brief
    // reveal window (driven by the gateway) lets the final picker see their card
    // before `beginPlayerDraft` transitions everyone into the player draft.
    const allPicked = ad.currentPickIndex >= ad.pickOrder.length;
    return { session, allPicked };
  }

  /** Transitions out of the ability draft into the player draft (gateway-timed). */
  beginPlayerDraft(
    roomCode: string,
  ): { error: string } | { session: GameSession } {
    const session = this.getSessionByRoomCode(roomCode);
    if (!session) return { error: 'SESSION_NOT_FOUND' };
    if (session.status !== 'ability_draft') {
      return { error: 'NOT_ABILITY_DRAFT' };
    }
    session.abilityDraft = null;
    session.status = 'drafting';
    session.turn.turnStartedAt = session.turnTimeoutPolicy.enabled
      ? Date.now()
      : null;
    return { session };
  }

  /**
   * Structured ability marks for client visualisation: which slot each player
   * captained, which of each player's slots were red-carded, and each player's
   * yellow-card penalty. Mirrors the scoring logic so badges match the result.
   *
   * Gated on `session.abilityActivationRevealed`, same as `abilityActivations`
   * itself — NOT just `ab.status === 'used'`. `activateAbility` sets `status`
   * to 'used' and records `targetPlayerId`/`targetUserId` at COMMIT time (see
   * its own doc comment), well before reveal; without this second gate, a
   * captain/red/yellow badge would appear on every viewer's pitch the instant
   * one player commits, before anyone else has even locked in — the exact
   * "react to visible ability usage" leak hidden commitment exists to close.
   * (`sub`'s effect is naturally safe without this gate: the swap itself, and
   * `subSwappedCardIds`, are only ever populated inside
   * `_revealAbilityActivations`, so there's nothing to leak pre-reveal.)
   */
  private _abilityMarks(session: GameSession): {
    captainCardByPlayer: Record<string, string>;
    redCardIds: Set<string>;
    yellowByPlayer: Record<string, number>;
    coachedCardIds: Set<string>;
  } {
    const captainCardByPlayer: Record<string, string> = {};
    const redCardIds = new Set<string>();
    const yellowByPlayer: Record<string, number> = {};
    // Coach effects are applied (and coachedPositions populated) only at the
    // reveal pass, so this is naturally empty pre-reveal — no reveal gate
    // needed, unlike the pending captain/red/yellow marks below.
    const coachedCardIds = new Set<string>(
      Object.keys(session.coachedPositions ?? {}),
    );
    if (!session.abilityActivationRevealed) {
      return { captainCardByPlayer, redCardIds, yellowByPlayer, coachedCardIds };
    }
    for (const [pid, ab] of Object.entries(session.playerAbilities ?? {})) {
      if (ab.status !== 'used') continue;
      if (ab.type === 'captain' && ab.targetPlayerId) {
        captainCardByPlayer[pid] = ab.targetPlayerId;
      } else if (ab.type === 'red' && ab.targetPlayerId) {
        redCardIds.add(ab.targetPlayerId);
      } else if (ab.type === 'yellow' && ab.targetUserId != null) {
        yellowByPlayer[ab.targetUserId] =
          (yellowByPlayer[ab.targetUserId] ?? 0) + 20;
      }
    }
    return { captainCardByPlayer, redCardIds, yellowByPlayer, coachedCardIds };
  }

  /**
   * Serialises pitches for the client, tagging each slot with `captain` /
   * `redCarded` / `subSwapped` flags — all keyed on the CARD currently in the
   * slot, so badges follow players when they move during the subs phase.
   */
  private _serializePitches(
    session: GameSession,
    marks: {
      captainCardByPlayer: Record<string, string>;
      redCardIds: Set<string>;
      coachedCardIds: Set<string>;
    },
    localPlayerId?: string,
  ): Record<string, object> {
    const out: Record<string, object> = {};
    for (const [pid, pitch] of Object.entries(session.pitches)) {
      // Chemistry is private, per-player strategic information — each
      // player's chemistry challenges (session.playerBonusCache, the same
      // data card.chemistryBonuses carries) are drawn independently per
      // player specifically so they're secret. Sending them on every card
      // for EVERY pitch (needed for legitimate things like seeing an
      // opponent's club/rating/position) would let any client locally
      // recompute an opponent's full achieved chemistry — the club/nation/
      // league fields alone are enough for ChemistryEvaluator to do that
      // (see chemistry_evaluator.dart). Stripping chemistryBonuses down to
      // [] for every pitch except the viewer's own removes that entirely:
      // no chemistry total, no per-card badges, no achieved/progress
      // indicator can be computed client-side from an empty list. Mirrors
      // _buildSubsPhaseSnapshot's identical "full data for localPlayer,
      // status-only for others" pattern for the bench.
      //
      // Once the game is finished, this protection is deliberately dropped —
      // the result screen (result_screen.dart) shows every player's full
      // chemistry breakdown by design (its own admin-editable help text says
      // "Tap any row in Final Standings to see that user's full breakdown"),
      // and it reads the exact same buildSnapshot payload live gameplay
      // does. Without this bypass the redaction above would silently zero
      // out that intentional post-game transparency too.
      const isOwnPitch = pid === localPlayerId || session.isFinished;
      out[pid] = {
        playerId: pitch.playerId,
        filledCount: pitch.filledCount,
        slots: pitch.slots.map((s) => ({
          ...s,
          card:
            s.card != null && !isOwnPitch
              ? { ...s.card, chemistryBonuses: [] }
              : s.card,
          captain:
            s.card != null && marks.captainCardByPlayer[pid] === s.card.cardId,
          redCarded: s.card != null && marks.redCardIds.has(s.card.cardId),
          subSwapped:
            s.card != null && session.subSwappedCardIds.has(s.card.cardId),
          // Coach: this card gained an extra position (tracked by card id, so
          // the badge follows the player through swaps/bench moves).
          coached: s.card != null && marks.coachedCardIds.has(s.card.cardId),
        })),
      };
    }
    return out;
  }

  /**
   * Client view of the ability draft. Unpicked cards expose only their slot id
   * (face-down); the local player's own pick reveals its type so they can see
   * and remember their card. Other players' picks expose only the picker id.
   */
  private _buildAbilityDraftSnapshot(
    ad: import('./interfaces/ability.interface.js').AbilityDraftState,
    localPlayerId?: string,
  ): object {
    return {
      poolCount: ad.pool.length,
      pickOrder: ad.pickOrder,
      currentPickIndex: ad.currentPickIndex,
      currentPickerId: ad.pickOrder[ad.currentPickIndex] ?? null,
      // Per-card: id + who picked it (null while face-down). Type is included
      // ONLY for the local player's own card.
      cards: ad.pool.map((c) => ({
        id: c.id,
        pickedBy: c.pickedBy,
        type: c.pickedBy != null && c.pickedBy === localPlayerId ? c.type : null,
      })),
    };
  }

  // ── Snapshot (broadcast-safe — no candidate or hidden deck data) ──────────

  buildSnapshot(session: GameSession, localPlayerId?: string): object {
    const currentTurnOrder = this.computeEffectiveTurnOrder(session);
    const marks = this._abilityMarks(session);

    return {
      sessionId: session.sessionId,
      roomCode: session.roomCode,
      formation: session.formation,
      players: session.players,
      pitches: this._serializePitches(session, marks, localPlayerId),
      // Per-player yellow-card penalty (points docked), for team-level badges.
      yellowPenalties: marks.yellowByPlayer,
      // Card ids swapped by a Sub card — lets the bench show the swap badge too.
      subSwappedCardIds: [...session.subSwappedCardIds],
      // cardId → the extra position a Coach card granted that card. The
      // position is already baked into each coached card's naturalPositions
      // (so all fit/chemistry logic just works); this map is exposed only so
      // the client can optionally badge WHICH position was coached.
      coachedPositions: session.coachedPositions,
      baseTurnOrder: session.baseTurnOrder,
      currentRound: session.currentRound,
      totalRounds: session.totalRounds,
      currentTurnOrder,
      currentTurnIndex: session.currentTurnIndex,
      currentRoundSlotIndex: session.currentRoundSlotIndex,
      turn: {
        turnId: session.turn.turnId,
        phase: session.turn.phase,
        activePlayerId: session.turn.activePlayerId,
        activeSlotIndex: session.turn.activeSlotIndex,
        // Private to the active player only — mirrors myAbility/scoringPreview's
        // localPlayerId-scoped treatment elsewhere in this snapshot. Durable
        // (part of every game_state, not a one-off event) specifically so a
        // refresh mid-selecting_card can restore the exact candidate pool:
        // the only other place this pool is ever sent is the slot_candidates
        // event pickSlot() fires once, live, straight after the request that
        // created it — a client that missed that single delivery (reconnect,
        // refresh) previously had no way to ever see it again. Empty for
        // every other player/phase — session.turn.candidates is itself reset
        // to [] outside the selecting_card window (see pickCard/pickSlot), so
        // this check is really just "is this snapshot for the active player".
        candidates:
          localPlayerId != null && localPlayerId === session.turn.activePlayerId
            ? session.turn.candidates
            : [],
        // Populated during hidden_pick_reveal so clients know who must confirm.
        revealPickerPlayerId: session.hiddenPickReveal?.pickerPlayerId ?? null,
        // Timer data — null when no timer is set for this room.
        turnStartedAtMs: session.turn.turnStartedAt,
        turnDurationSeconds: session.turnTimeoutPolicy.enabled
          ? session.turnTimeoutPolicy.turnSeconds
          : null,
      },
      // Hidden-pick metadata: lets all clients render face-down slot grid.
      // Once a slot is taken the full card is revealed to everyone — no filtering.
      hiddenDeckSize: session.orderedHiddenDeck.length,
      hiddenSlotsTaken: Array.from(session.hiddenPicksTaken),
      hiddenSlots: session.orderedHiddenDeck.map((card, i) => {
        const pickInfo = session.hiddenPicksMap.get(i);
        const isTaken = session.hiddenPicksTaken.has(i);
        return {
          slotIndex: i,
          taken: isTaken,
          pickedByPlayerId: pickInfo?.playerId ?? null,
          pickedByPlayerName: pickInfo?.playerName ?? null,
          // Card is included for all players as soon as the slot is taken.
          card: isTaken ? {
            cardId:           card.cardId,
            playerName:       card.playerName,
            basePositionType: card.basePositionType,
            rating:           card.rating,
            nationality:      card.nationality ?? null,
            club:             card.club ?? null,
            clubLogoUrl:      card.clubLogoUrl ?? null,
            altPositions:     card.altPositions ?? [],
            naturalPositions: card.naturalPositions ?? [card.basePositionType, ...(card.altPositions ?? [])],
            imageUrl:         card.imageUrl ?? null,
            pace:             card.pace,
            shooting:         card.shooting,
            passing:          card.passing,
            dribbling:        card.dribbling,
            defending:        card.defending,
            physical:         card.physical,
          } : null,
        };
      }),
      // Cards no one picked in the round that just ended — revealed to all.
      lastRoundLeftovers: session.lastRoundLeftovers.map((card) => ({
        cardId:           card.cardId,
        playerName:       card.playerName,
        basePositionType: card.basePositionType,
        rating:           card.rating,
        nationality:      card.nationality ?? null,
        club:             card.club ?? null,
        clubLogoUrl:      card.clubLogoUrl ?? null,
        altPositions:     card.altPositions ?? [],
        naturalPositions: card.naturalPositions ?? [card.basePositionType, ...(card.altPositions ?? [])],
        imageUrl:         card.imageUrl ?? null,
        pace:             card.pace,
        shooting:         card.shooting,
        passing:          card.passing,
        dribbling:        card.dribbling,
        defending:        card.defending,
        physical:         card.physical,
      })),
      turnTimeoutPolicy: session.turnTimeoutPolicy,
      status: session.status,
      // Ability draft: face-down pool state. Card *types* are never revealed for
      // unpicked cards; only the local player's own picked card type is sent.
      abilityDraft: session.abilityDraft
        ? this._buildAbilityDraftSnapshot(session.abilityDraft, localPlayerId)
        : null,
      // The local player's own chosen ability (type + lifecycle), private to
      // them and persisted for the whole game. Other players never see it here.
      myAbility:
        localPlayerId != null
          ? session.playerAbilities[localPlayerId] ?? null
          : null,
      // Public log of activated abilities (announced to everyone).
      abilityActivations: session.abilityActivations,
      // Whether the deterministic reveal pass has run for this activation
      // phase. Kept top-level (not nested in the status-gated `abilityActivation`
      // object below) so it stays available on every later snapshot — clients
      // use it to distinguish "everyone locked, reveal about to start" from
      // "reveal already happened" even after status has moved on to `subs`,
      // e.g. to skip replaying a reveal animation on reconnect.
      abilityActivationRevealed: session.abilityActivationRevealed,
      // Activation phase: who has resolved (used/discarded) vs still deciding —
      // without revealing pending players' card types.
      abilityActivation:
        session.status === 'ability_activation'
          ? {
              resolved: Object.fromEntries(
                session.players.map((p) => [
                  p.id,
                  (session.playerAbilities[p.id]?.status ?? 'pending') !==
                    'pending',
                ]),
              ),
            }
          : null,
      isFinished: session.isFinished,
      subsPhase: session.subsPhase
        ? this._buildSubsPhaseSnapshot(
            session.subsPhase,
            marks,
            localPlayerId,
            session.status === 'ability_activation',
          )
        : null,
      subsTimerSeconds: session.subsTimerSeconds,
      subsDeadlineAt: session.subsDeadlineAt,
      result: session.result,
      localPlayerId: localPlayerId ?? null,
      // Private scoring preview — only included when a specific player's
      // localPlayerId is known. Other players never see this value.
      scoringPreview: localPlayerId
        ? this._buildScoringPreview(session, localPlayerId)
        : null,
    };
  }

  // ── Effective turn order ──────────────────────────────────────────────────

  computeEffectiveTurnOrder(session: GameSession): string[] {
    const n = session.baseTurnOrder.length;
    if (n === 0) return [];
    const offset = (session.currentRound - 1) % n;
    return [
      ...session.baseTurnOrder.slice(offset),
      ...session.baseTurnOrder.slice(0, offset),
    ];
  }

  // ── Turn-index advancement ──────────────────────────────────────────────────
  //
  // A mid-game socket disconnect (handleDisconnect in rooms.gateway.ts) only
  // ever flips Player.isConnected — it never removes the player from
  // baseTurnOrder/session.players (that's what the SEPARATE, already-correct
  // removePlayer() below does for a PERMANENT kick/leave).
  //
  // Turn ORDER is deliberately connection-agnostic: a disconnected-but-still-
  // in-room player still gets their turn assigned to them in the correct
  // round/position, exactly like a connected player. What happens once they
  // hold it differs — that's entirely the gateway's job. `_scheduleTurnTimer`
  // (rooms.gateway.ts) checks whether the newly active player is connected;
  // if not, it arms a short grace timer (ACTIVE_TURN_DISCONNECT_GRACE_MS)
  // that AUTO-PICKS on their behalf (via `_autoPickCurrentPhase`, the same
  // logic a connected-but-slow player's full turnSeconds timeout already
  // used) rather than waiting forever or skipping them out of the round.
  // This guarantees a temporary disconnect can never leave a still-in-room
  // player with fewer drafted cards than everyone else — every round, every
  // player either picks for themselves or gets auto-picked, never neither.
  // (This replaced an earlier design where a disconnected player was instead
  // skipped OVER in turn order — that left them permanently missing that
  // round's card even after reconnecting. See git history / PROJECT_OVERVIEW
  // for that prior "Task 6" skip-based approach if you need the old shape.)

  /**
   * `fromIndex` itself, if it's still within `order` — or null once we've
   * run off the end (meaning this round is over: every position in
   * `order` from `fromIndex` onward has already had its turn assigned).
   * Deliberately NOT connection-aware — see the block comment above.
   */
  private _nextIndexInRound(order: string[], fromIndex: number): number | null {
    return fromIndex < order.length ? fromIndex : null;
  }

  /**
   * Resolves the next hidden-pick turn starting from the CURRENT
   * `session.currentTurnIndex` (the caller has already positioned it at the
   * candidate to try) — connection-agnostic, see the block comment above.
   * Falls through to wrapping the round (or finishing the draft) once this
   * round's pickers are exhausted. Shared by orderHiddenDeck (handing off
   * to the round's first hidden picker) and confirmHiddenReveal (handing off
   * to the next one) so the two call sites can't drift out of sync on this.
   */
  private _advanceHiddenPickTurn(session: GameSession): {
    session: GameSession;
    availableSlots?: number[];
  } {
    const n = session.baseTurnOrder.length;
    const effectiveOrder = this.computeEffectiveTurnOrder(session);
    const nextIdx = this._nextIndexInRound(
      effectiveOrder,
      Math.min(session.currentTurnIndex, n),
    );

    if (nextIdx !== null) {
      session.currentTurnIndex = nextIdx;
      const availableSlots = session.orderedHiddenDeck
        .map((_, i) => i)
        .filter((i) => !session.hiddenPicksTaken.has(i));
      session.turn = {
        turnId: uuidv4(),
        phase: 'hidden_pick',
        activePlayerId: effectiveOrder[nextIdx],
        activeSlotIndex: session.currentRoundSlotIndex,
        candidates: [],
        turnStartedAt: null,
      };
      return { session, availableSlots };
    }

    return this._wrapToNextRoundOrFinishDraft(session);
  }

  /**
   * Starts the next round (or finishes the draft if that was the last one).
   * Connection-agnostic — see the block comment above; the first player in
   * `effectiveOrder` becomes that round's first picker regardless of their
   * connection state. Factored out so orderHiddenDeck's and
   * confirmHiddenReveal's round-wrap paths can't drift out of sync.
   */
  private _wrapToNextRoundOrFinishDraft(session: GameSession): {
    session: GameSession;
    availableSlots?: number[];
  } {
    session.currentTurnIndex = 0;
    session.currentRound++;
    // Reveal the cards no one picked this round (the "final" leftovers).
    this._captureRoundLeftovers(session);

    if (session.currentRound > session.totalRounds) {
      return { session: this._enterBenchSelectionPhase(session) };
    }

    this._clearRoundHiddenState(session);
    const effectiveOrder = this.computeEffectiveTurnOrder(session);
    const firstIdx = this._nextIndexInRound(effectiveOrder, 0);

    if (firstIdx === null) {
      // Defensive only — an empty baseTurnOrder means the last player already
      // left, which tears the whole session down elsewhere (handleDisconnect's
      // "allGone" path in rooms.gateway.ts calls endSession), so this should
      // be unreachable in practice.
      session.turn = {
        turnId: uuidv4(),
        phase: 'selecting_position',
        activePlayerId: effectiveOrder[0],
        activeSlotIndex: null,
        candidates: [],
        turnStartedAt: null,
      };
      return { session };
    }

    session.currentTurnIndex = firstIdx;
    session.turn = {
      turnId: uuidv4(),
      phase: 'selecting_position',
      activePlayerId: effectiveOrder[firstIdx],
      activeSlotIndex: null,
      candidates: [],
      turnStartedAt: null,
    };
    return { session };
  }

  // ── Pick slot (first player, selecting_position → selecting_card) ─────────

  pickSlot(
    roomCode: string,
    senderId: string,
    turnId: string,
    slotIndex: number,
  ): { error: string } | { session: GameSession; candidates: DraftCard[] } {
    const session = this.getSessionByRoomCode(roomCode);
    if (!session) return { error: 'SESSION_NOT_FOUND' };
    if (session.status !== 'drafting') return { error: 'GAME_NOT_DRAFTING' };
    if (session.turn.phase !== 'selecting_position') return { error: 'WRONG_PHASE' };
    if (turnId !== session.turn.turnId) return { error: 'STALE_TURN' };
    if (senderId !== session.turn.activePlayerId) return { error: 'NOT_YOUR_TURN' };
    if (slotIndex < 0 || slotIndex > 10) return { error: 'SLOT_OUT_OF_RANGE' };

    const pitch = session.pitches[senderId];
    if (!pitch) return { error: 'PITCH_NOT_FOUND' };
    const slot = pitch.slots.find((s) => s.index === slotIndex);
    if (!slot) return { error: 'SLOT_NOT_FOUND' };
    if (slot.card !== null) return { error: 'SLOT_ALREADY_FILLED' };
    if (session.currentRoundSlotIndex !== null) return { error: 'ROUND_SLOT_ALREADY_CHOSEN' };

    const candidates = this.generateCandidates(
      slot.basePositionType,
      session.draftedCardIds,
      session.players.length,
      session.leagues,
      session,
    );
    session.currentRoundSlotIndex = slotIndex;
    session.turn.activeSlotIndex = slotIndex;
    session.roundCandidates = candidates;
    session.turn.candidates = candidates;
    session.turn.phase = 'selecting_card';

    return { session, candidates };
  }

  // ── Pick card (first player only — selecting_card → first_player_order) ───

  pickCard(
    roomCode: string,
    senderId: string,
    turnId: string,
    cardId: string,
  ): { error: string } | PickCardResult {
    const session = this.getSessionByRoomCode(roomCode);
    if (!session) return { error: 'SESSION_NOT_FOUND' };
    if (session.status !== 'drafting') return { error: 'GAME_NOT_DRAFTING' };
    if (session.turn.phase !== 'selecting_card') return { error: 'WRONG_PHASE' };
    if (turnId !== session.turn.turnId) return { error: 'STALE_TURN' };
    if (senderId !== session.turn.activePlayerId) return { error: 'NOT_YOUR_TURN' };

    const slotIndex = session.turn.activeSlotIndex;
    if (slotIndex === null) return { error: 'NO_ACTIVE_SLOT' };

    const card = session.turn.candidates.find((c) => c.cardId === cardId);
    if (!card) return { error: 'INVALID_CARD' };

    const pitch = session.pitches[senderId];
    if (!pitch) return { error: 'PITCH_NOT_FOUND' };
    const slot = pitch.slots.find((s) => s.index === slotIndex);
    if (!slot) return { error: 'SLOT_NOT_FOUND' };
    if (slot.card !== null) return { error: 'SLOT_ALREADY_FILLED' };

    // Place card
    slot.card = card;
    pitch.filledCount++;
    session.draftedCardIds.add(card.cardId);
    session.roundCandidates = session.roundCandidates.filter(
      (c) => c.cardId !== card.cardId,
    );
    this.logger.info(
      {
        event: 'card_drafted',
        roomCode,
        playerId: senderId,
        cardId: card.cardId,
        playerName: card.playerName,
        remainingInRoundPool: session.roundCandidates.length,
      },
      'Card drafted',
    );

    session.turn.candidates = [];
    session.turn.activeSlotIndex = null;

    // Solo game: skip hidden mechanic, wrap round immediately
    if (session.players.length === 1) {
      return this._advanceAfterSoloRound(session);
    }

    // Multi-player: first player must now order the remaining cards
    session.turn = {
      turnId: uuidv4(),
      phase: 'first_player_order',
      activePlayerId: senderId,
      activeSlotIndex: session.currentRoundSlotIndex,
      candidates: [],
      turnStartedAt: null,
    };
    return { session, orderPromptCards: session.roundCandidates };
  }

  // ── Order hidden deck (first_player_order → hidden_pick) ──────────────────

  orderHiddenDeck(
    roomCode: string,
    senderId: string,
    turnId: string,
    orderedCardIds: string[],
  ): { error: string } | OrderHiddenDeckResult {
    const session = this.getSessionByRoomCode(roomCode);
    if (!session) return { error: 'SESSION_NOT_FOUND' };
    if (session.status !== 'drafting') return { error: 'GAME_NOT_DRAFTING' };
    if (session.turn.phase !== 'first_player_order') return { error: 'WRONG_PHASE' };
    if (turnId !== session.turn.turnId) return { error: 'STALE_TURN' };
    if (senderId !== session.turn.activePlayerId) return { error: 'NOT_YOUR_TURN' };

    const remaining = session.roundCandidates;
    if (orderedCardIds.length !== remaining.length) {
      return { error: 'INVALID_ORDER_LENGTH' };
    }
    const remainingIds = new Set(remaining.map((c) => c.cardId));
    const uniqueOrderedIds = new Set(orderedCardIds);
    // A repeated id here would pass length + membership checks alone (both
    // only look at the SET of ids) while silently dropping one genuinely
    // remaining card entirely: the map below would place the repeated card
    // at two different hidden-deck slot indices, so two different players
    // could end up drafting the exact same card — the no-duplication
    // guarantee is a server invariant this endpoint has to enforce, not
    // something the client can be trusted to send correctly.
    if (
      uniqueOrderedIds.size !== orderedCardIds.length ||
      !orderedCardIds.every((id) => remainingIds.has(id))
    ) {
      return { error: 'INVALID_ORDER_IDS' };
    }

    // Store ordered deck
    session.orderedHiddenDeck = orderedCardIds.map(
      (id) => remaining.find((c) => c.cardId === id)!,
    );
    session.hiddenPicksTaken = new Set<number>();
    session.roundCandidates = [];

    // Advance turn index to the first hidden picker — skipping any
    // disconnected player(s) in the way, and wrapping the round entirely if
    // every remaining player this round turns out to be disconnected
    // (Task 6: disconnected-player turn-order fix).
    session.currentTurnIndex++;
    const result = this._advanceHiddenPickTurn(session);

    this.logger.info(
      {
        event: 'hidden_deck_ordered',
        roomCode,
        playerId: senderId,
        orderedSlots: session.orderedHiddenDeck.length,
        nextPicker: result.session.turn.activePlayerId,
      },
      'Hidden deck ordered',
    );

    return { session: result.session, availableSlots: result.availableSlots };
  }

  // ── Pick hidden slot (hidden_pick → hidden_pick | round wrap) ─────────────

  pickHiddenSlot(
    roomCode: string,
    senderId: string,
    turnId: string,
    slotIndex: number,
  ): { error: string } | PickHiddenSlotResult {
    const session = this.getSessionByRoomCode(roomCode);
    if (!session) return { error: 'SESSION_NOT_FOUND' };
    if (session.status !== 'drafting') return { error: 'GAME_NOT_DRAFTING' };
    if (session.turn.phase !== 'hidden_pick') return { error: 'WRONG_PHASE' };
    if (turnId !== session.turn.turnId) return { error: 'STALE_TURN' };
    if (senderId !== session.turn.activePlayerId) return { error: 'NOT_YOUR_TURN' };

    if (slotIndex < 0 || slotIndex >= session.orderedHiddenDeck.length) {
      return { error: 'SLOT_OUT_OF_RANGE' };
    }
    if (session.hiddenPicksTaken.has(slotIndex)) {
      return { error: 'SLOT_ALREADY_TAKEN' };
    }

    const card = session.orderedHiddenDeck[slotIndex];
    const roundSlotIndex = session.turn.activeSlotIndex!;

    const pitch = session.pitches[senderId];
    if (!pitch) return { error: 'PITCH_NOT_FOUND' };
    const slot = pitch.slots.find((s) => s.index === roundSlotIndex);
    if (!slot) return { error: 'SLOT_NOT_FOUND' };
    if (slot.card !== null) return { error: 'SLOT_ALREADY_FILLED' };

    slot.card = card;
    pitch.filledCount++;
    session.draftedCardIds.add(card.cardId);
    session.hiddenPicksTaken.add(slotIndex);

    const picker = session.players.find((p) => p.id === senderId);
    session.hiddenPicksMap.set(slotIndex, {
      playerId: senderId,
      playerName: picker?.displayName ?? '',
    });

    this.logger.info(
      {
        event: 'hidden_slot_picked',
        roomCode,
        playerId: senderId,
        slotIndex,
        cardId: card.cardId,
        playerName: card.playerName,
      },
      'Hidden slot picked',
    );

    // Enter reveal phase — turn does NOT advance until confirmHiddenReveal is called.
    session.hiddenPickReveal = {
      pickerPlayerId: senderId,
      timeoutAt: Date.now() + 5000,
    };
    session.turn = {
      turnId: uuidv4(),
      phase: 'hidden_pick_reveal',
      activePlayerId: senderId,
      activeSlotIndex: session.currentRoundSlotIndex,
      candidates: [],
      turnStartedAt: null,
    };

    return { session, revealedCard: card };
  }

  // ── Confirm hidden reveal (hidden_pick_reveal → hidden_pick | round wrap) ──

  confirmHiddenReveal(
    roomCode: string,
    turnId: string,
    senderId?: string,
  ): { error: string } | ConfirmHiddenRevealResult {
    const session = this.getSessionByRoomCode(roomCode);
    if (!session) return { error: 'SESSION_NOT_FOUND' };
    if (session.status !== 'drafting') return { error: 'GAME_NOT_DRAFTING' };
    if (session.turn.phase !== 'hidden_pick_reveal') return { error: 'WRONG_PHASE' };
    if (turnId !== session.turn.turnId) return { error: 'STALE_TURN' };
    if (senderId && senderId !== session.hiddenPickReveal?.pickerPlayerId) {
      return { error: 'NOT_THE_PICKER' };
    }

    session.hiddenPickReveal = null;

    // Advance the turn — skipping any disconnected player(s) in the way, and
    // wrapping the round (or finishing the draft) if every remaining player
    // this round turns out to be disconnected (Task 6: disconnected-player
    // turn-order fix). Shared with orderHiddenDeck via _advanceHiddenPickTurn
    // so the two call sites can't drift out of sync on this logic.
    session.currentTurnIndex++;
    const result = this._advanceHiddenPickTurn(session);
    return { session: result.session, nextAvailableSlots: result.availableSlots };
  }

  // ── Remove player (kick or leave_permanently during game) ─────────────────

  removePlayer(
    roomCode: string,
    playerId: string,
  ): RemovePlayerResult | null {
    const session = this.getSessionByRoomCode(roomCode);
    if (!session) return null;

    const playerIndex = session.players.findIndex((p) => p.id === playerId);
    if (playerIndex === -1) return null;

    // Ability draft (Task 3.6): a removed player can't be waited on for a
    // pick, so drop them from the pick order entirely (no card is drafted
    // on their behalf) and recompute whether every REMAINING picker has
    // now picked — the exact same `allPicked` signal pickAbilityCard
    // returns, so the gateway can reuse `_afterAbilityPick`'s existing
    // post-pick orchestration instead of duplicating it.
    let abilityDraftAllPicked: boolean | undefined;
    if (session.status === 'ability_draft' && session.abilityDraft) {
      const ad = session.abilityDraft;
      const pickIdx = ad.pickOrder.indexOf(playerId);
      if (pickIdx !== -1) {
        ad.pickOrder.splice(pickIdx, 1);
        if (pickIdx < ad.currentPickIndex) {
          ad.currentPickIndex = Math.max(0, ad.currentPickIndex - 1);
        }
        abilityDraftAllPicked = ad.currentPickIndex >= ad.pickOrder.length;
      }
    }

    // Bench selection (Track B): a removed player's incomplete bench pick can
    // never complete (nobody remains who can act for them), which would
    // permanently block `_allBenchSelectionsComplete`'s all-players check for
    // everyone else. Deleting the entry (same pattern as the lineup_edit case
    // below) removes it from that check entirely; if every REMAINING player
    // already has a complete bench selection, this removal is itself the
    // trigger that advances the game into ability_activation — the exact
    // same inline transition `pickSub` makes for a real last pick.
    if (session.status === 'bench_selection' && session.subsPhase) {
      delete session.subsPhase.userSubs[playerId];
      if (this._allBenchSelectionsComplete(session)) {
        this._enterActivationPhase(session);
      }
    }

    // Ability activation (Task 3.6): a removed player can't resolve their
    // own pending ability, so auto-discard it — the exact same state
    // mutation discardAbility makes — then run the exact same completion
    // check it does, instead of duplicating either.
    let abilityActivationAllResolved: boolean | undefined;
    if (session.status === 'ability_activation') {
      const ability = session.playerAbilities[playerId];
      if (ability && ability.status === 'pending') {
        ability.status = 'discarded';
      }
      abilityActivationAllResolved = !this._hasPendingAbilities(session);
    }

    // Lineup edit (Phase 5 audit, Track B): confirmLineup's "has everyone
    // confirmed" check (`Object.values(session.subsPhase.userSubs).every(s
    // => s.lineupConfirmed)`) iterates every entry ever created for this
    // phase — a removed player's entry, if left behind, can NEVER become
    // lineupConfirmed (nobody remains who can act for them), which
    // permanently blocks that check for every other player still in the
    // room. With no subs timer configured (a valid, null-by-default host
    // setting), this was a full, unrecoverable game soft-lock — the ONLY way
    // out was forceFinalizeLineupEdit, which only exists at all if a timer
    // happens to be armed. Deleting the entry (mirroring the existing
    // `delete session.pitches[playerId]` pattern just below) removes it from
    // the completion check entirely, so remaining players confirming
    // normally is sufficient again — exactly as if the departed player had
    // never joined this phase. The "is everyone now confirmed" check has to
    // run here (before session.players is spliced below) so it sees the
    // up-to-date userSubs map, but the actual finalize call is deferred until
    // AFTER the splice (see below `_finalizeDraft`/`subsTournamentStarting`
    // call site) so a departed player is excluded from final scoring, exactly
    // like every other "game ends because someone left" path already is.
    let subsAllConfirmedAfterRemoval = false;
    if (session.status === 'lineup_edit' && session.subsPhase) {
      delete session.subsPhase.userSubs[playerId];
      const remaining = Object.values(session.subsPhase.userSubs);
      subsAllConfirmedAfterRemoval = remaining.length > 0 && remaining.every((s) => s.lineupConfirmed);
    }

    // Tournament (Phase 7 audit): the bracket (session.tournament) is a
    // self-sufficient, frozen structure built once at beginTournament —
    // every match is pre-computed server-side and needs no live input from
    // players except pressing Ready for their own round. A departed real
    // participant's ready_check id (session.tournament.readyPlayerIds is
    // keyed by the FROZEN bracket's participantId, never session.players)
    // could otherwise never become ready again — nobody remains who can act
    // for them — which stalled the round for every other real participant
    // for the full 60s auto-ready timeout rather than resolving instantly,
    // same class of gap as the ability_activation/subs cases above. Marking
    // them ready immediately (the exact mutation autoReadyRemainingPlayers
    // already makes per-id) lets the round proceed the moment everyone
    // ELSE is actually ready, instead of always waiting out the timer.
    let tournamentAllReadyAfterRemoval: boolean | undefined;
    if (session.status === 'tournament' && session.tournament?.phase === 'ready_check') {
      const t = session.tournament;
      const realIds = this._currentRoundRealParticipantIds(t);
      if (realIds.includes(playerId)) {
        if (!t.readyPlayerIds.includes(playerId)) t.readyPlayerIds.push(playerId);
        tournamentAllReadyAfterRemoval = realIds.every((id) => t.readyPlayerIds.includes(id));
      }
    }

    session.players.splice(playerIndex, 1);
    delete session.pitches[playerId];

    // Now that the departed player is fully out of session.players/pitches,
    // it's safe to finalize scoring (computeAllScores reads session.players)
    // without them showing up in the result. Same tournament fork
    // confirmLineup/forceFinalizeLineupEdit already make: a tournament-enabled
    // session hands off to the bracket instead of finishing outright — the
    // gateway calls beginBracketReveal when it sees this flag (see
    // _afterPlayerRemoved).
    let subsTournamentStarting: boolean | undefined;
    if (subsAllConfirmedAfterRemoval) {
      if (session.tournamentEnabled) {
        subsTournamentStarting = true;
      } else {
        this._finalizeDraft(session);
      }
    }

    const turnIndex = session.baseTurnOrder.indexOf(playerId);
    if (turnIndex !== -1) {
      session.baseTurnOrder.splice(turnIndex, 1);

      if (session.baseTurnOrder.length === 0) {
        session.isFinished = true;
        session.status = 'finished';
        session.currentTurnIndex = 0;
      } else {
        if (turnIndex < session.currentTurnIndex) {
          session.currentTurnIndex = Math.max(0, session.currentTurnIndex - 1);
        } else if (session.currentTurnIndex >= session.baseTurnOrder.length) {
          session.currentTurnIndex = 0;
          session.currentRound++;
        }
      }
    }

    if (session.isFinished) return { session };
    if (subsTournamentStarting) return { session, subsTournamentStarting };
    if (tournamentAllReadyAfterRemoval !== undefined) {
      return { session, tournamentAllReadyAfterRemoval };
    }

    // Removed player held the active turn — advance it. Scoped to
    // 'drafting' status only: `session.turn` is initialized at session
    // creation (before an ability draft, if any, even begins) and its
    // 'selecting_position'/'selecting_card'/etc. phases are only ever
    // meaningful once status is actually 'drafting' — running this during
    // 'ability_draft'/'bench_selection'/'ability_activation'/'lineup_edit'
    // would overwrite turn state with a meaningless reassignment that
    // doesn't address the real gap in those phases (handled above instead).
    if (session.status === 'drafting' && session.turn.activePlayerId === playerId) {
      const phase = session.turn.phase;

      if (phase === 'first_player_order') {
        // Auto-shuffle remaining candidates so the game can continue
        return this._autoOrderHiddenDeck(session);
      }

      if (phase === 'hidden_pick') {
        // Skip this player's pick — they get no card this round
        return this._advanceHiddenPick(session);
      }

      if (phase === 'hidden_pick_reveal') {
        // Card was already placed; just advance past the reveal window.
        session.hiddenPickReveal = null;
        return this._advanceHiddenPick(session);
      }

      // selecting_position or selecting_card (shouldn't normally occur mid-pick,
      // but handle defensively: assign next player)
      if (session.baseTurnOrder.length > 0) {
        const effectiveOrder = this.computeEffectiveTurnOrder(session);
        const nextPlayerId =
          effectiveOrder[session.currentTurnIndex] ?? session.players[0]?.id ?? '';

        if (session.currentRoundSlotIndex !== null) {
          // Round slot already chosen — if there are remaining candidates, proceed
          const nextCandidates = session.roundCandidates;
          session.turn = {
            turnId: uuidv4(),
            phase: 'selecting_card',
            activePlayerId: nextPlayerId,
            activeSlotIndex: session.currentRoundSlotIndex,
            candidates: nextCandidates,
            turnStartedAt: null,
          };
        } else {
          session.turn = {
            turnId: uuidv4(),
            phase: 'selecting_position',
            activePlayerId: nextPlayerId,
            activeSlotIndex: null,
            candidates: [],
            turnStartedAt: null,
          };
        }
      }
    }

    return { session, abilityDraftAllPicked, abilityActivationAllResolved };
  }

  // ── Connection ────────────────────────────────────────────────────────────

  updatePlayerConnection(
    roomCode: string,
    playerId: string,
    isConnected: boolean,
  ): GameSession | null {
    const session = this.getSessionByRoomCode(roomCode);
    if (!session) return null;
    const player = session.players.find((p) => p.id === playerId);
    if (player) player.isConnected = isConnected;
    return session;
  }

  // ── End game ──────────────────────────────────────────────────────────────

  declareForfeitWin(session: GameSession, winnerId: string): void {
    const winner = session.players.find((p) => p.id === winnerId);
    if (!winner) return;

    const allScores = computeAllScores(session);

    const nonWinners = session.players
      .filter((p) => p.id !== winnerId)
      .map((p) => ({ player: p, breakdown: allScores[p.id] ?? emptyBreakdown() }))
      .sort((a, b) => b.breakdown.finalScore - a.breakdown.finalScore);

    const winnerBreakdown = allScores[winnerId] ?? emptyBreakdown();

    session.isFinished = true;
    session.status = 'finished';
    session.result = {
      reason: 'forfeit',
      players: [
        {
          playerId: winner.id,
          displayName: winner.displayName,
          rank: 1,
          score: Math.round(winnerBreakdown.finalScore),
          scoreBreakdown: winnerBreakdown,
        },
        ...nonWinners.map((nw, i) => ({
          playerId: nw.player.id,
          displayName: nw.player.displayName,
          rank: i + 2,
          score: Math.round(nw.breakdown.finalScore),
          scoreBreakdown: nw.breakdown,
        })),
      ],
    };
  }

  endSession(roomCode: string): void {
    const id = this.roomToSession.get(roomCode);
    if (!id) return;

    // Task 2.3: the single choke point every game-end path (natural finish,
    // forfeit, abandoned-but-resolved) already passes through. Only records
    // when the session actually reached an end state with a real result —
    // session.result is null for rooms swept while still genuinely
    // mid-game-or-never-started (e.g. a stale empty lobby), and there's
    // nothing meaningful to record for those.
    const session = this.sessions.get(id);
    if (session?.result) {
      const durationSeconds = Math.round((Date.now() - session.createdAt) / 1000);
      this.matchHistoryService.recordMatch(
        roomCode,
        durationSeconds,
        session.result.players.map((p) => ({
          playerId: p.playerId,
          displayName: p.displayName,
          score: p.score,
          rank: p.rank,
        })),
      );
    }

    this.sessions.delete(id);
    this.roomToSession.delete(roomCode);
  }

  // ── Lookups ───────────────────────────────────────────────────────────────

  getSession(sessionId: string): GameSession | undefined {
    return this.sessions.get(sessionId);
  }

  getSessionByRoomCode(roomCode: string): GameSession | undefined {
    const id = this.roomToSession.get(roomCode);
    return id ? this.sessions.get(id) : undefined;
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /** Computes the hidden-pick available slots for the active player. */
  computeAvailableHiddenSlots(session: GameSession): number[] {
    return session.orderedHiddenDeck
      .map((_, i) => i)
      .filter((i) => !session.hiddenPicksTaken.has(i));
  }

  /**
   * Solo-game fast path: after the only player picks their card, advance
   * the round immediately (no ordering, no hidden picks needed).
   */
  private _advanceAfterSoloRound(session: GameSession): PickCardResult {
    session.currentTurnIndex = 0;
    session.currentRound++;
    session.currentRoundSlotIndex = null;
    session.roundCandidates = [];

    if (session.currentRound > session.totalRounds) {
      return { session: this._enterBenchSelectionPhase(session), orderPromptCards: null };
    }

    const effectiveOrder = this.computeEffectiveTurnOrder(session);
    session.turn = {
      turnId: uuidv4(),
      phase: 'selecting_position',
      activePlayerId: effectiveOrder[0],
      activeSlotIndex: null,
      candidates: [],
      turnStartedAt: null,
    };
    return { session, orderPromptCards: null };
  }

  /**
   * Auto-order remaining candidates (random) when the first player leaves
   * during `first_player_order`. Transitions to `hidden_pick` for the next player.
   */
  private _autoOrderHiddenDeck(session: GameSession): RemovePlayerResult {
    if (session.baseTurnOrder.length === 0) return { session };

    session.orderedHiddenDeck = this.shuffle(session.roundCandidates);
    session.hiddenPicksTaken = new Set<number>();
    session.hiddenPicksMap = new Map();
    session.hiddenPickReveal = null;
    session.roundCandidates = [];

    // currentTurnIndex was already pointing to the first player (index 0 in round).
    // The first player has been removed from baseTurnOrder, so currentTurnIndex
    // is already correct or needs adjustment (handled by the splice logic above).
    const effectiveOrder = this.computeEffectiveTurnOrder(session);
    const nextPlayerId = effectiveOrder[session.currentTurnIndex % effectiveOrder.length];
    const autoHiddenPickSlots = session.orderedHiddenDeck.map((_, i) => i);

    session.turn = {
      turnId: uuidv4(),
      phase: 'hidden_pick',
      activePlayerId: nextPlayerId,
      activeSlotIndex: session.currentRoundSlotIndex,
      candidates: [],
      turnStartedAt: null,
    };

    return { session, autoHiddenPickSlots };
  }

  /**
   * Advances a `hidden_pick` turn when the active picker is removed.
   * They simply do not pick a card this round.
   */
  private _advanceHiddenPick(session: GameSession): RemovePlayerResult {
    if (session.baseTurnOrder.length === 0) return { session };

    const n = session.baseTurnOrder.length;
    // currentTurnIndex may have already been decremented by the splice above;
    // clamp to valid range.
    session.currentTurnIndex = Math.min(session.currentTurnIndex, n - 1);
    const roundWrapped = session.currentTurnIndex >= n;

    if (roundWrapped) {
      session.currentTurnIndex = 0;
      session.currentRound++;
      this._captureRoundLeftovers(session);

      if (session.currentRound > session.totalRounds) {
        this._enterBenchSelectionPhase(session);
        return { session };
      }

      this._clearRoundHiddenState(session);
      const effectiveOrder = this.computeEffectiveTurnOrder(session);
      session.turn = {
        turnId: uuidv4(),
        phase: 'selecting_position',
        activePlayerId: effectiveOrder[0],
        activeSlotIndex: null,
        candidates: [],
        turnStartedAt: null,
      };
      return { session };
    }

    const effectiveOrder = this.computeEffectiveTurnOrder(session);
    const nextPlayerId = effectiveOrder[session.currentTurnIndex];
    const autoHiddenPickSlots = this.computeAvailableHiddenSlots(session);

    session.turn = {
      turnId: uuidv4(),
      phase: 'hidden_pick',
      activePlayerId: nextPlayerId,
      activeSlotIndex: session.currentRoundSlotIndex,
      candidates: [],
      turnStartedAt: null,
    };
    return { session, autoHiddenPickSlots };
  }

  /**
   * Builds the private scoring preview sent only to the local player.
   * Line bonuses are not included (they require comparing all players) —
   * only the base total and chemistry bonuses are shown in-game.
   */
  // Delegates to computeLivePreview (scoring.ts), which reuses the exact same
  // captain/red/yellow ability-effect logic as the final computeAllScores —
  // this used to be a separate, simpler calculation that ignored ability
  // effects entirely, so activating a captain/red/yellow card never moved
  // the live total shown during the game, only the final score at the end.
  private _buildScoringPreview(session: GameSession, playerId: string): object | null {
    return computeLivePreview(session, playerId);
  }

  private _clearRoundHiddenState(session: GameSession): void {
    session.currentRoundSlotIndex = null;
    session.roundCandidates = [];
    session.orderedHiddenDeck = [];
    session.hiddenPicksTaken = new Set<number>();
    session.hiddenPicksMap = new Map();
    session.hiddenPickReveal = null;
  }

  /**
   * Snapshots the hidden-deck cards that no one picked this round so they can be
   * revealed to all players. Call BEFORE `_clearRoundHiddenState`.
   */
  private _captureRoundLeftovers(session: GameSession): void {
    session.lastRoundLeftovers = session.orderedHiddenDeck.filter(
      (_, i) => !session.hiddenPicksTaken.has(i),
    );
  }

  // ── Sub-positions ─────────────────────────────────────────────────────────

  private static readonly SUB_POSITIONS: Record<SubPositionGroup, Set<string>> = {
    att: new Set(['ST', 'CF', 'LW', 'RW', 'CAM']),
    mid: new Set(['CM', 'CDM', 'LM', 'RM', 'CAM']),
    def: new Set(['CB', 'LB', 'RB', 'GK']),
    // Extra Bench card: any position is eligible.
    extra: new Set([
      'GK', 'LB', 'CB', 'RB', 'CDM', 'CM', 'CAM', 'LM', 'RM', 'LW', 'RW', 'CF', 'ST',
    ]),
  };

  // ── Bench selection (Track B step 2) ────────────────────────────────────────

  /**
   * Transitions the drafted starting XI into the bench-selection phase (Track
   * B step 2: "choose 3 bench players") — att/mid/def spin/pick only, no free
   * swapping and no Extra Bench slot yet (that ability hasn't resolved). Once
   * every player's bench selection is complete, `pickSub` advances the game
   * into `_enterActivationPhase` (step 3).
   */
  private _enterBenchSelectionPhase(session: GameSession): GameSession {
    this._clearRoundHiddenState(session);
    session.lastRoundLeftovers = [];
    session.status = 'bench_selection';
    const userSubs: Record<string, UserSubstitutions> = {};
    for (const player of session.players) {
      userSubs[player.id] = { isComplete: false, lineupConfirmed: false };
    }
    session.subsPhase = { userSubs };
    // Arm the shared subs deadline for bench_selection (Track B step 2).
    // Cleared on entry to ability_activation; re-armed fresh for lineup_edit.
    // The gateway's `_maybeArmSubsTimer` watches this and calls
    // `forceFinalizeBenchSelection` when it expires so an absent player
    // cannot deadlock the room forever.
    session.subsDeadlineAt =
      session.subsTimerSeconds !== null
        ? Date.now() + session.subsTimerSeconds * 1000
        : null;
    return session;
  }

  private _allBenchSelectionsComplete(session: GameSession): boolean {
    const userSubs = session.subsPhase?.userSubs ?? {};
    const all = Object.values(userSubs);
    return all.length > 0 && all.every((s) => s.isComplete);
  }

  // ── Ability activation (Track B step 3) ─────────────────────────────────────

  /**
   * Transitions the session from bench selection into the ability-activation
   * phase, where each player uses or discards their card before editing their
   * final lineup. If no player holds a pending ability (shouldn't happen —
   * everyone drafts one), skips straight to lineup_edit.
   */
  private _enterActivationPhase(session: GameSession): GameSession {
    this._clearRoundHiddenState(session);
    session.lastRoundLeftovers = [];
    session.status = 'ability_activation';
    session.abilityActivationRevealed = false;
    // Bench-selection deadline no longer applies — ability_activation has its
    // own `abilityActivationDeadlineAt`. Clearing here also forces the
    // gateway to drop any armed bench timer before re-arming later for
    // lineup_edit with a fresh `subsDeadlineAt`.
    session.subsDeadlineAt = null;
    if (!this._hasPendingAbilities(session)) {
      return this._enterLineupEditPhase(session);
    }
    // Host-configured seconds per player for this phase (Room.
    // abilityTimerSeconds) — null means no limit, the exact same semantics
    // turnTimerSeconds/subsTimerSeconds already use elsewhere: the host is
    // explicitly accepting that an unresponsive player can hold up this
    // phase indefinitely, the same tradeoff already available for subs.
    // _maybeArmAbilityActivationTimer (rooms.gateway.ts) already treats a
    // null deadline as "don't arm a timer" — nothing else to change there.
    session.abilityActivationDeadlineAt = session.abilityTimerSeconds !== null
      ? Date.now() + session.abilityTimerSeconds * 1000
      : null;
    return session;
  }

  private _hasPendingAbilities(session: GameSession): boolean {
    return Object.values(session.playerAbilities).some(
      (a) => a.status === 'pending',
    );
  }

  private _displayName(session: GameSession, playerId?: string): string {
    return (
      session.players.find((p) => p.id === playerId)?.displayName ?? '—'
    );
  }

  private _slotCardName(
    session: GameSession,
    userId: string,
    slotIndex: number,
  ): string | null {
    const slot = session.pitches[userId]?.slots.find(
      (s) => s.index === slotIndex,
    );
    return slot?.card?.playerName ?? null;
  }

  /** Discards the local player's ability without using it. */
  discardAbility(
    roomCode: string,
    playerId: string,
  ): { error: string } | { session: GameSession; allResolved: boolean } {
    const session = this.getSessionByRoomCode(roomCode);
    if (!session) return { error: 'SESSION_NOT_FOUND' };
    if (session.status !== 'ability_activation') {
      return { error: 'NOT_ACTIVATION_PHASE' };
    }
    const ability = session.playerAbilities[playerId];
    if (!ability || ability.status !== 'pending') {
      return { error: 'NO_PENDING_ABILITY' };
    }
    ability.status = 'discarded';
    return { session, allResolved: !this._hasPendingAbilities(session) };
  }

  /**
   * Commits the local player's ability with a target. Validates the choice and
   * freezes its public announcement text (`pendingSummary`), but — unlike the
   * old immediate-effect behavior — does NOT touch the board or publish
   * anything into `session.abilityActivations` yet. Every player commits
   * against the same static, pre-reveal board (nothing moves until reveal),
   * so choices are effectively simultaneous and hidden from each other. Once
   * every player has committed (`allResolved`), the caller must invoke
   * `revealAbilityActivations` to apply effects and publish the log for
   * everyone at once — see `_revealAbilityActivations`.
   */
  activateAbility(
    roomCode: string,
    playerId: string,
    payload: {
      ownSlotIndex?: number;
      targetUserId?: string;
      targetSlotIndex?: number;
      /** coach: the new (non-GK) position to add to the targeted own player. */
      coachedPosition?: string;
      /** red/sub: rival bench group (att/mid/def). XOR with targetSlotIndex. */
      targetBenchGroup?: string;
      /** coach: own bench group (att/mid/def). XOR with ownSlotIndex. */
      ownBenchGroup?: string;
    },
  ): { error: string } | { session: GameSession; allResolved: boolean } {
    const session = this.getSessionByRoomCode(roomCode);
    if (!session) return { error: 'SESSION_NOT_FOUND' };
    if (session.status !== 'ability_activation') {
      return { error: 'NOT_ACTIVATION_PHASE' };
    }
    const ability = session.playerAbilities[playerId];
    if (!ability || ability.status !== 'pending') {
      return { error: 'NO_PENDING_ABILITY' };
    }

    const abilityBenchGroups = ['att', 'mid', 'def'] as const;
    type AbilityBenchGroup = (typeof abilityBenchGroups)[number];
    const asAbilityBenchGroup = (g?: string): AbilityBenchGroup | null =>
      g != null && (abilityBenchGroups as readonly string[]).includes(g)
        ? (g as AbilityBenchGroup)
        : null;

    const ownFilled = (idx?: number) =>
      idx != null &&
      session.pitches[playerId]?.slots.find((s) => s.index === idx)?.card != null;
    const rivalFilled = (uid?: string, idx?: number) =>
      uid != null &&
      uid !== playerId &&
      idx != null &&
      session.pitches[uid]?.slots.find((s) => s.index === idx)?.card != null;
    const slotPos = (uid: string, idx: number) =>
      session.pitches[uid]?.slots.find((s) => s.index === idx)?.basePositionType;
    const slotCardId = (uid: string, idx: number) =>
      session.pitches[uid]?.slots.find((s) => s.index === idx)?.card?.cardId;

    const benchCardOf = (
      uid: string,
      group: AbilityBenchGroup,
    ): DraftCard | null => {
      const slot = session.subsPhase?.userSubs[uid]?.[group];
      if (!slot) return null;
      return slot.benchedCard ?? slot.chosenCard ?? null;
    };
    const rivalBenchCard = (uid?: string, group?: AbilityBenchGroup) =>
      uid != null && uid !== playerId && group != null
        ? benchCardOf(uid, group)
        : null;
    const ownBenchCard = (group?: AbilityBenchGroup) =>
      group != null ? benchCardOf(playerId, group) : null;

    let summary: string;
    switch (ability.type) {
      case 'captain': {
        // Starting XI only — bench targeting is intentionally rejected.
        if (!ownFilled(payload.ownSlotIndex)) return { error: 'INVALID_TARGET' };
        ability.sourceSlotIndex = payload.ownSlotIndex;
        ability.sourceBenchGroup = undefined;
        // Track the captained CARD (not the slot) so the effect follows it if
        // this player rearranges their OWN lineup in the subs phase. This is
        // intentionally NOT cross-owner: scoring.ts only ever looks for this
        // card id within THIS player's own current slots, so if a Sub
        // ability later moves the card to a different player's pitch, the
        // bonus simply stops applying — it does not transfer to the new
        // owner. See scoring.spec.ts's captain/red cross-ownership tests.
        ability.targetPlayerId = slotCardId(playerId, payload.ownSlotIndex!);
        summary = `Captain on ${this._slotCardName(session, playerId, payload.ownSlotIndex!)}`;
        break;
      }
      case 'yellow': {
        if (
          payload.targetUserId == null ||
          payload.targetUserId === playerId ||
          !session.players.some((p) => p.id === payload.targetUserId)
        ) {
          return { error: 'INVALID_TARGET' };
        }
        ability.targetUserId = payload.targetUserId;
        summary = `Yellow Card on ${this._displayName(session, payload.targetUserId)} (−20)`;
        break;
      }
      case 'red': {
        const rivalUid = payload.targetUserId;
        const benchGroup = asAbilityBenchGroup(payload.targetBenchGroup);
        const hasPitch = rivalFilled(rivalUid, payload.targetSlotIndex);
        const hasBench = rivalBenchCard(rivalUid, benchGroup ?? undefined) != null;
        // Pitch XOR bench — not both, not neither.
        if (
          rivalUid == null ||
          (hasPitch && hasBench) ||
          (!hasPitch && !hasBench) ||
          (payload.targetSlotIndex != null && benchGroup != null)
        ) {
          return { error: 'INVALID_TARGET' };
        }
        ability.targetUserId = rivalUid;
        if (hasBench && benchGroup) {
          const card = rivalBenchCard(rivalUid, benchGroup)!;
          ability.targetBenchGroup = benchGroup;
          ability.targetSlotIndex = undefined;
          ability.targetPlayerId = card.cardId;
          summary = `Red Card on ${card.playerName} (${this._displayName(session, rivalUid)}, bench)`;
        } else {
          ability.targetSlotIndex = payload.targetSlotIndex;
          ability.targetBenchGroup = undefined;
          ability.targetPlayerId = slotCardId(rivalUid!, payload.targetSlotIndex!);
          const name = this._slotCardName(session, rivalUid!, payload.targetSlotIndex!);
          summary = `Red Card on ${name} (${this._displayName(session, rivalUid)})`;
        }
        break;
      }
      case 'extra_bench': {
        summary = 'Extra Bench activated';
        break;
      }
      case 'sub': {
        // Caster side is always own starting-XI pitch.
        if (!ownFilled(payload.ownSlotIndex)) return { error: 'INVALID_TARGET' };
        const rivalUid = payload.targetUserId;
        const benchGroup = asAbilityBenchGroup(payload.targetBenchGroup);
        const hasPitch = rivalFilled(rivalUid, payload.targetSlotIndex);
        const benchCard = rivalBenchCard(rivalUid, benchGroup ?? undefined);
        const hasBench = benchCard != null;
        if (
          rivalUid == null ||
          (hasPitch && hasBench) ||
          (!hasPitch && !hasBench) ||
          (payload.targetSlotIndex != null && benchGroup != null)
        ) {
          return { error: 'INVALID_TARGET' };
        }
        const ownPos = slotPos(playerId, payload.ownSlotIndex!);
        if (hasBench && benchGroup && benchCard) {
          // Position match: own pitch slot type === rival bench card's base type.
          if (ownPos !== benchCard.basePositionType) {
            return { error: 'POSITION_MISMATCH' };
          }
          ability.sourceSlotIndex = payload.ownSlotIndex;
          ability.targetUserId = rivalUid;
          ability.targetBenchGroup = benchGroup;
          ability.targetSlotIndex = undefined;
          const mine = this._slotCardName(session, playerId, payload.ownSlotIndex!);
          summary = `Sub swap: ${mine} ↔ ${benchCard.playerName} (${this._displayName(session, rivalUid)}, bench)`;
        } else {
          if (
            ownPos !==
            slotPos(rivalUid!, payload.targetSlotIndex!)
          ) {
            return { error: 'POSITION_MISMATCH' };
          }
          ability.sourceSlotIndex = payload.ownSlotIndex;
          ability.targetUserId = rivalUid;
          ability.targetSlotIndex = payload.targetSlotIndex;
          ability.targetBenchGroup = undefined;
          const mine = this._slotCardName(session, playerId, payload.ownSlotIndex!);
          const theirs = this._slotCardName(session, rivalUid!, payload.targetSlotIndex!);
          summary = `Sub swap: ${mine} ↔ ${theirs} (${this._displayName(session, rivalUid)})`;
        }
        // The actual card swap is deferred to `_revealAbilityActivations`.
        break;
      }
      case 'coach': {
        const ownBenchGroup = asAbilityBenchGroup(payload.ownBenchGroup);
        const hasPitch = ownFilled(payload.ownSlotIndex);
        const benchCard = ownBenchCard(ownBenchGroup ?? undefined);
        const hasBench = benchCard != null;
        if (
          (hasPitch && hasBench) ||
          (!hasPitch && !hasBench) ||
          (payload.ownSlotIndex != null && ownBenchGroup != null)
        ) {
          return { error: 'INVALID_TARGET' };
        }
        const card = hasBench
          ? benchCard!
          : session.pitches[playerId]!.slots.find(
              (s) => s.index === payload.ownSlotIndex,
            )!.card!;
        // GK is excluded on the TARGET side: you cannot coach a goalkeeper.
        if (card.basePositionType === 'GK') {
          return { error: 'CANNOT_COACH_GK' };
        }
        const newPos = payload.coachedPosition as BasePositionType | undefined;
        if (newPos == null || !COACHABLE_POSITIONS.includes(newPos)) {
          return { error: 'INVALID_COACH_POSITION' };
        }
        if (
          this.cardPositionSet(card).has(newPos) ||
          session.coachedPositions[card.cardId] != null
        ) {
          return { error: 'POSITION_ALREADY_OWNED' };
        }
        if (hasBench && ownBenchGroup) {
          ability.sourceBenchGroup = ownBenchGroup;
          ability.sourceSlotIndex = undefined;
        } else {
          ability.sourceSlotIndex = payload.ownSlotIndex;
          ability.sourceBenchGroup = undefined;
        }
        ability.targetPlayerId = card.cardId;
        ability.coachedPosition = newPos;
        summary = `Coach: +${newPos} to ${card.playerName}${hasBench ? ' (bench)' : ''}`;
        break;
      }
    }

    ability.status = 'used';
    ability.pendingSummary = summary;
    return { session, allResolved: !this._hasPendingAbilities(session) };
  }

  /**
   * Applies every committed ability's effect and publishes the activation log,
   * all at once, in stable `baseTurnOrder` — the "reveal" half of hidden
   * simultaneous ability commitment (see `activateAbility`'s doc comment).
   *
   * Only `sub` has a deferred effect to apply here: captain/red/yellow are
   * resolved lazily by `scoring.ts` via cardId/userId lookups against
   * whatever the final board looks like, so reveal order can't change their
   * outcome (in particular, red beating captain on the same card is already
   * guaranteed there — see scoring.ts's `computeCardChemWithCaptain`). `sub`
   * swaps are re-validated against the board as it stands at each step of
   * this loop, not the board at commit time: two `sub` cards can coexist
   * when player count > 5 duplicates a type (see `buildAbilityPool`), and an
   * earlier swap in this same pass may have already moved one of a later
   * swap's target cards. A swap that's no longer valid fizzles — recorded in
   * the log as failed rather than silently applied against stale slots.
   *
   * Idempotent via `abilityActivationRevealed`: a forced timeout racing a
   * manual reveal (or any other double-invocation) can never double-apply a
   * swap.
   */
  private _revealAbilityActivations(session: GameSession): void {
    if (session.abilityActivationRevealed) return;
    session.abilityActivationRevealed = true;
    // Nothing is pending anymore by definition (the caller only reaches
    // here once allResolved), so there's nothing left for the auto-discard
    // deadline to force — clear it so a broadcast during the post-reveal
    // hold window (see `_afterAbilityActivation`) can't re-arm a stale timer
    // that fires against an already-fully-resolved phase.
    session.abilityActivationDeadlineAt = null;

    for (const playerId of session.baseTurnOrder) {
      const ability = session.playerAbilities[playerId];
      if (!ability || ability.status !== 'used') continue;

      let summary = ability.pendingSummary ?? '';
      if (ability.type === 'sub') {
        const mySlot = session.pitches[playerId]?.slots.find(
          (s) => s.index === ability.sourceSlotIndex,
        );
        const myCard = mySlot?.card ?? null;
        let rivalCard: DraftCard | null = null;
        let writeRival: ((card: DraftCard) => void) | null = null;

        if (ability.targetBenchGroup && ability.targetUserId) {
          const group = ability.targetBenchGroup;
          const subSlot =
            session.subsPhase?.userSubs[ability.targetUserId]?.[group];
          rivalCard = subSlot
            ? (subSlot.benchedCard ?? subSlot.chosenCard ?? null)
            : null;
          if (subSlot) {
            writeRival = (card: DraftCard) => {
              subSlot.benchedCard = card;
              subSlot.benchedPlayerId = card.cardId;
              subSlot.benchedPlayerName = card.playerName;
              subSlot.benchedPlayerRating = card.rating;
              subSlot.benchedPlayerPosition = card.basePositionType;
              subSlot.swappedSlotIndex = undefined;
            };
          }
        } else if (
          ability.targetUserId != null &&
          ability.targetSlotIndex != null
        ) {
          const rivalSlot = session.pitches[ability.targetUserId]?.slots.find(
            (s) => s.index === ability.targetSlotIndex,
          );
          rivalCard = rivalSlot?.card ?? null;
          if (rivalSlot) {
            writeRival = (card: DraftCard) => {
              rivalSlot.card = card;
            };
          }
        }

        if (mySlot && myCard && rivalCard && writeRival) {
          session.subSwappedCardIds.add(myCard.cardId);
          session.subSwappedCardIds.add(rivalCard.cardId);
          mySlot.card = rivalCard;
          writeRival(myCard);
        } else {
          summary = `${summary} — fizzled (target no longer available)`;
        }
      } else if (ability.type === 'coach') {
        // Deferred (like sub) so opponents don't see the coached player gain a
        // position before everyone has locked in. Locate by card id across
        // pitches AND benches — an earlier sub may have moved the card, or
        // the coach target may have started on the bench.
        const cardId = ability.targetPlayerId;
        const pos = ability.coachedPosition;
        const card = this._findCardByIdAcrossBoard(session, cardId);
        // eslint-disable-next-line no-console
        console.log('[Coach] reveal apply', {
          byPlayerId: playerId,
          cardId,
          pos,
          found: card != null,
          foundBasePos: card?.basePositionType,
          alreadyCoached: cardId ? session.coachedPositions[cardId] != null : null,
        });
        if (
          card &&
          pos &&
          card.basePositionType !== 'GK' &&
          session.coachedPositions[card.cardId] == null &&
          !this.cardPositionSet(card).has(pos)
        ) {
          card.naturalPositions = [...(card.naturalPositions ?? []), pos];
          card.altPositions = [...(card.altPositions ?? []), pos];
          session.coachedPositions[card.cardId] = pos;
          // eslint-disable-next-line no-console
          console.log('[Coach] applied', {
            cardId: card.cardId,
            naturalPositions: card.naturalPositions,
          });
        } else {
          summary = `${summary} — fizzled (target no longer available)`;
        }
      }

      const activation: AbilityActivation = {
        byPlayerId: playerId,
        byName: this._displayName(session, playerId),
        type: ability.type,
        summary,
        targetUserId: ability.targetUserId,
        targetSlotIndex: ability.targetSlotIndex,
        targetBenchGroup: ability.targetBenchGroup,
      };
      session.abilityActivations.push(activation);
    }
  }

  /**
   * Public entry point for the reveal pass: called once the gateway observes
   * every player has committed (`allResolved` from `activateAbility`/
   * `discardAbility`). Requires nothing pending — the gateway is expected to
   * check `allResolved` itself, this is just belt-and-suspenders.
   */
  revealAbilityActivations(
    roomCode: string,
  ): { error: string } | { session: GameSession } {
    const session = this.getSessionByRoomCode(roomCode);
    if (!session) return { error: 'SESSION_NOT_FOUND' };
    if (session.status !== 'ability_activation') {
      return { error: 'NOT_ACTIVATION_PHASE' };
    }
    if (this._hasPendingAbilities(session)) {
      return { error: 'ABILITIES_STILL_PENDING' };
    }
    this._revealAbilityActivations(session);
    return { session };
  }

  /**
   * Advances from the (already revealed) ability-activation phase into
   * lineup_edit (Track B step 4). Split out from `revealAbilityActivations`
   * so the gateway can hold a brief "here's what everyone did" window
   * between the two, mirroring the ability draft's own
   * reveal-then-`beginPlayerDraft` pattern.
   */
  finishAbilityActivation(
    roomCode: string,
  ): { error: string } | { session: GameSession } {
    const session = this.getSessionByRoomCode(roomCode);
    if (!session) return { error: 'SESSION_NOT_FOUND' };
    if (session.status !== 'ability_activation') {
      return { error: 'NOT_ACTIVATION_PHASE' };
    }
    this._enterLineupEditPhase(session);
    return { session };
  }

  /**
   * Force-ends the ability-activation phase when its deadline expires: every
   * player who hasn't used or discarded their card yet has it auto-discarded
   * (the same no-op outcome as `discardAbility`), then whatever WAS committed
   * (possibly by just one player, seconds before the deadline, with no one
   * else around to trigger a normal reveal) is revealed before the game
   * advances to lineup_edit — otherwise an already-locked-in `sub` swap would
   * be silently lost. Mirrors `forceFinalizeLineupEdit` for the same reason —
   * a phase with no forced resolution path can otherwise hang forever on one
   * absent player.
   */
  forceFinalizeAbilityActivation(
    roomCode: string,
  ): { error: string } | { session: GameSession } {
    const session = this.getSessionByRoomCode(roomCode);
    if (!session) return { error: 'SESSION_NOT_FOUND' };
    if (session.status !== 'ability_activation') {
      return { error: 'NOT_ACTIVATION_PHASE' };
    }
    for (const ability of Object.values(session.playerAbilities)) {
      if (ability.status === 'pending') ability.status = 'discarded';
    }
    this._revealAbilityActivations(session);
    this._enterLineupEditPhase(session);
    return { session };
  }

  /**
   * Transitions the session into lineup_edit (Track B step 4) once ability
   * activation has resolved (or been skipped). Extends — does NOT recreate —
   * the `userSubs` records already populated by `_enterBenchSelectionPhase`,
   * preserving each player's already-chosen att/mid/def bench picks. This is
   * also where `hasExtraBench` is derived (moved here from the old
   * subs-phase entry point, since ability_activation now runs strictly
   * before this), which can grow `isComplete`'s requirement set — so
   * `isComplete` is recomputed here, not merely defaulted, and can flip back
   * to false for an Extra-Bench holder until they've also picked their bonus
   * `extra` sub.
   */
  private _enterLineupEditPhase(session: GameSession): GameSession {
    this._clearRoundHiddenState(session);
    session.lastRoundLeftovers = [];
    session.status = 'lineup_edit';
    // Leaving ability_activation (however it got resolved) — its deadline no
    // longer applies.
    session.abilityActivationDeadlineAt = null;
    const userSubs = session.subsPhase?.userSubs ?? {};
    for (const player of session.players) {
      // Players who activated the Extra Bench card get a 4th any-position sub,
      // available starting now (see _enterBenchSelectionPhase's doc comment —
      // this couldn't be known until ability_activation resolved).
      const ab = session.playerAbilities[player.id];
      const hasExtraBench = ab?.type === 'extra_bench' && ab.status === 'used';
      const existing = userSubs[player.id] ?? { isComplete: false, lineupConfirmed: false };
      const requiredGroups: SubPositionGroup[] = hasExtraBench
        ? ['att', 'mid', 'def', 'extra']
        : ['att', 'mid', 'def'];
      const picksComplete = requiredGroups.every(
        (g) => existing[g]?.chosenPlayerId != null,
      );
      // Bench-selection timeout may have force-marked `isComplete` with some
      // att/mid/def slots still empty (those groups cannot be filled later —
      // lineup_edit only allows the Extra Bench 'extra' pick). Preserve that
      // force-complete so confirmLineup stays reachable; still require the
      // newly unlocked 'extra' pick when Extra Bench just activated.
      const needsExtra =
        hasExtraBench && existing.extra?.chosenPlayerId == null;
      const isComplete =
        picksComplete || (existing.isComplete === true && !needsExtra);
      userSubs[player.id] = { ...existing, hasExtraBench, isComplete };
    }
    session.subsPhase = { userSubs };
    // Re-arm a FRESH lineup_edit deadline (independent of any prior
    // bench_selection window). Gateway re-arms because the deadline value
    // changes — see `_maybeArmSubsTimer`'s deadlineAt comparison.
    session.subsDeadlineAt =
      session.subsTimerSeconds !== null
        ? Date.now() + session.subsTimerSeconds * 1000
        : null;
    return session;
  }

  /**
   * Force-ends bench_selection when its deadline expires (Track B / B4):
   * every player's bench is accepted as-is — including empty/partial
   * att/mid/def slots — then the session advances into ability_activation
   * (or straight to lineup_edit when nothing is pending). Without this, a
   * single absent player can deadlock the room forever, because att/mid/def
   * spin/pick is only legal during bench_selection.
   */
  forceFinalizeBenchSelection(
    roomCode: string,
  ): { error: string } | { session: GameSession } {
    const session = this.getSessionByRoomCode(roomCode);
    if (!session) return { error: 'SESSION_NOT_FOUND' };
    if (session.status !== 'bench_selection') return { error: 'NOT_SUBS_PHASE' };
    if (session.subsPhase) {
      for (const subs of Object.values(session.subsPhase.userSubs)) {
        subs.isComplete = true;
      }
    }
    this._enterActivationPhase(session);
    return { session };
  }

  /**
   * Force-ends the lineup_edit phase when its timer expires: every player's
   * current lineup is accepted as-is (no position validation) and the game
   * is scored.
   */
  forceFinalizeLineupEdit(roomCode: string): { error: string } | { session: GameSession; tournamentStarting?: boolean } {
    const session = this.getSessionByRoomCode(roomCode);
    if (!session) return { error: 'SESSION_NOT_FOUND' };
    if (session.status !== 'lineup_edit') return { error: 'NOT_SUBS_PHASE' };
    if (session.subsPhase) {
      for (const subs of Object.values(session.subsPhase.userSubs)) {
        subs.lineupConfirmed = true;
      }
    }
    // Diagnostic: log who was left out of position at timeout. Those cards score
    // 0 in their line average and earn no card/line-leader chemistry.
    for (const p of session.players) {
      const slots = session.pitches[p.id]?.slots ?? [];
      const misplaced = slots
        .filter((s) => s.card && !cardFitsSlot(s))
        .map((s) => `${s.card!.playerName}(${s.card!.basePositionType}→${s.basePositionType})`);
      if (misplaced.length > 0) {
        this.logger.info(
          {
            event: 'subs_timeout_misplaced',
            roomCode,
            playerId: p.id,
            displayName: p.displayName,
            misplaced,
          },
          'Subs timeout: player misplaced, scored 0',
        );
      }
    }
    // Tournament fork (mirrors confirmLineup): on timeout the lineups are
    // force-confirmed above, then a tournament-enabled session starts the
    // bracket instead of finalizing. The gateway calls `beginBracketReveal`.
    if (session.tournamentEnabled) return { session, tournamentStarting: true };
    this._finalizeDraft(session);
    return { session };
  }

  /**
   * Returns subsPhase with full data for localPlayer.
   * Rivals: status-only by default; during ability_activation, also expose
   * bench card identity (no chemistry bonuses) so Red/Sub can target rival
   * bench players without leaking private chemistry data.
   */
  private _buildSubsPhaseSnapshot(
    subsPhase: SubsPhase,
    marks: { captainCardByPlayer: Record<string, string>; redCardIds: Set<string>; coachedCardIds: Set<string> },
    localPlayerId?: string,
    exposeRivalBenchIdentity = false,
  ): object {
    const filtered: Record<string, object> = {};
    for (const [pid, subs] of Object.entries(subsPhase.userSubs)) {
      if (pid === localPlayerId) {
        filtered[pid] = {
          isComplete: subs.isComplete,
          lineupConfirmed: subs.lineupConfirmed,
          hasExtraBench: subs.hasExtraBench ?? false,
          att: subs.att ? this._serializeSubSlot(subs.att, marks, pid) : null,
          mid: subs.mid ? this._serializeSubSlot(subs.mid, marks, pid) : null,
          def: subs.def ? this._serializeSubSlot(subs.def, marks, pid) : null,
          extra: subs.extra ? this._serializeSubSlot(subs.extra, marks, pid) : null,
        };
      } else if (exposeRivalBenchIdentity) {
        filtered[pid] = {
          isComplete: subs.isComplete,
          lineupConfirmed: subs.lineupConfirmed,
          hasExtraBench: subs.hasExtraBench ?? false,
          att: subs.att
            ? this._serializeSubSlotIdentity(subs.att, marks, pid)
            : null,
          mid: subs.mid
            ? this._serializeSubSlotIdentity(subs.mid, marks, pid)
            : null,
          def: subs.def
            ? this._serializeSubSlotIdentity(subs.def, marks, pid)
            : null,
          // extra does not exist yet during ability_activation.
          extra: null,
        };
      } else {
        filtered[pid] = {
          isComplete: subs.isComplete,
          lineupConfirmed: subs.lineupConfirmed,
          hasExtraBench: subs.hasExtraBench ?? false,
        };
      }
    }
    return { userSubs: filtered };
  }

  /**
   * Rival-facing bench identity for ability targeting: enough to pick a
   * target (id/name/rating/position) without chemistry bonuses.
   */
  private _serializeSubSlotIdentity(
    slot: SubSlot,
    marks: { captainCardByPlayer: Record<string, string>; redCardIds: Set<string>; coachedCardIds: Set<string> },
    ownerId: string,
  ): object {
    const current = slot.benchedCard ?? slot.chosenCard;
    return {
      positionGroup: slot.positionGroup,
      spinResultClub: slot.spinResultClub ?? null,
      chosenPlayerId: slot.chosenPlayerId ?? null,
      chosenPlayerName: slot.chosenPlayerName ?? null,
      chosenPlayerRating: slot.chosenPlayerRating ?? null,
      chosenPlayerPosition: slot.chosenPlayerPosition ?? null,
      swappedSlotIndex: slot.swappedSlotIndex ?? null,
      benchHoldsStarter: slot.benchedCard != null,
      benchedPlayerId: current?.cardId ?? null,
      benchedPlayerName: current?.playerName ?? null,
      benchedPlayerRating: current?.rating ?? null,
      benchedPlayerPosition: current?.basePositionType ?? null,
      benchedImageUrl: current?.imageUrl ?? null,
      benchedClub: current?.club ?? null,
      benchedClubLogoUrl: current?.clubLogoUrl ?? null,
      benchedNationality: current?.nationality ?? null,
      benchedPace: current?.pace ?? null,
      benchedShooting: current?.shooting ?? null,
      benchedPassing: current?.passing ?? null,
      benchedDribbling: current?.dribbling ?? null,
      benchedDefending: current?.defending ?? null,
      benchedPhysical: current?.physical ?? null,
      benchedAltPositions: current?.altPositions ?? [],
      benchedNaturalPositions: current?.naturalPositions ?? [],
      benchedCaptain:
        current != null && marks.captainCardByPlayer[ownerId] === current.cardId,
      benchedRedCarded: current != null && marks.redCardIds.has(current.cardId),
      benchedCoached: current != null && marks.coachedCardIds.has(current.cardId),
      // Intentionally omit chemistry bonuses for rivals.
      benchedChemistryBonuses: [],
    };
  }

  /**
   * Serializes a single bench slot for the client — including `captain`/
   * `redCarded` flags for whichever card is CURRENTLY on the bench, mirroring
   * `_serializePitches`' identical per-slot tagging for pitch cards (see that
   * method's doc comment: "keyed on the CARD currently in the slot, so
   * badges follow players when they move"). Bench cards used to be excluded
   * from this entirely — a captained or red-carded starter swapped onto the
   * bench during the subs phase would silently lose its badge, even though
   * `redDisabledIndices`/`computeCardChemWithCaptain` (scoring.ts) already
   * track effects purely by card id, independent of where the card ends up.
   */
  private _serializeSubSlot(
    slot: SubSlot,
    marks: { captainCardByPlayer: Record<string, string>; redCardIds: Set<string>; coachedCardIds: Set<string> },
    ownerId: string,
  ): object {
    // The card physically on the bench right now: the displaced starter once a
    // swap has happened, otherwise the originally-chosen sub. The client always
    // renders this as a full card.
    const current = slot.benchedCard ?? slot.chosenCard;
    return {
      positionGroup:       slot.positionGroup,
      spinResultClub:      slot.spinResultClub      ?? null,
      chosenPlayerId:      slot.chosenPlayerId      ?? null,
      chosenPlayerName:    slot.chosenPlayerName    ?? null,
      chosenPlayerRating:  slot.chosenPlayerRating  ?? null,
      chosenPlayerPosition:slot.chosenPlayerPosition ?? null,
      swappedSlotIndex:    slot.swappedSlotIndex    ?? null,
      // `benchHoldsStarter` is true when the bench currently holds a swapped-out
      // starter (not the originally-chosen sub).
      benchHoldsStarter:   slot.benchedCard != null,
      benchedPlayerId:       current?.cardId           ?? null,
      benchedPlayerName:     current?.playerName       ?? null,
      benchedPlayerRating:   current?.rating           ?? null,
      benchedPlayerPosition: current?.basePositionType ?? null,
      benchedImageUrl:       current?.imageUrl         ?? null,
      benchedClub:           current?.club             ?? null,
      benchedClubLogoUrl:    current?.clubLogoUrl      ?? null,
      benchedNationality:    current?.nationality      ?? null,
      benchedPace:           current?.pace             ?? null,
      benchedShooting:       current?.shooting         ?? null,
      benchedPassing:        current?.passing          ?? null,
      benchedDribbling:      current?.dribbling        ?? null,
      benchedDefending:      current?.defending        ?? null,
      benchedPhysical:       current?.physical         ?? null,
      benchedAltPositions:   current?.altPositions     ?? [],
      benchedNaturalPositions: current?.naturalPositions ?? [],
      benchedCaptain:
        current != null && marks.captainCardByPlayer[ownerId] === current.cardId,
      benchedRedCarded: current != null && marks.redCardIds.has(current.cardId),
      benchedCoached: current != null && marks.coachedCardIds.has(current.cardId),
      // The bench card's own tiered chemistry challenges, so the client can show
      // each challenge's achieved/remaining progress when the player taps it.
      benchedChemistryBonuses: current?.chemistryBonuses ?? [],
    };
  }

  /**
   * Every player id already used anywhere in the game: all starting-XI cards
   * (draftedCardIds, which spans every player's lineup) plus every chosen sub
   * across all users. A spun/picked sub must avoid these so no real player is
   * duplicated. Club duplication is intentionally allowed — same-club players
   * are rewarded by the chemistry system.
   */
  private _usedPlayerIds(session: GameSession): Set<string> {
    const used = new Set<string>(session.draftedCardIds);
    const allSubs = session.subsPhase?.userSubs ?? {};
    for (const userSubs of Object.values(allSubs)) {
      for (const g of ['att', 'mid', 'def', 'extra'] as SubPositionGroup[]) {
        const slot = userSubs[g];
        if (slot?.chosenCard) used.add(slot.chosenCard.cardId);
        else if (slot?.chosenPlayerId) used.add(slot.chosenPlayerId);
      }
    }
    return used;
  }

  requestSubSpin(
    roomCode: string,
    playerId: string,
    positionGroup: SubPositionGroup,
  ): { error: string } | { clubName: string; players: { id: string; name: string; rating: number; position: string }[] } {
    const session = this.getSessionByRoomCode(roomCode);
    if (!session) return { error: 'SESSION_NOT_FOUND' };
    // Track B: att/mid/def spin/pick belongs to bench_selection (step 2);
    // the Extra Bench bonus 'extra' spin/pick belongs to lineup_edit (step
    // 4), since hasExtraBench isn't known until ability_activation resolves
    // between the two. Reject a group in the wrong phase even before
    // checking hasExtraBench, so the error is unambiguous either way.
    if (positionGroup === 'extra') {
      if (session.status !== 'lineup_edit') return { error: 'NO_EXTRA_BENCH' };
    } else if (session.status !== 'bench_selection') {
      return { error: 'NOT_SUBS_PHASE' };
    }
    if (!session.subsPhase) return { error: 'NO_SUBS_PHASE' };

    const userSubs = session.subsPhase.userSubs[playerId];
    if (!userSubs) return { error: 'PLAYER_NOT_FOUND' };
    if (userSubs.isComplete) return { error: 'SUBS_ALREADY_COMPLETE' };
    if (positionGroup === 'extra' && !userSubs.hasExtraBench) {
      return { error: 'NO_EXTRA_BENCH' };
    }

    // Every player already used anywhere in the game (all starting XIs + all
    // already-chosen subs) so a freshly spun sub never duplicates a player.
    const usedIds = this._usedPlayerIds(session);

    const eligiblePositions = GameService.SUB_POSITIONS[positionGroup];
    const pool = loadPlayerPool();

    // Build the club list from the players actually in the pool (respects admin
    // edits: new clubs, renamed clubs and club→league reassignments all flow in
    // via the enriched `league` field). Empty selection = all leagues.
    const leagueSet = new Set(session.leagues);
    const leagueOf = (p: PlayerCardDefinition) =>
      (p as any).league ?? CLUB_LEAGUE[p.club] ?? '';
    const allClubs = [
      ...new Set(
        pool
          .filter((p) => leagueSet.size === 0 || leagueSet.has(leagueOf(p)))
          .map((p) => p.club)
          .filter((c): c is string => !!c),
      ),
    ];

    const clubHasEligible = (club: string): boolean =>
      pool.some(
        (p) =>
          p.club === club &&
          p.positions.some((pos) => eligiblePositions.has(pos)) &&
          !usedIds.has(p.id),
      );

    // Determine the club for this spin:
    //  • If this sub group was already spun, reuse its locked club — re-opening
    //    the spinner must NOT re-roll a new club (prevents free re-spins).
    //  • Otherwise pick a fresh club that isn't already locked by this player's
    //    other two sub groups, so all three subs come from distinct clubs.
    const existingSlot = userSubs[positionGroup];
    const lockedByOtherSubs = new Set(
      (['att', 'mid', 'def', 'extra'] as SubPositionGroup[])
        .filter((g) => g !== positionGroup)
        .map((g) => userSubs[g]?.spinResultClub)
        .filter((c): c is string => !!c),
    );

    let club: string | undefined = existingSlot?.spinResultClub;
    if (!club) {
      // Prefer clubs not used by the other subs; only fall back to an
      // already-used club if dedup would otherwise leave nothing playable.
      const preferred = this.shuffle(allClubs.filter((c) => !lockedByOtherSubs.has(c)));
      const fallback = this.shuffle(allClubs.filter((c) => lockedByOtherSubs.has(c)));
      club = [...preferred, ...fallback].find(clubHasEligible);
    }
    if (!club || !clubHasEligible(club)) return { error: 'NO_ELIGIBLE_CLUB' };

    {
      // Lock the club on the slot (preserving any already-chosen pick).
      userSubs[positionGroup] = { ...existingSlot, positionGroup, spinResultClub: club };

      // A player is eligible if ANY of their positions (primary or alternate)
      // falls in this group — not just their primary.
      const eligiblePlayers = pool.filter(
        (p) =>
          p.club === club &&
          p.positions.some((pos) => eligiblePositions.has(pos)) &&
          !usedIds.has(p.id),
      );

      const players = eligiblePlayers
        .sort((a, b) => b.rating - a.rating)
        .map((p) => {
          // Show the player at the position that qualified them for this group
          // (their primary if it fits, otherwise the matching alternate).
          const groupPos = (p.positions.find((pos) => eligiblePositions.has(pos))
            ?? p.positions[0]) as BasePositionType;
          const card = this.toCard(p, groupPos, session);
          return {
            id:               p.id,
            name:             p.name,
            rating:           p.rating,
            position:         groupPos,
            imageUrl:         card.imageUrl         ?? null,
            club:             card.club,
            clubLogoUrl:      card.clubLogoUrl       ?? null,
            nationality:      card.nationality       ?? null,
            altPositions:     card.altPositions,
            naturalPositions: card.naturalPositions,
            pace:             card.pace,
            shooting:         card.shooting,
            passing:          card.passing,
            dribbling:        card.dribbling,
            defending:        card.defending,
            physical:         card.physical,
            chemistryBonuses: card.chemistryBonuses,
          };
        });

      return { clubName: club, players };
    }
  }

  pickSub(
    roomCode: string,
    playerId: string,
    positionGroup: SubPositionGroup,
    chosenPlayerId: string,
  ): { error: string } | { session: GameSession } {
    const session = this.getSessionByRoomCode(roomCode);
    if (!session) return { error: 'SESSION_NOT_FOUND' };
    // Same phase/group split as requestSubSpin — see its comment.
    if (positionGroup === 'extra') {
      if (session.status !== 'lineup_edit') return { error: 'NO_EXTRA_BENCH' };
    } else if (session.status !== 'bench_selection') {
      return { error: 'NOT_SUBS_PHASE' };
    }
    if (!session.subsPhase) return { error: 'NO_SUBS_PHASE' };

    const userSubs = session.subsPhase.userSubs[playerId];
    if (!userSubs) return { error: 'PLAYER_NOT_FOUND' };
    if (userSubs.isComplete) return { error: 'SUBS_ALREADY_COMPLETE' };
    if (positionGroup === 'extra' && !userSubs.hasExtraBench) {
      return { error: 'NO_EXTRA_BENCH' };
    }

    const slot = userSubs[positionGroup];
    if (!slot?.spinResultClub) return { error: 'SPIN_NOT_DONE' };

    const pool = loadPlayerPool();
    const player = pool.find((p) => p.id === chosenPlayerId);
    if (!player) return { error: 'PLAYER_NOT_IN_POOL' };
    if (player.club !== slot.spinResultClub) return { error: 'PLAYER_NOT_FROM_SPUN_CLUB' };

    const eligiblePositions = GameService.SUB_POSITIONS[positionGroup];
    if (!player.positions.some((pos) => eligiblePositions.has(pos))) {
      return { error: 'WRONG_POSITION_GROUP' };
    }

    // Reject any player already used anywhere — in a starting XI (own or
    // opponents') or already chosen as a sub. The current group's previous pick
    // was wiped by the spin, so re-picking the same slot is unaffected.
    const usedIds = this._usedPlayerIds(session);
    if (usedIds.has(chosenPlayerId)) return { error: 'PLAYER_ALREADY_USED' };

    // Use the position that qualifies the player for this group (primary if it
    // fits, otherwise the matching alternate) so the bench card sits correctly.
    const groupPos = (player.positions.find((pos) => eligiblePositions.has(pos))
      ?? player.positions[0]) as BasePositionType;

    slot.chosenPlayerId = chosenPlayerId;
    slot.chosenPlayerName = player.name;
    slot.chosenPlayerRating = player.rating;
    slot.chosenPlayerPosition = groupPos;
    slot.chosenCard = this.toCard(player, groupPos, session);

    const requiredGroups: SubPositionGroup[] = userSubs.hasExtraBench
      ? ['att', 'mid', 'def', 'extra']
      : ['att', 'mid', 'def'];
    const allGroupsDone = requiredGroups.every(
      (g) => userSubs[g]?.chosenPlayerId != null,
    );
    if (allGroupsDone) {
      userSubs.isComplete = true;
      // Once every player's bench selection is complete, advance the whole
      // session straight into ability_activation (Track B step 3) — mirrors
      // confirmLineup's inline "last one triggers the next phase" pattern.
      // Only fires from bench_selection itself: a player completing their
      // Extra Bench 'extra' pick during lineup_edit also flips isComplete,
      // but that phase is already active and must not re-enter step 3.
      if (session.status === 'bench_selection' && this._allBenchSelectionsComplete(session)) {
        this._enterActivationPhase(session);
      }
    }

    return { session };
  }

  /**
   * Returns the full natural-position set for a card (primary + alternates),
   * falling back to base+alt for older cards that predate `naturalPositions`.
   */
  private cardPositionSet(card: DraftCard): Set<string> {
    const nat = card.naturalPositions && card.naturalPositions.length > 0
      ? card.naturalPositions
      : [card.basePositionType, ...(card.altPositions ?? [])];
    return new Set<string>(nat);
  }

  /** True if `card` can legally occupy a slot requiring `slotPos`. */
  private cardFitsSlot(card: DraftCard, slotPos: string): boolean {
    return this.cardPositionSet(card).has(slotPos);
  }

  /** Finds the card with `cardId` on ANY player's pitch or bench (or null).
   *  Used by coach reveal so its effect attaches wherever the card currently
   *  sits — including after an earlier same-pass sub moved it, or when the
   *  coach target started on the bench. */
  private _findCardByIdAcrossBoard(
    session: GameSession,
    cardId?: string,
  ): DraftCard | null {
    if (cardId == null) return null;
    for (const pitch of Object.values(session.pitches)) {
      const found = pitch.slots.find((s) => s.card?.cardId === cardId)?.card;
      if (found) return found;
    }
    const groups: SubPositionGroup[] = ['att', 'mid', 'def', 'extra'];
    for (const subs of Object.values(session.subsPhase?.userSubs ?? {})) {
      for (const g of groups) {
        const slot = subs[g];
        if (!slot) continue;
        const current = slot.benchedCard ?? slot.chosenCard;
        if (current?.cardId === cardId) return current;
      }
    }
    return null;
  }

  /** @deprecated Prefer `_findCardByIdAcrossBoard` — kept as a thin alias for
   *  any remaining call sites during the coach/bench targeting rollout. */
  private _findCardByIdAcrossPitches(
    session: GameSession,
    cardId?: string,
  ): DraftCard | null {
    return this._findCardByIdAcrossBoard(session, cardId);
  }

  /**
   * Unified "swap any card with any card" used in the subs phase. Each endpoint
   * is either a pitch slot (`{ kind: 'pitch', index }`) or a bench sub
   * (`{ kind: 'bench', group }`). The cards currently occupying the two
   * endpoints are exchanged with NO position restriction — the only validity
   * gate is `confirmLineup`, which requires every starter to fit its slot.
   *
   * A bench slot's "current card" is whatever physically sits on the bench:
   * `benchedCard` once it has been swapped at least once, otherwise the
   * originally-chosen sub (`chosenCard`). Writing a card onto a bench slot
   * stores it as `benchedCard` (and mirrors the snapshot fields).
   */
  swapRoster(
    roomCode: string,
    playerId: string,
    a: RosterEndpoint,
    b: RosterEndpoint,
  ): { error: string } | { session: GameSession } {
    const session = this.getSessionByRoomCode(roomCode);
    if (!session) return { error: 'SESSION_NOT_FOUND' };
    // Free swapping is a lineup_edit-only mechanic (Track B step 4) — bench
    // selection (step 2) only spins/picks, no free-swap UI/logic there.
    if (session.status !== 'lineup_edit') return { error: 'NOT_SUBS_PHASE' };
    if (!session.subsPhase) return { error: 'NO_SUBS_PHASE' };

    const userSubs = session.subsPhase.userSubs[playerId];
    if (!userSubs) return { error: 'PLAYER_NOT_FOUND' };
    if (userSubs.lineupConfirmed) return { error: 'LINEUP_ALREADY_CONFIRMED' };

    const pitch = session.pitches[playerId];
    if (!pitch) return { error: 'PITCH_NOT_FOUND' };

    // Reject a no-op (same endpoint twice).
    if (
      a.kind === b.kind &&
      ((a.kind === 'pitch' && b.kind === 'pitch' && a.index === b.index) ||
        (a.kind === 'bench' && b.kind === 'bench' && a.group === b.group))
    ) {
      return { error: 'SAME_ENDPOINT' };
    }

    const readCard = (e: RosterEndpoint): DraftCard | null => {
      if (e.kind === 'pitch') {
        return pitch.slots.find((s) => s.index === e.index)?.card ?? null;
      }
      const slot = userSubs[e.group];
      if (!slot) return null;
      return slot.benchedCard ?? slot.chosenCard ?? null;
    };

    const writeCard = (e: RosterEndpoint, card: DraftCard): void => {
      if (e.kind === 'pitch') {
        const s = pitch.slots.find((s) => s.index === e.index);
        if (s) s.card = card;
        return;
      }
      const slot = userSubs[e.group];
      if (!slot) return;
      slot.benchedCard = card;
      slot.benchedPlayerId = card.cardId;
      slot.benchedPlayerName = card.playerName;
      slot.benchedPlayerRating = card.rating;
      slot.benchedPlayerPosition = card.basePositionType;
      // swappedSlotIndex is no longer meaningful under free swapping; the bench
      // simply shows whatever card it currently holds.
      slot.swappedSlotIndex = undefined;
    };

    const cardA = readCard(a);
    const cardB = readCard(b);
    if (!cardA || !cardB) return { error: 'CARD_NOT_FOUND' };

    writeCard(a, cardB);
    writeCard(b, cardA);

    // eslint-disable-next-line no-console
    console.log('[Swap] swapRoster', {
      playerId,
      a,
      b,
      movedA: { cardId: cardA.cardId, naturalPositions: cardA.naturalPositions },
      movedB: { cardId: cardB.cardId, naturalPositions: cardB.naturalPositions },
      coachedPositions: session.coachedPositions,
    });

    return { session };
  }

  swapSub(
    roomCode: string,
    playerId: string,
    positionGroup: SubPositionGroup,
    starterId: string,
  ): { error: string } | { session: GameSession } {
    const session = this.getSessionByRoomCode(roomCode);
    if (!session) return { error: 'SESSION_NOT_FOUND' };
    // Same lineup_edit-only gating as swapRoster above.
    if (session.status !== 'lineup_edit') return { error: 'NOT_SUBS_PHASE' };
    if (!session.subsPhase) return { error: 'NO_SUBS_PHASE' };

    const userSubs = session.subsPhase.userSubs[playerId];
    if (!userSubs) return { error: 'PLAYER_NOT_FOUND' };
    if (userSubs.lineupConfirmed) return { error: 'LINEUP_ALREADY_CONFIRMED' };

    const subSlot = userSubs[positionGroup];
    if (!subSlot?.chosenCard) return { error: 'SUB_NOT_PICKED' };

    const pitch = session.pitches[playerId];

    // Case: tapping the currently benched player → undo swap
    if (
      subSlot.benchedCard &&
      subSlot.swappedSlotIndex !== undefined &&
      subSlot.benchedCard.cardId === starterId
    ) {
      const prevPitchSlot = pitch.slots.find((s) => s.index === subSlot.swappedSlotIndex!);
      if (prevPitchSlot) prevPitchSlot.card = subSlot.benchedCard;
      subSlot.benchedCard = undefined;
      subSlot.swappedSlotIndex = undefined;
      subSlot.benchedPlayerId = undefined;
      subSlot.benchedPlayerName = undefined;
      subSlot.benchedPlayerRating = undefined;
      subSlot.benchedPlayerPosition = undefined;
      return { session };
    }

    // Undo any existing swap first (re-swap with different starter)
    if (subSlot.swappedSlotIndex !== undefined && subSlot.benchedCard) {
      const prevPitchSlot = pitch.slots.find((s) => s.index === subSlot.swappedSlotIndex!);
      if (prevPitchSlot) prevPitchSlot.card = subSlot.benchedCard;
      subSlot.benchedCard = undefined;
      subSlot.swappedSlotIndex = undefined;
      subSlot.benchedPlayerId = undefined;
      subSlot.benchedPlayerName = undefined;
      subSlot.benchedPlayerRating = undefined;
      subSlot.benchedPlayerPosition = undefined;
    }

    // Find the target starter's pitch slot
    const targetSlot = pitch.slots.find((s) => s.card?.cardId === starterId);
    if (!targetSlot) return { error: 'STARTER_NOT_FOUND' };

    // Perform swap (no position restriction here — confirmLineup validates instead)
    subSlot.benchedCard = targetSlot.card!;
    subSlot.benchedPlayerId = targetSlot.card!.cardId;
    subSlot.benchedPlayerName = targetSlot.card!.playerName;
    subSlot.benchedPlayerRating = targetSlot.card!.rating;
    subSlot.benchedPlayerPosition = targetSlot.card!.basePositionType;
    targetSlot.card = subSlot.chosenCard!;
    subSlot.swappedSlotIndex = targetSlot.index;

    return { session };
  }

  confirmLineup(
    roomCode: string,
    playerId: string,
  ): { error: string } | { session: GameSession; tournamentStarting?: boolean } {
    const session = this.getSessionByRoomCode(roomCode);
    if (!session) return { error: 'SESSION_NOT_FOUND' };
    // Final submission (Track B step 5) only happens once lineup_edit (step
    // 4) is active — i.e. after ability_activation has resolved.
    if (session.status !== 'lineup_edit') return { error: 'NOT_SUBS_PHASE' };
    if (!session.subsPhase) return { error: 'NO_SUBS_PHASE' };

    const userSubs = session.subsPhase.userSubs[playerId];
    if (!userSubs) return { error: 'PLAYER_NOT_FOUND' };
    if (!userSubs.isComplete) return { error: 'SUBS_NOT_COMPLETE' };
    if (userSubs.lineupConfirmed) return { error: 'ALREADY_CONFIRMED' };

    // Every starter must be in a slot matching their primary OR alternate
    // position. Free rearranging can produce out-of-position players; those
    // must be fixed before the lineup can be confirmed.
    const pitch = session.pitches[playerId];
    if (pitch) {
      const misplaced = pitch.slots.some(
        (s) => s.card !== null && !this.cardFitsSlot(s.card, s.basePositionType),
      );
      if (misplaced) return { error: 'PLAYERS_OUT_OF_POSITION' };
    }

    userSubs.lineupConfirmed = true;

    const allConfirmed = Object.values(session.subsPhase.userSubs).every((s) => s.lineupConfirmed);
    if (allConfirmed) {
      // Tournament fork: in a tournament-enabled session lineup_edit flows
      // into the knockout tournament instead of finalizing the game. The
      // gateway sees `tournamentStarting` and calls `beginBracketReveal`; the
      // session stays in 'lineup_edit' until `beginTournament` flips it to
      // 'tournament'.
      if (session.tournamentEnabled) return { session, tournamentStarting: true };
      this._finalizeDraft(session);
    }

    return { session };
  }

  /**
   * Scores and marks the session as finished. Returns the same session for
   * chaining convenience.
   *
   * Scoring formula:
   *   linesTotal = defAvg + midAvg + atkAvg
   *   finalScore = linesTotal + userChemTotal + cardChemTotal
   */
  /**
   * Public, side-effect-free chemistry score for a single player — the same
   * `finalScore` used at game end, callable at any point after the subs phase
   * (tournament mode needs each lineup's chemistry at bracket creation, before
   * the game would otherwise finalize). Shares the exact `computeAllScores`
   * engine that `_finalizeDraft` uses, so there is no duplicated scoring logic;
   * `_finalizeDraft` keeps using the batch form (one pass for all players)
   * rather than calling this per-player, which would be O(n²) for the same
   * result.
   */
  public computeChemistryScore(session: GameSession, playerId: string): number {
    const breakdown = computeAllScores(session)[playerId] ?? emptyBreakdown();
    return breakdown.finalScore;
  }

  private _finalizeDraft(session: GameSession): GameSession {
    const allScores = computeAllScores(session);
    // For a tournament-mode session, `pointsAwarded` (champion/runner-up/top
    // scorer/most assists/highest rating bonuses — see
    // `_computeTournamentAwards`) must actually decide the winner, not just
    // be attached as display metadata. Non-tournament sessions get an empty
    // map here, so `tournamentBonus` is 0 for everyone and behavior is
    // unchanged from before this existed.
    const tournamentPoints = session.tournament?.awards?.pointsAwarded ?? {};

    const scored = session.players.map((p) => ({
      player: p,
      breakdown: allScores[p.id] ?? emptyBreakdown(),
      tournamentBonus: tournamentPoints[p.id] ?? 0,
    }));

    // The ranking score is draft/chemistry score + tournament bonus points.
    const totalOf = (s: (typeof scored)[number]) => s.breakdown.finalScore + s.tournamentBonus;
    scored.sort((a, b) => totalOf(b) - totalOf(a));

    // Assign ranks with proper tie handling: an equal total SHARES a rank
    // (see the tie-break note in _computeTournamentAwards) rather than being
    // arbitrarily split further. Deliberately a plain loop, not `.map()`:
    // the previous version tracked "the previous entry's rank" via
    // `session.result?.players[i - 1]?.rank`, which reads the OLD result
    // from BEFORE this call (always null on a genuine first finalization,
    // since `.map()`'s own callback has no way to see entries it has
    // already produced earlier in the SAME pass) — falling back to the
    // loop index `i` instead. That fallback only accidentally produced the
    // right answer for a 2-WAY tie (index 1 happens to equal rank 1); a
    // 3-or-more-way tie kept incrementing off the loop index instead of
    // staying pinned to the tie chain's rank, e.g. three equal totals
    // wrongly ranked 1, 1, 2 instead of 1, 1, 1. A plain loop carrying
    // `prevRank` forward explicitly (not derived from `i` or stale state)
    // is correct for a tie chain of any length.
    const players: PlayerResult[] = [];
    let prevTotal: number | null = null;
    let prevRank = 0;
    for (let i = 0; i < scored.length; i++) {
      const s = scored[i];
      const total = totalOf(s);
      const rank = prevTotal !== null && total === prevTotal ? prevRank : i + 1;
      players.push({
        playerId: s.player.id,
        displayName: s.player.displayName,
        rank,
        score: Math.round(total),
        scoreBreakdown: s.breakdown,
      });
      prevTotal = total;
      prevRank = rank;
    }

    session.status = 'finished';
    session.isFinished = true;
    this._clearRoundHiddenState(session);
    session.result = { reason: 'completed', players };
    session.turn = {
      turnId: '',
      phase: 'selecting_position',
      activePlayerId: '',
      activeSlotIndex: null,
      candidates: [],
      turnStartedAt: null,
    };
    return session;
  }

  // ── Tournament mode ─────────────────────────────────────────────────────────

  /**
   * Starts the knockout tournament for a tournament-enabled session whose subs
   * phase has just completed. Freezes every real player's confirmed lineup,
   * sizes the bracket (round up to 4/8/16), fills empty slots with AI club
   * placeholders, seeds round 1 (slot 1 vs 2, 3 vs 4, …), and enters the
   * `bracket_reveal` phase. The session flips to `status: 'tournament'`.
   */
  public beginTournament(roomCode: string): TournamentState {
    const session = this.getSessionByRoomCode(roomCode);
    if (!session) throw new Error('SESSION_NOT_FOUND');
    if (!session.tournamentEnabled) throw new Error('TOURNAMENT_NOT_ENABLED');

    const realParticipants: TournamentParticipant[] = session.players.map((p) => ({
      kind: 'real',
      participantId: p.id,
      displayName: p.displayName,
      lineup: this._buildParticipantLineup(session, p.id),
    }));

    const realCount = realParticipants.length;
    const size: 4 | 8 | 16 = realCount <= 4 ? 4 : realCount <= 8 ? 8 : 16;
    const aiCount = Math.max(0, size - realCount);

    // Real clubs already on a human's confirmed lineup are avoided by AI club
    // selection where possible, so every participant in the tournament reads
    // as a distinct club — this set grows as each AI club is picked below too.
    const usedClubIds = new Set<string>();
    for (const rp of realParticipants) {
      for (const card of rp.lineup?.pitchCards ?? []) usedClubIds.add(card.club);
    }

    const aiPool = loadPlayerPool();
    const aiParticipants: TournamentParticipant[] = [];
    for (let i = 0; i < aiCount; i++) {
      const selection = AiTeamFactory.selectAiClub(aiPool, session.leagues, usedClubIds, session.formation);
      if (!selection) {
        // No players at all for the room's leagues — keep the old generic
        // placeholder rather than fail tournament creation.
        aiParticipants.push({
          kind: 'ai',
          participantId: `ai_${uuidv4()}`,
          displayName: 'AI Club',
          lineup: null,
        });
        continue;
      }
      usedClubIds.add(selection.club);
      aiParticipants.push({
        kind: 'ai',
        participantId: `ai_${uuidv4()}`,
        displayName: selection.club,
        clubLogoUrl: selection.clubLogoUrl,
        lineup: AiTeamFactory.generateAiSquad(selection, session.formation),
      });
    }

    // The draw: bracket slots are randomly shuffled (real players and AI clubs
    // alike), not seeded by join order — every matchup, including whether a
    // player faces another real player or an AI club in round 1, is a genuine
    // lucky draw. Decided once here and then fixed for the rest of the
    // tournament (stored on session.tournament.bracket).
    const seeded = this.shuffle([...realParticipants, ...aiParticipants]);
    const bracket = this._buildBracket(seeded, size);

    const tournament: TournamentState = {
      phase: 'bracket_reveal',
      bracket,
      currentRound: 1,
      totalRounds: Math.log2(size),
      readyPlayerIds: [],
      readyDeadlineAt: null,
      bracketRevealAt: Date.now() + 8_000,
      awards: null,
    };
    session.tournament = tournament;
    session.status = 'tournament';
    // Snapshot the currently-published tournament awards config once, here,
    // so nothing later in this tournament ever re-reads
    // tournament-awards-config.json — same snapshot-safety principle as
    // scoringConfig at session creation, see the GameSession.
    // tournamentAwardsConfig doc comment for why this matters.
    const awardsConfig = loadPublishedTournamentAwardsConfig();
    session.tournamentAwardsConfig = awardsConfig.values;
    session.tournamentAwardsConfigVersion = awardsConfig.version;
    return tournament;
  }

  /**
   * Records a real player pressing Ready for their current-round match.
   * Idempotent (a duplicate ready is a no-op, not an error). Returns the
   * tournament state plus whether every real participant in the current round
   * is now ready.
   */
  public recordTournamentReady(
    roomCode: string,
    playerId: string,
  ): { error: string } | { state: TournamentState; allReady: boolean } {
    const session = this.getSessionByRoomCode(roomCode);
    if (!session) return { error: 'SESSION_NOT_FOUND' };
    if (session.status !== 'tournament' || !session.tournament) {
      return { error: 'TOURNAMENT_NOT_IN_READY_CHECK' };
    }
    const t = session.tournament;
    if (t.phase !== 'ready_check') return { error: 'TOURNAMENT_NOT_IN_READY_CHECK' };

    const realIds = this._currentRoundRealParticipantIds(t);
    if (!realIds.includes(playerId)) return { error: 'TOURNAMENT_NOT_YOUR_ROUND' };

    if (!t.readyPlayerIds.includes(playerId)) t.readyPlayerIds.push(playerId);
    const allReady = realIds.every((id) => t.readyPlayerIds.includes(id));
    return { state: t, allReady };
  }

  /**
   * Auto-readies every real participant in the current round who hasn't readied
   * yet (the 60-second ready-check timeout path). Clears the ready deadline.
   */
  public autoReadyRemainingPlayers(roomCode: string): TournamentState {
    const session = this.getSessionByRoomCode(roomCode);
    if (!session || !session.tournament) throw new Error('SESSION_NOT_FOUND');
    const t = session.tournament;
    for (const id of this._currentRoundRealParticipantIds(t)) {
      if (!t.readyPlayerIds.includes(id)) t.readyPlayerIds.push(id);
    }
    t.readyDeadlineAt = null;
    return t;
  }

  /**
   * Performs a tournament phase transition. The gateway owns the timers and
   * the live event delivery; this method owns the state mutations for each
   * target phase.
   */
  public advanceTournamentPhase(
    roomCode: string,
    toPhase: 'ready_check' | 'simulating' | 'round_result' | 'complete',
  ): TournamentState {
    const session = this.getSessionByRoomCode(roomCode);
    if (!session || !session.tournament) throw new Error('SESSION_NOT_FOUND');
    const t = session.tournament;
    const round = t.bracket.rounds[t.currentRound - 1];

    switch (toPhase) {
      case 'ready_check': {
        t.readyPlayerIds = [];
        // AI participants in this round are immediately considered ready.
        for (const id of this._currentRoundAiParticipantIds(t)) t.readyPlayerIds.push(id);
        t.readyDeadlineAt = Date.now() + 60_000;
        for (const m of round.matches) m.status = 'ready_check';
        t.phase = 'ready_check';
        break;
      }
      case 'simulating': {
        for (const m of round.matches) {
          const seed = this._seedHash(session.sessionId + m.matchId);
          const sim = this.runMatchSimulation(m.participantA, m.participantB, seed);
          const { events, ...rest } = sim;
          m.simulationEvents = events;
          m.nextEventIndex = 0;
          // The full result is computed up-front (deterministic). It stays
          // server-side until the gateway finishes streaming this match's
          // events and flips status to 'complete'; buildTournamentStatePayload
          // gates `result`/`winnerId` on `status === 'complete'` so clients
          // never see the score before the live feed reaches it.
          m.result = { ...rest, matchId: m.matchId };
          m.winnerId = sim.winnerId;
          m.status = 'simulating';
        }
        t.phase = 'simulating';
        break;
      }
      case 'round_result': {
        // Seed the next round from this round's winners: winner of match i goes
        // into next-round match floor(i/2), slot A if i even, slot B if i odd.
        const nextRound = t.bracket.rounds[t.currentRound]; // 0-based: next round
        if (nextRound) {
          round.matches.forEach((m, i) => {
            const winner = this._participantById(m, m.winnerId);
            const target = nextRound.matches[Math.floor(i / 2)];
            if (i % 2 === 0) target.participantA = winner;
            else target.participantB = winner;
          });
          nextRound.status = 'in_progress';
        }
        round.status = 'complete';
        t.phase = 'round_result';
        break;
      }
      case 'complete': {
        const finalRound = t.bracket.rounds[t.bracket.rounds.length - 1];
        const finalMatch = finalRound.matches[0];
        finalRound.status = 'complete';
        const champion = this._participantById(finalMatch, finalMatch.winnerId);
        const runnerUp =
          finalMatch.participantA.participantId === finalMatch.winnerId
            ? finalMatch.participantB
            : finalMatch.participantA;
        // Defensive fallback only — session.tournamentAwardsConfig is always
        // set by beginTournament() for any tournament reaching 'complete',
        // but a v1-equal default here means a hand-built/older session
        // fixture can never crash this call.
        t.awards = this._computeTournamentAwards(
          t,
          champion,
          runnerUp,
          session.tournamentAwardsConfig ?? DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1,
        );
        t.phase = 'complete';
        // Build the regular game result (player chemistry rankings) — the
        // tournament path forked away from _finalizeDraft at subs completion,
        // so session.result is still null here. _finalizeDraft sets
        // status='finished' + isFinished, which the existing game_state path
        // uses to drive the client's navigation to the result screen.
        this._finalizeDraft(session);
        if (session.result) session.result.tournament = t.awards;
        break;
      }
    }
    return t;
  }

  /**
   * Match simulation engine. Fully deterministic given the integer `seed` (a
   * seeded PRNG — no Math.random), so the same match always replays identically.
   *
   * Model:
   *  - Each team's expected goals scale with its relative lineup strength
   *    (equal strength → ~1.35 xG each; a stronger lineup pulls more xG). Goals
   *    are drawn from a Poisson distribution and capped for realism.
   *  - No draws: a level game is settled by a strength-weighted "shootout" that
   *    adds one decisive goal (equal strength → ~50/50).
   *  - Scorers are picked weighted toward attacking positions; goals, missed
   *    big chances and the occasional card become the (minute-sorted) event feed.
   *  - Per-player match ratings centre on ~6.4, lifted for the winning side and
   *    for goalscorers, clamped to [4.0, 10.0].
   * Returns the full result plus its event list (the `SimulationOutput`
   * contract — events are delivered alongside the result, stored on the match).
   */
  private runMatchSimulation(
    participantA: TournamentParticipant,
    participantB: TournamentParticipant,
    seed: number,
  ): MatchSimulationResult & { events: MatchEvent[] } {
    const rand = this._mulberry32(seed);

    const ratingA = participantA.lineup?.overallRating ?? 50;
    const ratingB = participantB.lineup?.overallRating ?? 50;
    const avg = (ratingA + ratingB) / 2 || 1;

    // Expected goals scale with relative strength. K controls how strongly a
    // rating edge tilts the match; BASE keeps equal games ~1.35 xG per side.
    const BASE_XG = 1.35;
    const K = 3.0;
    const xgA = BASE_XG * Math.pow(ratingA / avg, K);
    const xgB = BASE_XG * Math.pow(ratingB / avg, K);

    let openA = Math.min(this._poisson(rand, xgA), 4);
    let openB = Math.min(this._poisson(rand, xgB), 4);

    // Keep the combined scoreline realistic (≤ 8) by trimming the trailing team.
    while (openA + openB > 8) {
      if (openA < openB) openA -= 1;
      else openB -= 1;
    }

    const scoreA = openA;
    const scoreB = openB;

    // A drawn knockout match goes to a real penalty shootout, decided AFTER
    // regulation-time events are generated below (so a player sent off during
    // the 90 minutes is correctly excluded from taking a penalty too).
    // Regulation score (scoreA/scoreB) is never inflated by the shootout — it's
    // tracked separately so the final result reads like real football: "1–1
    // (4–3 pens)", not a fabricated "2–1".
    let penaltyScoreA: number | null = null;
    let penaltyScoreB: number | null = null;
    let winnerId: string;
    const events: MatchEvent[] = [];
    const goalsByName: Record<string, number> = {};

    // Decide WHAT happens and WHEN (minute + type + team) before deciding WHO
    // — this lets every player pick happen in strict chronological order, so
    // a red-carded player can never be selected for a LATER event (no more
    // "sent off at 20', scores at 85'"). Each team tracks its own sent-off
    // set, checked/updated as we walk the slots minute-by-minute.
    type PendingSlot = {
      minute: number;
      type: 'goal' | 'big_chance_missed' | 'yellow_card' | 'red_card';
      team: TournamentParticipant;
    };
    const pending: PendingSlot[] = [];
    const randMinute = () => 1 + Math.floor(rand() * 90);

    for (let g = 0; g < openA; g++) pending.push({ minute: randMinute(), type: 'goal', team: participantA });
    for (let g = 0; g < openB; g++) pending.push({ minute: randMinute(), type: 'goal', team: participantB });

    const missA = 1 + Math.floor(rand() * 3);
    const missB = 1 + Math.floor(rand() * 3);
    for (let m = 0; m < missA; m++) pending.push({ minute: randMinute(), type: 'big_chance_missed', team: participantA });
    for (let m = 0; m < missB; m++) pending.push({ minute: randMinute(), type: 'big_chance_missed', team: participantB });

    if (rand() < 0.5) pending.push({ minute: randMinute(), type: 'yellow_card', team: participantA });
    if (rand() < 0.5) pending.push({ minute: randMinute(), type: 'yellow_card', team: participantB });
    if (rand() < 0.05) pending.push({ minute: randMinute(), type: 'red_card', team: participantA });
    if (rand() < 0.05) pending.push({ minute: randMinute(), type: 'red_card', team: participantB });

    pending.sort((x, y) => x.minute - y.minute);

    const sentOff: { A: Set<string>; B: Set<string> } = { A: new Set(), B: new Set() };
    const sentOffFor = (p: TournamentParticipant) => (p === participantA ? sentOff.A : sentOff.B);

    for (const slot of pending) {
      const excluded = sentOffFor(slot.team);
      if (slot.type === 'goal') {
        const scorer = this._pickPlayerCard(rand, slot.team, excluded);
        const ev: MatchEvent = {
          minute: slot.minute,
          type: 'goal',
          teamParticipantId: slot.team.participantId,
          playerName: scorer.name,
          playerRating: scorer.rating,
        };
        if (rand() < 0.6) {
          // The assister must also be an eligible teammate, on the pitch at
          // this minute and not the scorer themself.
          const assistExcluded = new Set(excluded);
          assistExcluded.add(scorer.name);
          const assister = this._pickPlayerCard(rand, slot.team, assistExcluded);
          if (assister.name !== scorer.name) ev.assistPlayerName = assister.name;
        }
        events.push(ev);
        goalsByName[scorer.name] = (goalsByName[scorer.name] ?? 0) + 1;
      } else if (slot.type === 'big_chance_missed') {
        const pl = this._pickPlayerCard(rand, slot.team, excluded);
        events.push({
          minute: slot.minute,
          type: 'big_chance_missed',
          teamParticipantId: slot.team.participantId,
          playerName: pl.name,
          playerRating: pl.rating,
        });
      } else if (slot.type === 'yellow_card') {
        const pl = this._pickPlayerCard(rand, slot.team, excluded);
        events.push({
          minute: slot.minute,
          type: 'yellow_card',
          teamParticipantId: slot.team.participantId,
          playerName: pl.name,
          playerRating: pl.rating,
        });
      } else {
        // red_card — pick, record the event, then remove them from the
        // eligible pool for every subsequent slot (goals/assists/misses/
        // cards/penalties) for the rest of this match.
        const pl = this._pickPlayerCard(rand, slot.team, excluded);
        events.push({
          minute: slot.minute,
          type: 'red_card',
          teamParticipantId: slot.team.participantId,
          playerName: pl.name,
          playerRating: pl.rating,
        });
        excluded.add(pl.name);
      }
    }

    if (scoreA === scoreB) {
      // Players sent off during regulation cannot take a shootout penalty.
      const shootout = this._runPenaltyShootout(
        rand,
        participantA,
        participantB,
        sentOff.A,
        sentOff.B,
      );
      penaltyScoreA = shootout.penaltyScoreA;
      penaltyScoreB = shootout.penaltyScoreB;
      winnerId =
        shootout.winner === 'A' ? participantA.participantId : participantB.participantId;
      events.push(...shootout.events);
    } else {
      winnerId =
        scoreA > scoreB ? participantA.participantId : participantB.participantId;
    }

    // Guarantee a minimum-length feed even for a quiet game.
    while (events.length < 3) {
      const pl = this._pickPlayerCard(rand, participantA, sentOff.A);
      events.push({
        minute: 1 + Math.floor(rand() * 90),
        type: 'big_chance_missed',
        teamParticipantId: participantA.participantId,
        playerName: pl.name,
        playerRating: pl.rating,
      });
    }

    events.sort((x, y) => x.minute - y.minute);

    // ── Per-player match ratings ──────────────────────────────────────────
    const playerRatings: Record<string, number> = {};
    const margin = Math.abs(scoreA - scoreB);
    const assignRatings = (p: TournamentParticipant, isWinner: boolean) => {
      const cards = p.lineup?.pitchCards;
      if (!cards || cards.length === 0) {
        playerRatings[p.displayName] = isWinner ? 7.0 : 6.0;
        return;
      }
      for (const c of cards) {
        let r = 6.4 + (isWinner ? 0.25 : -0.25) * margin + (rand() - 0.5) * 0.8;
        r += (goalsByName[c.playerName] ?? 0) * 0.7;
        r = Math.max(4.0, Math.min(10.0, r));
        playerRatings[c.playerName] = Math.round(r * 10) / 10;
      }
    };
    // Use winnerId (not scoreA > scoreB) so a shootout winner still gets the
    // winner's rating boost even though regulation ended level.
    const aWon = winnerId === participantA.participantId;
    assignRatings(participantA, aWon);
    assignRatings(participantB, !aWon);

    // ── Stats ─────────────────────────────────────────────────────────────
    const possessionA = Math.max(
      35,
      Math.min(65, Math.round(50 + (ratingA - ratingB) * 1.2)),
    );
    const shotsOnTargetA = scoreA + this._poisson(rand, 2);
    const shotsOnTargetB = scoreB + this._poisson(rand, 2);
    const stats = {
      possessionA,
      shotsA: shotsOnTargetA + this._poisson(rand, 4),
      shotsOnTargetA,
      bigChancesA: scoreA + missA,
      shotsB: shotsOnTargetB + this._poisson(rand, 4),
      shotsOnTargetB,
      bigChancesB: scoreB + missB,
    };

    const winnerName =
      winnerId === participantA.participantId
        ? participantA.displayName
        : participantB.displayName;
    const hi = Math.max(scoreA, scoreB);
    const lo = Math.min(scoreA, scoreB);
    const explanation =
      penaltyScoreA !== null && penaltyScoreB !== null
        ? `${winnerName} won ${scoreA}-${scoreB} on penalties (${penaltyScoreA}-${penaltyScoreB}) after a draw.`
        : `${winnerName} won ${hi}-${lo}.`;
    return {
      matchId: '', // set by caller from the match it belongs to
      scoreA,
      scoreB,
      winnerId,
      penaltyScoreA,
      penaltyScoreB,
      stats,
      playerRatings,
      explanation,
      events,
    };
  }

  /**
   * A real penalty shootout for a drawn knockout match — standard best-of-5,
   * alternating kicks starting with team A, stopping the instant the outcome
   * is mathematically decided (a team can't be caught even if they scored
   * every remaining kick and the leader missed every one), then sudden death
   * (one kick each, repeat) if still level after 5 rounds each. Shootout
   * kicks are their own event types (`penalty_scored`/`penalty_missed`), never
   * `'goal'` — they don't count toward goals/assists/top-scorer stats or
   * inflate the regulation scoreline, matching real football convention.
   */
  private _runPenaltyShootout(
    rand: () => number,
    participantA: TournamentParticipant,
    participantB: TournamentParticipant,
    excludedA?: Set<string>,
    excludedB?: Set<string>,
  ): { penaltyScoreA: number; penaltyScoreB: number; winner: 'A' | 'B'; events: MatchEvent[] } {
    const events: MatchEvent[] = [];
    let penaltyScoreA = 0;
    let penaltyScoreB = 0;
    let remainingA = 5;
    let remainingB = 5;
    let kickNumber = 0;

    const takeKick = (p: TournamentParticipant, team: 'A' | 'B'): void => {
      kickNumber++;
      // A player sent off during regulation cannot step up to take a penalty.
      const kicker = this._pickPlayerCard(rand, p, team === 'A' ? excludedA : excludedB);
      // Conversion rate mirrors real-world penalty statistics (~72–87%),
      // nudged slightly by the taker's rating.
      const successProb = 0.72 + Math.min(0.15, Math.max(0, kicker.rating - 60) / 200);
      const scored = rand() < successProb;
      events.push({
        // 120 + kick number — an orderable marker, not a real minute. Clients
        // render these as "P1", "P2", … rather than "121'".
        minute: 120 + kickNumber,
        type: scored ? 'penalty_scored' : 'penalty_missed',
        teamParticipantId: p.participantId,
        playerName: kicker.name,
        playerRating: kicker.rating,
      });
      if (scored) {
        if (team === 'A') penaltyScoreA++;
        else penaltyScoreB++;
      }
    };

    const decided = (): 'A' | 'B' | null => {
      if (penaltyScoreA - penaltyScoreB > remainingB) return 'A';
      if (penaltyScoreB - penaltyScoreA > remainingA) return 'B';
      return null;
    };

    for (let round = 0; round < 5; round++) {
      takeKick(participantA, 'A');
      remainingA--;
      let outcome = decided();
      if (outcome) return { penaltyScoreA, penaltyScoreB, winner: outcome, events };

      takeKick(participantB, 'B');
      remainingB--;
      outcome = decided();
      if (outcome) return { penaltyScoreA, penaltyScoreB, winner: outcome, events };
    }

    // Sudden death: one kick each per round until the scores differ once both
    // have taken theirs. Capped generously — the odds of staying level this
    // long are astronomically small, but a hard cap guarantees termination.
    for (let round = 0; round < 20; round++) {
      takeKick(participantA, 'A');
      takeKick(participantB, 'B');
      if (penaltyScoreA !== penaltyScoreB) {
        return {
          penaltyScoreA,
          penaltyScoreB,
          winner: penaltyScoreA > penaltyScoreB ? 'A' : 'B',
          events,
        };
      }
    }

    // Practically unreachable fallback (needed only to guarantee termination
    // has a deterministic result): the higher-rated side is awarded it —
    // never a further coin flip.
    const ratingA = participantA.lineup?.overallRating ?? 50;
    const ratingB = participantB.lineup?.overallRating ?? 50;
    return {
      penaltyScoreA,
      penaltyScoreB,
      winner: ratingA >= ratingB ? 'A' : 'B',
      events,
    };
  }

  /** Seeded PRNG (mulberry32) → deterministic uniform [0, 1) stream. */
  private _mulberry32(seed: number): () => number {
    let a = seed >>> 0;
    return () => {
      a = (a + 0x6d2b79f5) >>> 0;
      let t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t = (t + Math.imul(t ^ (t >>> 7), t | 61)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  /** Draws a Poisson-distributed count using the supplied seeded RNG (Knuth). */
  private _poisson(rand: () => number, lambda: number): number {
    if (lambda <= 0) return 0;
    const L = Math.exp(-lambda);
    let k = 0;
    let p = 1;
    do {
      k += 1;
      p *= rand();
    } while (p > L);
    return k - 1;
  }

  /** Picks a scorer/actor weighted toward attacking positions. */
  /**
   * Picks a weighted-random player card from `p`'s lineup. `excluded` removes
   * players who are no longer eligible to generate further events this match
   * (sent off on a red card) — callers must keep this set updated as the
   * match progresses so a dismissed player can never be picked again (for a
   * goal, assist, miss, card, or penalty). Falls back to the full lineup if
   * everyone eligible has somehow been excluded (should never realistically
   * happen — at most one red card per team — but guarantees a valid pick).
   */
  private _pickPlayerCard(
    rand: () => number,
    p: TournamentParticipant,
    excluded?: Set<string>,
  ): { name: string; rating: number } {
    const cards = p.lineup?.pitchCards;
    if (!cards || cards.length === 0) {
      return { name: p.displayName, rating: p.lineup?.overallRating ?? 50 };
    }
    const pool =
      excluded && excluded.size > 0 ? cards.filter((c) => !excluded.has(c.playerName)) : cards;
    const effective = pool.length > 0 ? pool : cards;
    const weights = effective.map((c) => this._positionAttackWeight(c.basePositionType));
    const total = weights.reduce((s, w) => s + w, 0);
    let r = rand() * total;
    for (let i = 0; i < effective.length; i++) {
      r -= weights[i];
      if (r <= 0) return { name: effective[i].playerName, rating: effective[i].rating };
    }
    const last = effective[effective.length - 1];
    return { name: last.playerName, rating: last.rating };
  }

  private _positionAttackWeight(base: string): number {
    switch (base) {
      case 'GK':
        return 0.05;
      case 'CB':
      case 'LB':
      case 'RB':
      case 'DEF':
        return 1;
      case 'CDM':
      case 'CM':
      case 'CAM':
      case 'LM':
      case 'RM':
      case 'MID':
        return 2.5;
      case 'LW':
      case 'RW':
      case 'CF':
      case 'ST':
      case 'ATK':
        return 5;
      default:
        return 2;
    }
  }

  // ── Tournament helpers ──────────────────────────────────────────────────────

  private _buildParticipantLineup(session: GameSession, playerId: string): ParticipantLineup {
    const pitch = session.pitches[playerId];
    const starters = pitch ? pitch.slots.filter((s) => s.card !== null) : [];
    const pitchCards = starters.map((s) => this._freezeCard(s.card!, s.label));

    const benchCards: FrozenCard[] = [];
    const userSubs = session.subsPhase?.userSubs[playerId];
    if (userSubs) {
      for (const g of ['att', 'mid', 'def', 'extra'] as SubPositionGroup[]) {
        const slot = userSubs[g];
        const card = slot?.benchedCard ?? slot?.chosenCard;
        if (card) benchCards.push(this._freezeCard(card, card.basePositionType as unknown as SlotLabel));
      }
    }

    const overallRating = pitchCards.length > 0
      ? Math.round((pitchCards.reduce((acc, c) => acc + c.rating, 0) / pitchCards.length) * 10) / 10
      : 0;

    const ability = session.playerAbilities[playerId];
    let captainCardId: string | null = null;
    if (ability && ability.type === 'captain' && ability.status === 'used' && ability.sourceSlotIndex != null) {
      captainCardId = pitch?.slots[ability.sourceSlotIndex]?.card?.cardId ?? null;
    }
    const activeAbilityTypes = ability && ability.status === 'used' ? [ability.type] : [];

    return {
      formationSlug: session.formation.slug ?? session.formation.name,
      pitchCards,
      benchCards,
      overallRating,
      chemistryScore: this.computeChemistryScore(session, playerId),
      captainCardId,
      activeAbilityTypes,
    };
  }

  private _freezeCard(card: DraftCard, slotLabel: SlotLabel): FrozenCard {
    return {
      cardId: card.cardId,
      playerName: card.playerName,
      rating: card.rating,
      basePositionType: card.basePositionType,
      slotLabel,
      nationality: card.nationality,
      club: card.club,
      league: card.league ?? '',
      chemistryBonuses: card.chemistryBonuses,
    };
  }

  private _buildBracket(participants: TournamentParticipant[], size: 4 | 8 | 16): TournamentBracket {
    const totalRounds = Math.log2(size);
    const rounds: TournamentRound[] = [];
    for (let r = 1; r <= totalRounds; r++) {
      const matchCount = size / Math.pow(2, r);
      const matches: TournamentMatch[] = [];
      for (let m = 0; m < matchCount; m++) {
        const a = r === 1 ? participants[m * 2] : this._tbdParticipant();
        const b = r === 1 ? participants[m * 2 + 1] : this._tbdParticipant();
        matches.push({
          matchId: `r${r}_m${m + 1}`,
          roundNumber: r,
          participantA: a,
          participantB: b,
          status: 'pending',
          simulationEvents: [],
          nextEventIndex: 0,
          result: null,
          winnerId: null,
        });
      }
      rounds.push({
        roundNumber: r,
        label: this._roundLabel(r, totalRounds),
        matches,
        status: r === 1 ? 'in_progress' : 'pending',
      });
    }
    return { size, rounds };
  }

  /** A not-yet-decided future-round slot. `participantId: ''` signals TBD to clients. */
  private _tbdParticipant(): TournamentParticipant {
    return { kind: 'real', participantId: '', displayName: 'TBD', lineup: null };
  }

  private _roundLabel(roundNumber: number, totalRounds: number): TournamentRoundLabel {
    const fromEnd = totalRounds - roundNumber; // 0 = final
    switch (fromEnd) {
      case 0:
        return 'Final';
      case 1:
        return 'Semi-finals';
      case 2:
        return 'Quarter-finals';
      default:
        return 'Round of 16';
    }
  }

  private _currentRoundRealParticipantIds(t: TournamentState): string[] {
    const round = t.bracket.rounds[t.currentRound - 1];
    const ids: string[] = [];
    for (const m of round.matches) {
      for (const p of [m.participantA, m.participantB]) {
        if (p.kind === 'real' && p.participantId !== '') ids.push(p.participantId);
      }
    }
    return ids;
  }

  private _currentRoundAiParticipantIds(t: TournamentState): string[] {
    const round = t.bracket.rounds[t.currentRound - 1];
    const ids: string[] = [];
    for (const m of round.matches) {
      for (const p of [m.participantA, m.participantB]) {
        if (p.kind === 'ai') ids.push(p.participantId);
      }
    }
    return ids;
  }

  private _participantById(match: TournamentMatch, id: string | null): TournamentParticipant {
    return match.participantA.participantId === id ? match.participantA : match.participantB;
  }

  private _allRealParticipants(t: TournamentState): TournamentParticipant[] {
    const out: TournamentParticipant[] = [];
    for (const m of t.bracket.rounds[0].matches) {
      for (const p of [m.participantA, m.participantB]) {
        if (p.kind === 'real' && p.participantId !== '') out.push(p);
      }
    }
    return out;
  }

  /**
   * Every tournament entrant — real AND AI — used for stat/leaderboard
   * tallying. Leaderboard inclusion is deliberately separate from points
   * eligibility: an AI club's players fully participate in Top Scorer/Most
   * Assists/Best Rating/Clean Sheets/Top Contributions ranking (an AI player
   * can legitimately BE the tournament's top scorer), but `_allRealParticipants`
   * is what gates `pointsAwarded` — AI never receives user reward points, and
   * a category an AI player tops simply awards no points to anyone (no
   * automatic hand-down to the next human).
   */
  private _allParticipants(t: TournamentState): TournamentParticipant[] {
    const out: TournamentParticipant[] = [];
    for (const m of t.bracket.rounds[0].matches) {
      for (const p of [m.participantA, m.participantB]) {
        if (p.participantId !== '') out.push(p);
      }
    }
    return out;
  }

  /**
   * Per-player goals/assists/minutes across the whole tournament, keyed by
   * player name. Minutes are derived from real match participation (this
   * engine has no in-tournament substitutions — a participant's frozen
   * lineup plays every one of their matches): 90 minutes per completed match
   * they featured in, capped at their own red-card minute in any match where
   * they were sent off (never negative, never counted past dismissal).
   * Shootout kicks never add goals/assists/minutes (real football convention
   * — see the MatchEvent type split between 'goal' and 'penalty_scored').
   */
  private _computeTournamentPlayerStats(
    t: TournamentState,
  ): Map<string, { participantId: string; goals: number; assists: number; minutesPlayed: number }> {
    const stats = new Map<
      string,
      { participantId: string; goals: number; assists: number; minutesPlayed: number }
    >();
    const ensure = (playerName: string, participantId: string) => {
      let s = stats.get(playerName);
      if (!s) {
        s = { participantId, goals: 0, assists: 0, minutesPlayed: 0 };
        stats.set(playerName, s);
      }
      return s;
    };

    for (const p of this._allParticipants(t)) {
      const ownNames = new Set((p.lineup?.pitchCards ?? []).map((c) => c.playerName));
      if (ownNames.size === 0) continue;

      for (const round of t.bracket.rounds) {
        for (const m of round.matches) {
          if (m.participantA.participantId !== p.participantId && m.participantB.participantId !== p.participantId) continue;
          if (!m.result) continue; // not completed yet — no stats from this match

          const dismissedAt = new Map<string, number>();
          for (const ev of m.simulationEvents) {
            if (ev.type === 'red_card' && ev.teamParticipantId === p.participantId) {
              dismissedAt.set(ev.playerName, ev.minute);
            }
          }
          for (const name of ownNames) {
            const s = ensure(name, p.participantId);
            const cutoff = dismissedAt.get(name);
            s.minutesPlayed += cutoff !== undefined ? Math.min(cutoff, 90) : 90;
          }

          for (const ev of m.simulationEvents) {
            if (ev.type !== 'goal' || ev.teamParticipantId !== p.participantId) continue;
            ensure(ev.playerName, p.participantId).goals += 1;
            if (ev.assistPlayerName) ensure(ev.assistPlayerName, p.participantId).assists += 1;
          }
        }
      }
    }
    return stats;
  }

  /**
   * Selects the leader(s) for a stat category with the shared-award tie rule:
   * highest stat wins; ties broken by FEWER minutes played; if still tied,
   * every remaining entry SHARES the award (never picked apart further, e.g.
   * by insertion/bracket order). Returns an empty array if nobody qualifies
   * (statOf never > 0 for anyone).
   */
  private _selectSharedLeaders<T>(
    entries: T[],
    statOf: (e: T) => number,
    minutesOf: (e: T) => number,
  ): T[] {
    const qualifying = entries.filter((e) => statOf(e) > 0);
    if (qualifying.length === 0) return [];
    const maxStat = Math.max(...qualifying.map(statOf));
    let leaders = qualifying.filter((e) => statOf(e) === maxStat);
    if (leaders.length === 1) return leaders;
    const minMinutes = Math.min(...leaders.map(minutesOf));
    leaders = leaders.filter((e) => minutesOf(e) === minMinutes);
    return leaders; // still tied after minutes → genuinely shared
  }

  private _computeTournamentAwards(
    t: TournamentState,
    champion: TournamentParticipant,
    runnerUp: TournamentParticipant,
    config: TournamentAwardsConfigValues,
  ): TournamentAwards {
    const playerStats = this._computeTournamentPlayerStats(t);
    const playerEntries = Array.from(playerStats.entries()).map(([playerName, s]) => ({
      playerName,
      ...s,
    }));

    const topScorer = this._selectSharedLeaders(
      playerEntries,
      (e) => e.goals,
      (e) => e.minutesPlayed,
    ).map((e) => ({
      playerName: e.playerName,
      participantId: e.participantId,
      goals: e.goals,
      minutesPlayed: e.minutesPlayed,
    }));

    const mostAssists = this._selectSharedLeaders(
      playerEntries,
      (e) => e.assists,
      (e) => e.minutesPlayed,
    ).map((e) => ({
      playerName: e.playerName,
      participantId: e.participantId,
      assists: e.assists,
      minutesPlayed: e.minutesPlayed,
    }));

    const topContributions = this._selectSharedLeaders(
      playerEntries,
      (e) => e.goals + e.assists,
      (e) => e.minutesPlayed,
    ).map((e) => ({
      playerName: e.playerName,
      participantId: e.participantId,
      goals: e.goals,
      assists: e.assists,
      contributions: e.goals + e.assists,
      minutesPlayed: e.minutesPlayed,
    }));

    // Highest average rating = the individual PLAYER with the highest average
    // MATCH rating across every match they actually played — a genuine
    // per-player award (previously this mistakenly averaged a whole
    // participant's squad and displayed the manager/AI-club name instead of
    // a footballer). Tie-broken the same way as every other stat category:
    // fewer minutes played, then genuinely shared.
    const ratingTotals = new Map<
      string,
      { participantId: string; sum: number; count: number }
    >();
    for (const p of this._allParticipants(t)) {
      const ownPlayerNames = new Set((p.lineup?.pitchCards ?? []).map((c) => c.playerName));
      for (const round of t.bracket.rounds) {
        for (const m of round.matches) {
          if (!m.result) continue;
          if (m.participantA.participantId !== p.participantId && m.participantB.participantId !== p.participantId) continue;
          for (const [playerName, rating] of Object.entries(m.result.playerRatings)) {
            if (!ownPlayerNames.has(playerName)) continue;
            let entry = ratingTotals.get(playerName);
            if (!entry) {
              entry = { participantId: p.participantId, sum: 0, count: 0 };
              ratingTotals.set(playerName, entry);
            }
            entry.sum += rating;
            entry.count++;
          }
        }
      }
    }
    const ratingEntries = Array.from(ratingTotals.entries()).map(([playerName, e]) => ({
      playerName,
      participantId: e.participantId,
      avgRating: Math.round((e.sum / e.count) * 100) / 100,
      minutesPlayed: playerStats.get(playerName)?.minutesPlayed ?? 0,
    }));
    const highestAvgRating = this._selectSharedLeaders(
      ratingEntries,
      (e) => e.avgRating,
      (e) => e.minutesPlayed,
    ).map((e) => ({
      playerName: e.playerName,
      participantId: e.participantId,
      avgRating: e.avgRating,
      minutesPlayed: e.minutesPlayed,
    }));

    // Clean Sheets — credited to the actual goalkeeper (the pitch-slot 'GK'
    // card), never the participant/team display name, so a human manager's
    // username or an AI club's name never masquerades as a "player" award.
    const cleanSheetTotals = new Map<
      string,
      { participantId: string; count: number }
    >();
    for (const p of this._allParticipants(t)) {
      const gk = p.lineup?.pitchCards.find((c) => c.slotLabel === 'GK');
      if (!gk) continue; // no recorded keeper — skip rather than guess an identity
      let conceded0 = 0;
      for (const round of t.bracket.rounds) {
        for (const m of round.matches) {
          const isA = m.participantA.participantId === p.participantId;
          const isB = m.participantB.participantId === p.participantId;
          if (!m.result || (!isA && !isB)) continue;
          const concededByThem = isA ? m.result.scoreB : m.result.scoreA;
          if (concededByThem === 0) conceded0++;
        }
      }
      if (conceded0 > 0) cleanSheetTotals.set(gk.playerName, { participantId: p.participantId, count: conceded0 });
    }
    const cleanSheetEntries = Array.from(cleanSheetTotals.entries()).map(([playerName, e]) => ({
      playerName,
      participantId: e.participantId,
      cleanSheets: e.count,
      minutesPlayed: playerStats.get(playerName)?.minutesPlayed ?? 0,
    }));
    const cleanSheets = this._selectSharedLeaders(
      cleanSheetEntries,
      (e) => e.cleanSheets,
      (e) => e.minutesPlayed,
    ).map((e) => ({
      playerName: e.playerName,
      participantId: e.participantId,
      cleanSheets: e.cleanSheets,
      minutesPlayed: e.minutesPlayed,
    }));

    // Scoring system — admin-configurable (Track A), snapshotted onto the
    // session at tournament start (see GameSession.tournamentAwardsConfig)
    // and passed in as `config`, never re-read here. v1 defaults (the
    // client's leaderboard breakdown mirrors these same values for display):
    //   Champion            +50
    //   Runner-up            +20
    //   Top scorer           +15  (shared: split, rounded UP, equally)
    //   Most assists         +10  (shared: split, rounded UP, equally)
    //   Highest avg rating   +10  (shared: split, rounded UP, equally)
    // Bonuses stack with the champion/runner-up prize (e.g. the champion's
    // own top scorer earns champion+topScorer) and are additive across
    // categories. Only real participants earn points — an AI club topping a
    // stat category (possible since goals/assists are tallied across every
    // match, including AI-involved ones) awards nothing, since AI clubs
    // aren't in contention to "win" the room. Top Contributions is a
    // leaderboard/stat only — it carries no bonus points of its own (see the
    // product spec).
    const TOP_SCORER_BONUS = config.topScorerBonus;
    const MOST_ASSISTS_BONUS = config.mostAssistsBonus;
    const HIGHEST_RATING_BONUS = config.highestRatingBonus;

    const pointsAwarded: Record<string, number> = {};
    if (champion.kind === 'real' && champion.participantId !== '') pointsAwarded[champion.participantId] = config.championPoints;
    if (runnerUp.kind === 'real' && runnerUp.participantId !== '') pointsAwarded[runnerUp.participantId] = config.runnerUpPoints;

    // ── Tie-break rules — explicit and deterministic, never random ──────────
    //
    // Top Scorer / Most Assists / Top Contributions: highest stat wins. A tie
    // is broken by whichever player logged FEWER minutes played (more
    // productive per minute on the pitch). If still tied after that, the
    // award is genuinely SHARED among every remaining tied player — never
    // arbitrarily narrowed to one (e.g. by insertion order or bracket slot).
    //
    // Highest Avg Rating: a genuine per-player stat (2dp average of that
    // player's own match ratings) — same fewer-minutes-played tiebreak as
    // Top Scorer/Most Assists/Top Contributions, then SHARED if still tied.
    //
    // Clean Sheets: credited to the actual goalkeeper, same tiebreak rule.
    // Carries no bonus points (a leaderboard/stat only, like Top Contributions).
    //
    // AI inclusion: every leader list above (topScorer/mostAssists/
    // topContributions/highestAvgRating/cleanSheets) is computed over BOTH
    // real and AI participants — an AI player can legitimately BE the
    // tournament's top scorer, best-rated player, etc., and is shown as such
    // on the leaderboard. `addSharedBonus` below is what enforces the
    // points-only exclusion: it filters each leader list down to real
    // participants before paying out, so an AI-only leader (or an AI among
    // otherwise-tied leaders) simply pays no one for that category — the
    // bonus is never silently handed down to the next human runner-up.
    //
    // Shared-award points: the category's bonus is split EQUALLY among every
    // tied winner, rounded UP to the nearest whole point (e.g. 15 split 2
    // ways → 8 each, not 7/8). Every tied winner receives the identical
    // amount — never less than another winner in the same shared award. The
    // total distributed can exceed the nominal bonus pool (e.g. 8+8=16 for a
    // pool of 15); that is expected and accepted, not a bug.
    //
    // Final total-points winner (the room's overall ranking — see
    // `_finalizeDraft`, which adds `pointsAwarded` into each player's
    // ranking score): two players with an equal total SHARE the same rank
    // (e.g. two players both on rank 2) rather than being arbitrarily split —
    // ties are never broken further. This is deliberate: unlike a single
    // "Top Scorer" award, which must go to exactly one recipient, sharing an
    // equal placement is the standard, defensible convention for an overall
    // leaderboard tie.
    const realIds = new Set(this._allRealParticipants(t).map((p) => p.participantId));
    // Category labels (must match the client's TournamentAwardsModel labels
    // exactly, e.g. "Best Rating") where an AI presence among the (possibly
    // tied) leaders blocked the bonus from paying any human — surfaced to
    // clients so a human leader isn't left silently un-paid with no
    // explanation on the result page.
    const blockedCategories: string[] = [];
    const addSharedBonus = <E extends { participantId: string }>(
      label: string,
      leaders: E[],
      pool: number,
    ) => {
      if (leaders.length === 0) return;
      // AI participates fully in the leaderboard, but if an AI participant is
      // among the (possibly tied) leaders, the category pays NO user points —
      // not even to a human sharing that same tie. There is no automatic
      // hand-down to the next-best human; the category is simply blocked.
      if (!leaders.every((l) => realIds.has(l.participantId))) {
        blockedCategories.push(label);
        return;
      }
      const perWinner = Math.ceil(pool / leaders.length);
      for (const l of leaders) {
        pointsAwarded[l.participantId] = (pointsAwarded[l.participantId] ?? 0) + perWinner;
      }
    };
    addSharedBonus('Top Scorer', topScorer, TOP_SCORER_BONUS);
    addSharedBonus('Most Assists', mostAssists, MOST_ASSISTS_BONUS);
    addSharedBonus('Best Rating', highestAvgRating, HIGHEST_RATING_BONUS);

    return { champion, runnerUp, topScorer, mostAssists, topContributions, highestAvgRating, cleanSheets, pointsAwarded, blockedCategories, pointsConfig: config };
  }

  /** Deterministic non-negative integer hash for seeding simulations. */
  private _seedHash(str: string): number {
    let h = 0;
    for (let i = 0; i < str.length; i++) {
      h = (h * 31 + str.charCodeAt(i)) | 0;
    }
    return Math.abs(h);
  }

  /**
   * Selects `playerCount + 2` candidate cards for `basePositionType` from the
   * shared player pool, excluding cards already drafted in this session.
   * When `leagues` is non-empty, only players from those leagues are considered.
   */
  private generateCandidates(
    basePositionType: BasePositionType,
    draftedCardIds: Set<string>,
    playerCount: number,
    leagues: string[] = [],
    session?: GameSession,
  ): DraftCard[] {
    const count = playerCount + 2;
    const pool = loadPlayerPool();

    // Apply league filter when the room was created with specific leagues
    const leagueSet = new Set(leagues);
    const leagueFiltered = leagueSet.size > 0
      ? pool.filter((p) => {
          const playerLeague = (p as any).league ?? CLUB_LEAGUE[p.club] ?? '';
          return leagueSet.has(playerLeague);
        })
      : pool;

    // Strict primary-position matching: a player is eligible only if the slot's
    // position is one of their configured card positions. No sibling/alt fallback
    // — RW/RM etc. must be explicitly tagged in the player's data.
    const eligible = leagueFiltered.filter(
      (p) =>
        p.positions.includes(basePositionType) && !draftedCardIds.has(p.id),
    );

    if (eligible.length === 0) {
      this.logger.warn(
        { event: 'candidate_pool_exhausted', sessionId: session?.sessionId, basePositionType },
        'Candidate pool exhausted — offering without uniqueness constraint',
      );
      return this.shuffle(
        leagueFiltered.filter((p) => p.positions.includes(basePositionType)),
      )
        .slice(0, count)
        .map((p) => this.toCard(p, basePositionType, session));
    }

    const shuffled = this.shuffle(eligible);
    const picked = shuffled.slice(0, count);

    this.logger.debug(
      {
        event: 'candidates_generated',
        sessionId: session?.sessionId,
        basePositionType,
        offered: picked.length,
        eligible: eligible.length,
        draftedSoFar: draftedCardIds.size,
      },
      'Candidates generated',
    );

    return picked.map((p) => this.toCard(p, basePositionType, session));
  }

  private toCard(
    player: PlayerCardDefinition,
    forPosition: BasePositionType,
    session?: GameSession,
  ): DraftCard {
    const r = player.rating;
    const primary = player.positions[0];
    const isAtk = ['ST', 'CF', 'LW', 'RW'].includes(primary);
    const isDef = ['GK', 'LB', 'CB', 'RB', 'CDM'].includes(primary);

    const clamp = (v: number) => Math.min(99, Math.max(30, Math.round(v)));

    const chemistryBonuses = session?.playerBonusCache.get(player.id) ?? [];

    // Prefer the real per-attribute ratings from the dataset; fall back to
    // rating-derived approximations only when a stat is missing.
    const stat = (real: number | undefined, derived: number) =>
      real != null ? clamp(real) : clamp(derived);

    return {
      cardId:            player.id,
      playerName:        player.name,
      basePositionType:  forPosition,
      rating:            r,
      pace:              stat(player.pace,      isAtk ? r + 2   : isDef ? r - 20 : r - 5),
      shooting:          stat(player.shooting,  isAtk ? r - 1   : isDef ? r - 40 : r - 15),
      passing:           stat(player.passing,   !isAtk && !isDef ? r - 2  : isAtk ? r - 10 : r - 15),
      dribbling:         stat(player.dribbling, isAtk ? r - 3   : !isAtk && !isDef ? r - 7  : r - 18),
      defending:         stat(player.defending, isDef ? r - 2   : !isAtk && !isDef ? r - 22 : r - 38),
      physical:          stat(player.physical,  r - 8),
      nationality:       player.nationality,
      club:              player.club,
      altPositions:      player.positions.slice(1),
      naturalPositions:  [...player.positions],
      imageUrl:          player.photoUrl ?? undefined,
      clubLogoUrl:       player.clubLogoUrl,
      league:            (player as any).league ?? CLUB_LEAGUE[player.club] ?? undefined,
      chemistryBonuses,
    };
  }

  private pickFormation(slug?: string | null): Formation {
    const formations = loadActiveFormations();
    if (slug) {
      const found = formations.find((f) => f.slug === slug);
      if (found) return found;
    }
    return formations[Math.floor(Math.random() * formations.length)];
  }

  private buildPitches(
    playerIds: string[],
    formation: Formation,
  ): Record<string, Pitch> {
    const pitches: Record<string, Pitch> = {};
    for (const playerId of playerIds) {
      const slots: PitchSlot[] = formation.slots.map((s) => ({
        index: s.index,
        label: s.label,
        basePositionType: s.basePositionType,
        card: null,
      }));
      pitches[playerId] = { playerId, slots, filledCount: 0 };
    }
    return pitches;
  }

  private shuffle<T>(arr: T[]): T[] {
    const a = [...arr];
    for (let i = a.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [a[i], a[j]] = [a[j], a[i]];
    }
    return a;
  }
}
