import {
  WebSocketGateway,
  WebSocketServer,
  SubscribeMessage,
  OnGatewayConnection,
  OnGatewayDisconnect,
  MessageBody,
  ConnectedSocket,
} from '@nestjs/websockets';
import {
  Inject,
  OnApplicationShutdown,
  OnModuleDestroy,
  Optional,
  UseGuards,
  UseInterceptors,
  UsePipes,
  ValidationPipe,
} from '@nestjs/common';
import { Throttle, seconds } from '@nestjs/throttler';
import { Server, WebSocket } from 'ws';
import { AdminService } from '../admin/admin.service';
import { GameService } from '../game/game.service';
import { RoomsService } from './rooms.service';
import { WsSafetyInterceptor } from './ws-safety.interceptor.js';
import { CreateRoomDto } from './dto/create-room.dto';
import { JoinRoomDto } from './dto/join-room.dto';
import { ReconnectDto } from './dto/reconnect.dto';
import { KickPlayerDto } from './dto/kick-player.dto';
import { TransferHostDto } from './dto/transfer-host.dto';
import { ApproveJoinDto } from './dto/approve-join.dto';
import { RejectJoinDto } from './dto/reject-join.dto';
import { CheckPresenceDto } from './dto/check-presence.dto';
import { PickSlotDto } from './dto/pick-slot.dto';
import { PickCardDto } from './dto/pick-card.dto';
import { OrderHiddenDeckDto } from './dto/order-hidden-deck.dto';
import { PickHiddenSlotDto } from './dto/pick-hidden-slot.dto';
import { ConfirmHiddenRevealDto } from './dto/confirm-hidden-reveal.dto';
import { LeaveGamePermanentlyDto } from './dto/leave-game-permanently.dto';
import { PickAbilityDto } from './dto/pick-ability.dto';
import { ActivateAbilityDto } from './dto/activate-ability.dto';
import { RequestSubSpinDto } from './dto/request-sub-spin.dto';
import { PickSubDto } from './dto/pick-sub.dto';
import { SwapSubDto } from './dto/swap-sub.dto';
import { SwapRosterDto } from './dto/swap-roster.dto';
import { TournamentReadyDto } from './dto/tournament-ready.dto';
import { SpectateRoomDto } from './dto/spectate-room.dto';
import { SpectatorReconnectDto } from './dto/spectator-reconnect.dto';
import {
  TournamentStatePayload,
  TournamentMatchEventPayload,
  TournamentMatchResultPayload,
  TournamentCompletePayload,
  ParticipantSnapshot,
  MatchSnapshot,
  CompletedMatchSnapshot,
} from './dto/tournament-events.dto';
import { Room, SimulationSpeed } from './interfaces/room.interface';
import {
  GameSession,
  RosterEndpoint,
  TournamentState,
  TournamentParticipant,
  TournamentMatch,
} from '../game/interfaces/game-session.interface';
import { DraftCard } from '../game/interfaces/draft-card.interface';
import { getAllowedOrigins } from '../cors-origins.js';
import {
  generateReconnectToken,
  verifyReconnectToken,
} from '../reconnect-token.js';
import { ErrorCodes } from '../shared/error-codes.js';
import { WsThrottlerGuard } from './ws-throttler.guard.js';
import { InjectPinoLogger, PinoLogger } from 'nestjs-pino';

const STALE_ROOM_MS = 60 * 60 * 1000; // 60 min inactive → close room
const STALE_CHECK_MS = 5 * 60 * 1000; // check every 5 min
const MIN_ACTIVE_PLAYERS = 2;
// Fallback per-picker duration for the ability draft when the room has no
// per-turn timer configured — mirrors ABILITY_ACTIVATION_FALLBACK_SECONDS in
// game.service.ts so neither ability phase can hang forever with timers off.
const ABILITY_DRAFT_FALLBACK_SECONDS = 30;
// Zombie-connection detection (Task 1.7): a TCP connection that dies without
// a clean WS close frame (laptop lid closed, network partition) never fires
// handleDisconnect on its own — see PHASE_0_FINAL_REVIEW.md's residual-risk
// section. The standard ws heartbeat recipe needs two missed intervals to
// confirm-then-terminate a truly dead connection (the first tick can't tell
// "slow to respond" apart from "dead" — only the second can), so a real
// zombie is detected and cleaned up within 2×HEARTBEAT_INTERVAL_MS.
//
// Overridable via HEARTBEAT_INTERVAL_MS_OVERRIDE purely so a live
// verification script can observe the full detect-and-terminate cycle in
// seconds instead of waiting through two real 30s ticks — never set this in
// a real deployment.
const HEARTBEAT_INTERVAL_MS =
  Number(process.env.HEARTBEAT_INTERVAL_MS_OVERRIDE) || 30_000;

// Reconnect-during-turn grace window: a refresh/app-restart necessarily
// closes the old socket (firing handleDisconnect) before the new one
// reconnects (check_presence) — there is always a real gap, never zero.
// Without a grace window, a disconnected active player would get
// auto-picked for on the very first disconnect event, before they ever get
// a chance to reconnect and finish their own turn themselves. The grace
// period gives a normal refresh time to land first — `_scheduleTurnTimer`
// (drafting: selecting_position/selecting_card/first_player_order/
// hidden_pick — every phase except hidden_pick_reveal, which already
// self-heals via its own 5s timer regardless of connection state) only
// arms this timer when the CURRENT active player is disconnected; if they
// reconnect within the window, the timer is cancelled and they keep their
// turn exactly as if nothing happened. If they don't, `_autoPickCurrentPhase`
// picks on their behalf — the same logic a connected-but-slow player's full
// turnSeconds timeout already uses — so a temporary disconnect can never
// leave a still-in-room player with fewer drafted cards than everyone else.
const ACTIVE_TURN_DISCONNECT_GRACE_MS = 10_000;

// Restricted to ALLOWED_ORIGINS (env, comma-separated) — see cors-origins.ts.
// Evaluated once at module load, same as main.ts's HTTP CORS config, so both
// transports always agree on who's allowed to connect.
@WebSocketGateway({ cors: { origin: getAllowedOrigins() } })
// Applies to every @SubscribeMessage handler in this class: a malformed or
// unexpected payload always produces a clean error response to the sender
// instead of silently going unanswered. See ws-safety.interceptor.ts.
@UseInterceptors(WsSafetyInterceptor)
// Task 1.2: app.useGlobalPipes() in main.ts does NOT reach @MessageBody() on
// this gateway in practice — verified live (a deliberately invalid payload
// sailed straight through to the handler with the global pipe registered and
// nothing else). @nestjs/platform-ws's WS parameter-binding apparently
// doesn't consult globally-registered pipes the way HTTP @Body() does.
// Mirrors @UseInterceptors above: explicit, class-level, proven to actually
// run for this transport.
@UsePipes(
  new ValidationPipe({
    whitelist: true,
    forbidNonWhitelisted: true,
    transform: true,
  }),
)
// Task 1.3: real rate limiting, replacing the Phase 0 hand-rolled token
// bucket. A generous connection-wide default (30/10s, see
// shared/throttler-config.ts) applies to every handler; create_room/
// reconnect/check_presence layer a much tighter @Throttle() override below —
// same reasoning as the Phase 0 stopgap (these are the only endpoints
// callable before a player is meaningfully "in" anything, so they're the
// highest-risk targets for a scripted flood).
@UseGuards(WsThrottlerGuard)
export class RoomsGateway
  implements
    OnGatewayConnection,
    OnGatewayDisconnect,
    OnModuleDestroy,
    OnApplicationShutdown
{
  @WebSocketServer()
  server: Server;

  private cleanupTimer: ReturnType<typeof setInterval>;
  private heartbeatTimer: ReturnType<typeof setInterval>;
  // roomCode → auto-advance timer for the hidden_pick_reveal phase
  private hiddenRevealTimeouts = new Map<
    string,
    ReturnType<typeof setTimeout>
  >();
  // roomCode → grace-period timer before the disconnected active player is
  // auto-picked for (see ACTIVE_TURN_DISCONNECT_GRACE_MS). Cleared the
  // moment the same room's disconnected player successfully reconnects via
  // check_presence.
  private readonly _disconnectedTurnTimers = new Map<
    string,
    ReturnType<typeof setTimeout>
  >();
  // sessionId → per-turn auto-pick timer
  private readonly _turnTimers = new Map<
    string,
    ReturnType<typeof setTimeout>
  >();
  // sessionId → bench_selection / lineup_edit auto-finalize timer, keyed with
  // the deadline it was armed for so a fresh deadline (phase transition) always
  // re-arms instead of silently keeping the previous phase's timer.
  private readonly _subsTimers = new Map<
    string,
    { timer: ReturnType<typeof setTimeout>; deadlineAt: number }
  >();
  // sessionId → ability-draft per-picker auto-pick timer
  private readonly _abilityDraftTimers = new Map<
    string,
    ReturnType<typeof setTimeout>
  >();
  // sessionId → ability-activation phase auto-discard timer
  private readonly _abilityActivationTimers = new Map<
    string,
    ReturnType<typeof setTimeout>
  >();
  // roomCode → ability-draft "last pick reveal window" timer (3.5s, before
  // beginPlayerDraft). Tracked so a module teardown mid-window can't leave it
  // dangling or fire against a torn-down gateway.
  private readonly _abilityRevealTimers = new Map<
    string,
    ReturnType<typeof setTimeout>
  >();
  // roomCode → ability-activation "everyone revealed, hold before subs"
  // window (3.5s, before finishAbilityActivation). Same shape/purpose as
  // _abilityRevealTimers, one phase later.
  private readonly _abilityActivationRevealTimers = new Map<
    string,
    ReturnType<typeof setTimeout>
  >();
  // Tournament timers, all keyed by roomCode (one session per room). The
  // orchestration flows entirely through roomCode, so these mirror that rather
  // than the sessionId keying the draft/subs timers use.
  // roomCode → 8s bracket_reveal auto-advance
  private readonly _tournamentRevealTimers = new Map<
    string,
    ReturnType<typeof setTimeout>
  >();
  // roomCode → 60s ready_check auto-ready
  private readonly _tournamentReadyTimers = new Map<
    string,
    ReturnType<typeof setTimeout>
  >();
  // roomCode → 1500ms live simulation event-delivery interval
  private readonly _tournamentSimTimers = new Map<
    string,
    ReturnType<typeof setInterval>
  >();
  // roomCode → post-result pause (3s between rounds / before complete, 5s round result)
  private readonly _tournamentResultTimers = new Map<
    string,
    ReturnType<typeof setTimeout>
  >();
  // Task 2.1: socketId → live WebSocket, populated in handleConnection and
  // cleared in handleDisconnect — the only two mutation points, both already
  // structurally guaranteed to fire for every connect/disconnect. Every
  // broadcast loop in this file used to iterate ALL of `server.clients`
  // (every socket connected to the WHOLE server, across every room) and
  // filter down to the room it actually needed — O(total connections) work
  // per action in any single room. Combined with `roomsService.getSocketIds
  // (roomCode)` (already O(room size), already the authoritative source of
  // room membership), this turns every broadcast into a direct O(room size)
  // lookup instead.
  //
  // Deliberately NOT a `Map<roomCode, Set<WebSocket>>` keyed by room: that
  // would require duplicating room-membership bookkeeping that
  // `rooms.service.ts` already owns across 9+ separate mutation points
  // (create/join/approve/reconnect/kick/3×leave/disconnect) into a second,
  // gateway-side structure — every one of those would need a matching
  // gateway-side add/remove call, and a single missed one creates either a
  // broadcast leak or a stale-entry leak. A flat, connection-lifecycle-keyed
  // map needs none of that: it doesn't track room membership at all, only
  // "is this socket currently connected," which `handleConnection`/
  // `handleDisconnect` already answer correctly by construction.
  private readonly _connectedSockets = new Map<
    string,
    WebSocket & { id: string }
  >();

  constructor(
    private readonly roomsService: RoomsService,
    private readonly gameService: GameService,
    // Explicit @Inject — a TypeScript default (`= null`) makes Nest skip
    // wiring AdminService, which left production create_room unable to
    // resolve league bundles (always INVALID_LEAGUE_BUNDLE).
    // @Optional keeps `new RoomsGateway(rooms, game)` unit tests working.
    @Optional()
    @Inject(AdminService)
    private readonly adminService: AdminService | undefined,
    // Defaulted (not required) so every existing `new RoomsGateway(roomsService,
    // gameService)` test instantiation keeps working unchanged — DI always
    // supplies the real, app-configured logger; this standalone fallback
    // only ever runs in a test/non-DI context.
    @InjectPinoLogger(RoomsGateway.name)
    private readonly logger: PinoLogger = new PinoLogger({
      pinoHttp: { level: 'silent' },
    }),
  ) {
    this.cleanupTimer = setInterval(
      () => this._cleanStaleRooms(),
      STALE_CHECK_MS,
    );
    this.heartbeatTimer = setInterval(
      () => this._heartbeat(),
      HEARTBEAT_INTERVAL_MS,
    );
  }

  /** Number of currently open WebSocket connections. For /metrics (Task 3.4). */
  getConnectedSocketCount(): number {
    return this._connectedSockets.size;
  }

  // ── Heartbeat / zombie-connection detection (Task 1.7) ─────────────────────

  /**
   * NestJS gateway lifecycle hook — fires once per new connection (in
   * addition to IdStampingWsAdapter's own id-stamping, which runs first).
   * Marks the socket alive and listens for its pong replies, the standard
   * `ws` heartbeat pattern: https://github.com/websockets/ws#how-to-detect-and-close-broken-connections
   */
  handleConnection(
    client: WebSocket & { id: string; isAlive?: boolean },
  ): void {
    this.logger.info(
      { event: 'socket_opened', socketId: client.id },
      'socket opened',
    );
    this._connectedSockets.set(client.id, client);
    client.isAlive = true;
    client.on('pong', () => {
      client.isAlive = true;
    });
  }

  private _heartbeat(): void {
    (
      this._connectedSockets as Map<
        string,
        WebSocket & { id?: string; isAlive?: boolean }
      >
    ).forEach((client) => {
      if (client.isAlive === false) {
        // Missed the previous ping entirely — dead. terminate() fires the
        // 'close' event, which triggers handleDisconnect and the existing
        // cleanup logic (room/session teardown, timer clearing) from there.
        this.logger.debug(
          { socketId: client.id },
          'Heartbeat: terminating unresponsive connection',
        );
        client.terminate();
        return;
      }
      client.isAlive = false;
      client.ping();
    });
  }

  onModuleDestroy(): void {
    clearInterval(this.cleanupTimer);
    clearInterval(this.heartbeatTimer);
    this.hiddenRevealTimeouts.forEach((tid) => clearTimeout(tid));
    this.hiddenRevealTimeouts.clear();
    this._disconnectedTurnTimers.forEach((tid) => clearTimeout(tid));
    this._disconnectedTurnTimers.clear();
    this._turnTimers.forEach((tid) => clearTimeout(tid));
    this._turnTimers.clear();
    this._subsTimers.forEach((entry) => clearTimeout(entry.timer));
    this._subsTimers.clear();
    this._abilityDraftTimers.forEach((tid) => clearTimeout(tid));
    this._abilityDraftTimers.clear();
    this._abilityActivationTimers.forEach((tid) => clearTimeout(tid));
    this._abilityActivationTimers.clear();
    this._abilityRevealTimers.forEach((tid) => clearTimeout(tid));
    this._abilityRevealTimers.clear();
    this._abilityActivationRevealTimers.forEach((tid) => clearTimeout(tid));
    this._abilityActivationRevealTimers.clear();
    this._tournamentRevealTimers.forEach((tid) => clearTimeout(tid));
    this._tournamentRevealTimers.clear();
    this._tournamentReadyTimers.forEach((tid) => clearTimeout(tid));
    this._tournamentReadyTimers.clear();
    this._tournamentSimTimers.forEach((tid) => clearInterval(tid));
    this._tournamentSimTimers.clear();
    this._tournamentResultTimers.forEach((tid) => clearTimeout(tid));
    this._tournamentResultTimers.clear();
  }

  // ── Graceful shutdown (Task 1.6) ────────────────────────────────────────────

  /**
   * Sends every currently-connected socket a `server_shutdown` warning.
   * Called by main.ts's SIGTERM handler before the drain window starts, so
   * connected clients get a chance to show a "reconnecting" message instead
   * of just silently dying when the process exits.
   */
  broadcastShutdownWarning(): void {
    const payload = JSON.stringify({
      event: 'server_shutdown',
      data: { message: 'Server restarting, please reconnect in a moment' },
    });
    this._connectedSockets.forEach((c) => {
      if (c.readyState === WebSocket.OPEN) c.send(payload);
    });
  }

  /**
   * NestJS application-shutdown lifecycle hook — runs as part of app.close(),
   * after main.ts's SIGTERM handler has already warned clients and waited out
   * the drain window. Closes any sockets still open at that point with a
   * clean WS close frame (1001 "going away") rather than letting the process
   * exit and leave them to time out on their own.
   */
  onApplicationShutdown(signal?: string): void {
    this.logger.info(
      { signal, openSockets: this._connectedSockets.size },
      'Closing WebSocket connections for shutdown',
    );
    this._connectedSockets.forEach((c) => {
      if (c.readyState === WebSocket.OPEN)
        c.close(1001, 'Server shutting down');
    });
    // Not cleared in onModuleDestroy (which runs first in Nest's shutdown
    // sequence) — this method needs the live entries to actually close
    // anything. Cleared here, last, for hygiene/symmetry with the timer Maps.
    this._connectedSockets.clear();
  }

  private _cleanStaleRooms(): void {
    const cutoff = Date.now() - STALE_ROOM_MS;
    for (const roomCode of this.roomsService.getStaleRooms(cutoff)) {
      // Belt-and-suspenders: never sweep a room that still has an active,
      // unfinished game session with at least one connected player, even if
      // lastActivityAt looks stale. touchRoomActivity() on every gameplay
      // action (see gameplay handlers above) should make lastActivityAt
      // accurate in practice — this is a second, independent line of defense
      // against ever deleting a game out from under players who are still
      // there, not the primary fix.
      const session = this.gameService.getSessionByRoomCode(roomCode);
      if (session && !session.isFinished) {
        const room = this.roomsService.getRoom(roomCode);
        const hasConnectedPlayer =
          room?.players.some((p) => p.isConnected) ?? false;
        if (hasConnectedPlayer) continue;
      }
      this._clearAllTimersForSession(roomCode, session?.sessionId);
      this.gameService.endSession(roomCode);
      this.roomsService.closeRoom(roomCode);
    }
  }

  /**
   * Clears every gateway-owned timer associated with a session/room in one
   * place. MUST be called alongside every `gameService.endSession(roomCode)`
   * call — found during the Phase 0 production-safety review that
   * `handleDisconnect`'s "last player leaves" path ended the room but not the
   * session, leaving any still-armed timer to keep firing against (and
   * silently auto-advancing) an orphaned, unreachable session forever. See
   * PHASE_0_FINAL_REVIEW.md, "Critical fix" section.
   */
  private _clearAllTimersForSession(
    roomCode: string,
    sessionId?: string,
  ): void {
    this._clearHiddenRevealTimeout(roomCode);
    this._clearDisconnectedTurnTimer(roomCode);
    this._clearAbilityRevealTimer(roomCode);
    this._clearAbilityActivationRevealTimer(roomCode);
    // Tournament timers are keyed by roomCode (always available here), so they
    // clear regardless of whether sessionId was supplied.
    const revealTimer = this._tournamentRevealTimers.get(roomCode);
    if (revealTimer) {
      clearTimeout(revealTimer);
      this._tournamentRevealTimers.delete(roomCode);
    }
    const readyTimer = this._tournamentReadyTimers.get(roomCode);
    if (readyTimer) {
      clearTimeout(readyTimer);
      this._tournamentReadyTimers.delete(roomCode);
    }
    const simTimer = this._tournamentSimTimers.get(roomCode);
    if (simTimer) {
      clearInterval(simTimer);
      this._tournamentSimTimers.delete(roomCode);
    }
    const resultTimer = this._tournamentResultTimers.get(roomCode);
    if (resultTimer) {
      clearTimeout(resultTimer);
      this._tournamentResultTimers.delete(roomCode);
    }
    if (sessionId) {
      this._clearTurnTimer(sessionId);
      this._clearSubsTimer(sessionId);
      this._clearAbilityDraftTimer(sessionId);
      this._clearAbilityActivationTimer(sessionId);
    }
  }

  // ── Low-level helpers ──────────────────────────────────────────────────────

  private send(client: WebSocket, event: string, data: unknown): void {
    if (client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify({ event, data }));
    }
  }

  private sendToSocket(socketId: string, event: string, data: unknown): void {
    const c = this._connectedSockets.get(socketId);
    if (c) this.send(c, event, data);
  }

  private broadcastToSockets(
    socketIds: string[],
    event: string,
    data: unknown,
  ): void {
    for (const id of socketIds) {
      const c = this._connectedSockets.get(id);
      if (c) this.send(c, event, data);
    }
  }

  private broadcastRoom(roomCode: string, event: string, data: unknown): void {
    this.broadcastToSockets(
      this.roomsService.getSocketIds(roomCode),
      event,
      data,
    );
  }

  /** Sends slot_candidates to the current active player (selecting_card phase). */
  private sendCandidatesToActivePlayer(
    session: GameSession,
    roomCode: string,
    candidates: DraftCard[],
  ): void {
    const socketIds = this.roomsService.getSocketIds(roomCode);
    for (const id of socketIds) {
      const c = this._connectedSockets.get(id);
      if (!c) continue;
      const entry = this.roomsService.getSocketEntry(id);
      if (entry?.playerId === session.turn.activePlayerId) {
        this.send(c, 'slot_candidates', {
          turnId: session.turn.turnId,
          candidates,
        });
      }
    }
  }

  /** Sends first_player_order_prompt to the active player (first_player_order phase). */
  private sendOrderPromptToActivePlayer(
    session: GameSession,
    roomCode: string,
    cards: DraftCard[],
  ): void {
    const socketIds = this.roomsService.getSocketIds(roomCode);
    for (const id of socketIds) {
      const c = this._connectedSockets.get(id);
      if (!c) continue;
      const entry = this.roomsService.getSocketEntry(id);
      if (entry?.playerId === session.turn.activePlayerId) {
        this.send(c, 'first_player_order_prompt', {
          turnId: session.turn.turnId,
          cards,
        });
      }
    }
  }

  /**
   * Sends hidden_pick_prompt to the active player (hidden_pick phase).
   *
   * Slot-to-card mapping is NEVER sent — `totalSlots`/`availableSlots`
   * carry no card identity. `previewCards` is the one deliberate exception:
   * the FULL set of remaining cards, for the client's "magician" reveal-
   * conceal-shuffle intro animation (the picker briefly sees what's left in
   * the deck before it's turned face-down) — see `_previewCardsFor`'s doc
   * comment for exactly why this can't leak the real order.
   */
  private sendHiddenPickPromptToActivePlayer(
    session: GameSession,
    roomCode: string,
    availableSlots: number[],
  ): void {
    const socketIds = this.roomsService.getSocketIds(roomCode);
    for (const id of socketIds) {
      const c = this._connectedSockets.get(id);
      if (!c) continue;
      const entry = this.roomsService.getSocketEntry(id);
      if (entry?.playerId === session.turn.activePlayerId) {
        this.send(c, 'hidden_pick_prompt', {
          turnId: session.turn.turnId,
          totalSlots: session.orderedHiddenDeck.length,
          availableSlots,
          previewCards: this._previewCardsFor(session),
        });
      }
    }
  }

  /**
   * The remaining hidden-deck cards, resorted by `cardId` — deliberately
   * NOT `session.orderedHiddenDeck`'s own array order, since that array
   * index IS the real slot index (`orderedHiddenDeck[slotIndex]` is exactly
   * how `pickHiddenSlot` resolves a pick — see game.service.ts). Sending
   * cards in that order, in any client-visible field, would let the picker
   * read the real slot mapping directly off the wire before ever tapping a
   * slot, defeating the entire hidden-pick mechanic. Re-sorting by cardId
   * breaks that positional correlation completely while still giving the
   * client the exact card identities it needs for the face-up preview
   * step of the reveal-conceal-shuffle intro animation. Only ever sent to
   * the active picker (see the two call sites), never broadcast.
   */
  private _previewCardsFor(session: GameSession): DraftCard[] {
    return [...session.orderedHiddenDeck].sort((a, b) =>
      a.cardId.localeCompare(b.cardId),
    );
  }

  // ── Snapshot builders ──────────────────────────────────────────────────────

  private roomSnapshot(room: Room, playerId?: string, spectatorId?: string) {
    return {
      code: room.code,
      isStarted: room.isStarted,
      isLocked: room.isLocked,
      players: room.players.map((p) => ({
        id: p.id,
        displayName: p.displayName,
        isHost: p.isHost,
        isConnected: p.isConnected,
      })),
      // Read-only observers — see Spectator's docstring in room.interface.ts.
      // Included so players can see who's watching; never affects gameplay.
      spectators: room.spectators.map((s) => ({
        id: s.id,
        displayName: s.displayName,
        isConnected: s.isConnected,
      })),
      pendingCount: room.pendingJoinRequests.length,
      localPlayerId: playerId ?? null,
      localSpectatorId: spectatorId ?? null,
      tournamentEnabled: room.tournamentEnabled ?? false,
    };
  }

  private gameSnapshot(session: GameSession, localPlayerId?: string) {
    return this.gameService.buildSnapshot(session, localPlayerId);
  }

  // ── Room events ────────────────────────────────────────────────────────────

  @SubscribeMessage('create_room')
  // The only handler callable with zero prior state (no room/session
  // membership needed) — the single highest-risk target for a scripted
  // flood, hence the tightest limit of any handler in this gateway.
  @Throttle({ default: { limit: 5, ttl: seconds(60) } })
  handleCreateRoom(
    @MessageBody() dto: CreateRoomDto,
    @ConnectedSocket() client: WebSocket & { id: string },
  ): void {
    this.logger.info(
      {
        event: 'create_room',
        socketId: client.id,
        turnTimerSeconds: dto.turnTimerSeconds ?? null,
        subsTimerSeconds: dto.subsTimerSeconds ?? null,
        abilityTimerSeconds: dto.abilityTimerSeconds ?? null,
        leagueBundleId: dto.leagueBundleId ?? null,
      },
      'Room created',
    );

    const manualLeagues = dto.leagues ?? [];
    const hasManual = manualLeagues.length > 0;
    const hasBundle = !!dto.leagueBundleId?.trim();

    if (hasManual && hasBundle) {
      this.send(client, 'error', { code: ErrorCodes.AMBIGUOUS_LEAGUES });
      return;
    }

    let leagues = manualLeagues;
    let selectedBundleId: string | null = null;
    let selectedBundleName: string | null = null;

    if (hasBundle) {
      if (!this.adminService) {
        this.logger.error(
          { leagueBundleId: dto.leagueBundleId },
          'create_room: AdminService not injected — cannot resolve league bundle',
        );
        this.send(client, 'error', { code: ErrorCodes.INVALID_LEAGUE_BUNDLE });
        return;
      }
      try {
        const resolved = this.adminService.resolveLeagueBundleForRoom(
          dto.leagueBundleId!.trim(),
        );
        leagues = resolved.leagueNames;
        selectedBundleId = resolved.bundle.id;
        selectedBundleName = resolved.bundle.name;
      } catch (err) {
        this.logger.warn(
          { err, leagueBundleId: dto.leagueBundleId },
          'create_room: league bundle resolve failed',
        );
        this.send(client, 'error', { code: ErrorCodes.INVALID_LEAGUE_BUNDLE });
        return;
      }
    }

    const result = this.roomsService.createRoom(
      dto.displayName,
      client.id,
      leagues,
      dto.turnTimerSeconds ?? null,
      dto.subsTimerSeconds ?? null,
      dto.formationSlug ?? null,
      dto.tournamentEnabled ?? false,
      dto.simulationSpeed ?? 'normal',
      dto.abilityTimerSeconds ?? null,
      selectedBundleId,
      selectedBundleName,
    );
    this.send(client, 'room_update', {
      ...this.roomSnapshot(result.room, result.playerId),
      reconnectToken: generateReconnectToken(result.playerId, result.room.code),
    });
  }

  @SubscribeMessage('join_room')
  handleJoinRoom(
    @MessageBody() dto: JoinRoomDto,
    @ConnectedSocket() client: WebSocket & { id: string },
  ): void {
    const result = this.roomsService.joinRoom(
      dto.roomCode,
      dto.displayName,
      client.id,
    );

    if ('error' in result) {
      this.send(client, 'error', { code: result.error });
      return;
    }

    if ('pending' in result) {
      this.send(client, 'join_pending', {
        requestId: result.request.requestId,
        displayName: result.request.displayName,
        roomCode: result.roomCode,
      });
      if (result.hostSocketId) {
        this.sendToSocket(result.hostSocketId, 'join_request', {
          requestId: result.request.requestId,
          displayName: result.request.displayName,
        });
      }
      return;
    }

    this.send(client, 'room_update', {
      ...this.roomSnapshot(result.room, result.playerId),
      reconnectToken: generateReconnectToken(result.playerId, result.room.code),
    });
    this.broadcastRoom(
      result.room.code,
      'room_update',
      this.roomSnapshot(result.room),
    );
  }

  @SubscribeMessage('approve_join')
  handleApproveJoin(
    @MessageBody() dto: ApproveJoinDto,
    @ConnectedSocket() client: WebSocket & { id: string },
  ): void {
    const result = this.roomsService.approveJoin(client.id, dto.requestId);
    if ('error' in result) {
      this.send(client, 'error', { code: result.error });
      return;
    }
    this.sendToSocket(result.approvedSocketId, 'room_update', {
      ...this.roomSnapshot(result.room, result.playerId),
      reconnectToken: generateReconnectToken(result.playerId, result.room.code),
    });
    this.broadcastRoom(
      result.roomCode,
      'room_update',
      this.roomSnapshot(result.room),
    );
  }

  @SubscribeMessage('reject_join')
  handleRejectJoin(
    @MessageBody() dto: RejectJoinDto,
    @ConnectedSocket() client: WebSocket & { id: string },
  ): void {
    const result = this.roomsService.rejectJoin(client.id, dto.requestId);
    if ('error' in result) {
      this.send(client, 'error', { code: result.error });
      return;
    }
    this.sendToSocket(result.rejectedSocketId, 'join_rejected', {});
  }

  @SubscribeMessage('reconnect')
  @Throttle({ default: { limit: 10, ttl: seconds(30) } })
  handleReconnect(
    @MessageBody() dto: ReconnectDto,
    @ConnectedSocket() client: WebSocket & { id: string },
  ): void {
    if (!verifyReconnectToken(dto.reconnectToken, dto.playerId, dto.roomCode)) {
      this.send(client, 'error', { code: ErrorCodes.INVALID_TOKEN });
      return;
    }
    const result = this.roomsService.reconnect(
      dto.roomCode,
      dto.playerId,
      client.id,
    );
    if ('error' in result) {
      this.send(client, 'error', { code: result.error });
      return;
    }
    this.send(
      client,
      'room_update',
      this.roomSnapshot(result.room, dto.playerId),
    );
    this.broadcastRoom(
      result.room.code,
      'room_update',
      this.roomSnapshot(result.room),
    );

    const session = this.gameService.getSessionByRoomCode(dto.roomCode);
    if (session) {
      this.gameService.updatePlayerConnection(dto.roomCode, dto.playerId, true);
      this.send(client, 'game_state', this.gameSnapshot(session, dto.playerId));
      this._resendPhasePrompt(client, session, dto.playerId);
      // Tournament in progress → resync the reconnecting player's tournament UI.
      if (session.status === 'tournament' && session.tournament) {
        this.sendToSocket(
          client.id,
          'tournament_state',
          this.buildTournamentStatePayload(session.tournament),
        );
      }
    }
  }

  // ── Leave: lobby (permanent) ───────────────────────────────────────────────

  @SubscribeMessage('leave_lobby')
  handleLeaveLobby(
    @ConnectedSocket() client: WebSocket & { id: string },
  ): void {
    const result = this.roomsService.leaveLobby(client.id);
    if (!result) return;
    if (result.room) {
      this.broadcastRoom(
        result.roomCode,
        'room_update',
        this.roomSnapshot(result.room),
      );
    }
  }

  // ── Leave: exit game to home (temporary — player stays in game) ────────────

  @SubscribeMessage('exit_game_to_home')
  handleExitGameToHome(
    @ConnectedSocket() client: WebSocket & { id: string },
  ): void {
    const result = this.roomsService.exitGameToHome(client.id);
    if (!result) return;

    this.gameService.updatePlayerConnection(
      result.roomCode,
      result.playerId,
      false,
    );

    this.broadcastRoom(
      result.roomCode,
      'room_update',
      this.roomSnapshot(result.room),
    );
    const session = this.gameService.getSessionByRoomCode(result.roomCode);
    if (session) {
      // Personalized (Phase 7 audit — a leftover instance of the same bug
      // fixed everywhere else in Phase 3): broadcastRoom sends one shared,
      // non-personalized snapshot with no localPlayerId, which blanks every
      // recipient's own private fields (myAbility, the active
      // selecting_card player's candidate pool, scoringPreview) on every
      // exit-to-home, not just this player's own. See the identical fix in
      // handleDisconnect/handleKickPlayer/handleLeaveGamePermanently.
      this._broadcastGameStateToRoom(
        session,
        result.roomCode,
        this.roomsService.getSocketIds(result.roomCode),
      );
    }
  }

  // ── Leave: game permanently (full removal during running game) ────────────

  @SubscribeMessage('leave_game_permanently')
  handleLeaveGamePermanently(
    @MessageBody() dto: LeaveGamePermanentlyDto,
    @ConnectedSocket() client: WebSocket & { id: string },
  ): void {
    const result = this.roomsService.leaveGamePermanently(
      client.id,
      dto?.playerId,
      dto?.roomCode,
    );
    if (!result) return;

    this._clearHiddenRevealTimeout(result.roomCode);
    const removeResult = this.gameService.removePlayer(
      result.roomCode,
      result.playerId,
    );

    if (this._tryEndGame(result.roomCode)) return;

    if (result.room) {
      this.broadcastRoom(
        result.roomCode,
        'room_update',
        this.roomSnapshot(result.room),
      );
      const session = this.gameService.getSessionByRoomCode(result.roomCode);
      if (session) {
        // Personalized (not broadcastRoom) — a non-personalized snapshot has
        // no localPlayerId, so every recipient would transiently see their
        // OWN private fields (myAbility, the active selecting_card player's
        // candidate pool, scoringPreview) wiped to null/empty, immediately
        // overwritten a moment later by whatever the phase's own follow-up
        // broadcast sends (e.g. _afterPlayerRemoved's ability_draft path).
        // Not a privacy leak either way (no one ever sees ANOTHER player's
        // data) — just an avoidable stale/blank-flash risk this fixes for
        // every phase at once, rather than special-casing 'ability_draft'.
        this._broadcastGameStateToRoom(
          session,
          result.roomCode,
          this.roomsService.getSocketIds(result.roomCode),
        );
        this._maybeSendNextPrompt(session, result.roomCode, removeResult);
      }
    }

    this._afterPlayerRemoved(removeResult, result.roomCode);
  }

  // ── Host moderation ────────────────────────────────────────────────────────

  @SubscribeMessage('kick_player')
  handleKickPlayer(
    @MessageBody() dto: KickPlayerDto,
    @ConnectedSocket() client: WebSocket & { id: string },
  ): void {
    const result = this.roomsService.kickPlayer(client.id, dto.targetPlayerId);
    if ('error' in result) {
      this.send(client, 'error', { code: result.error });
      return;
    }

    this._clearHiddenRevealTimeout(result.roomCode);
    const removeResult = this.gameService.removePlayer(
      result.roomCode,
      dto.targetPlayerId,
    );

    if (result.targetSocketId) {
      this.sendToSocket(result.targetSocketId, 'kicked', {
        reason: 'KICKED_BY_HOST',
      });
    }

    if (this._tryEndGame(result.roomCode)) return;

    this.broadcastRoom(
      result.roomCode,
      'room_update',
      this.roomSnapshot(result.room),
    );
    const session = this.gameService.getSessionByRoomCode(result.roomCode);
    if (session) {
      // See the identical comment in handleLeaveGamePermanently.
      this._broadcastGameStateToRoom(
        session,
        result.roomCode,
        this.roomsService.getSocketIds(result.roomCode),
      );
      this._maybeSendNextPrompt(session, result.roomCode, removeResult);
    }

    this._afterPlayerRemoved(removeResult, result.roomCode);
  }

  @SubscribeMessage('transfer_host')
  handleTransferHost(
    @MessageBody() dto: TransferHostDto,
    @ConnectedSocket() client: WebSocket & { id: string },
  ): void {
    const result = this.roomsService.transferHost(
      client.id,
      dto.targetPlayerId,
    );
    if ('error' in result) {
      this.send(client, 'error', { code: result.error });
      return;
    }
    this.broadcastRoom(
      result.roomCode,
      'room_update',
      this.roomSnapshot(result.room),
    );
  }

  @SubscribeMessage('lock_room')
  handleLockRoom(@ConnectedSocket() client: WebSocket & { id: string }): void {
    const result = this.roomsService.lockRoom(client.id);
    if ('error' in result) {
      this.send(client, 'error', { code: result.error });
      return;
    }
    this.broadcastRoom(
      result.roomCode,
      'room_update',
      this.roomSnapshot(result.room),
    );
  }

  @SubscribeMessage('unlock_room')
  handleUnlockRoom(
    @ConnectedSocket() client: WebSocket & { id: string },
  ): void {
    const result = this.roomsService.unlockRoom(client.id);
    if ('error' in result) {
      this.send(client, 'error', { code: result.error });
      return;
    }
    this.broadcastRoom(
      result.roomCode,
      'room_update',
      this.roomSnapshot(result.room),
    );
  }

  // ── Presence ───────────────────────────────────────────────────────────────

  @SubscribeMessage('check_presence')
  @Throttle({ default: { limit: 10, ttl: seconds(30) } })
  handleCheckPresence(
    @MessageBody() dto: CheckPresenceDto,
    @ConnectedSocket() client: WebSocket & { id: string },
  ): void {
    this.logger.info(
      {
        event: 'check_presence',
        phase: 'request',
        socketId: client.id,
        playerId: dto.playerId,
        roomCode: dto.roomCode,
      },
      'check_presence: request',
    );
    if (!verifyReconnectToken(dto.reconnectToken, dto.playerId, dto.roomCode)) {
      this.logger.info(
        {
          event: 'check_presence',
          phase: 'response',
          result: 'rejected',
          reason: 'invalid_token',
          socketId: client.id,
          playerId: dto.playerId,
          roomCode: dto.roomCode,
        },
        'check_presence: response (rejected — invalid token)',
      );
      this.send(client, 'error', { code: ErrorCodes.INVALID_TOKEN });
      return;
    }
    const result = this.roomsService.checkPresence(dto.playerId, dto.roomCode);
    if (!result.found) {
      // roomsService.checkPresence already logged the specific not-found
      // reason (stale_or_wrong_room / room_gone / player_not_in_room) —
      // this is the response-level counterpart so "request" and "response"
      // always appear as a matched pair in the log stream.
      this.logger.info(
        {
          event: 'check_presence',
          phase: 'response',
          result: 'rejected',
          reason: 'not_found',
          socketId: client.id,
          playerId: dto.playerId,
          roomCode: dto.roomCode,
        },
        'check_presence: response (rejected — not found)',
      );
      this.send(client, 'error', { code: ErrorCodes.NOT_FOUND });
      return;
    }
    this.logger.info(
      {
        event: 'check_presence',
        phase: 'response',
        result: 'accepted',
        socketId: client.id,
        playerId: dto.playerId,
        roomCode: result.room.code,
      },
      'check_presence: response (accepted)',
    );

    this.roomsService.reconnect(dto.roomCode, dto.playerId, client.id);
    // Reconnected in time — cancel any pending active-turn skip scheduled by
    // the old socket's disconnect (see ACTIVE_TURN_DISCONNECT_GRACE_MS).
    this._clearDisconnectedTurnTimer(dto.roomCode);
    this.send(
      client,
      'room_update',
      this.roomSnapshot(result.room, dto.playerId),
    );
    this.broadcastRoom(
      result.room.code,
      'room_update',
      this.roomSnapshot(result.room),
    );

    const session = this.gameService.getSessionByRoomCode(dto.roomCode);
    if (session) {
      this.gameService.updatePlayerConnection(dto.roomCode, dto.playerId, true);
      // Personalized to every socket in the room (Phase 7 audit) — the
      // previous non-personalized broadcastRoom call here had NO
      // localPlayerId, so it blanked every OTHER player's own private
      // fields (myAbility, the active selecting_card player's candidate
      // pool, scoringPreview) on every single reconnect in the room, not
      // just this one. check_presence fires far more often than kick/leave
      // (every refresh, every brief network drop), making this the most
      // frequently-triggered instance of the bug class fixed elsewhere in
      // Phase 3. This one call also correctly covers the reconnecting
      // client's own socket (already re-associated with this room/player
      // by roomsService.reconnect above), so the separate explicit send
      // this replaced is no longer needed.
      this._broadcastGameStateToRoom(
        session,
        result.room.code,
        this.roomsService.getSocketIds(result.room.code),
      );
      this._resendPhasePrompt(client, session, dto.playerId);
      // Tournament in progress → resync the reconnecting player's tournament UI.
      if (session.status === 'tournament' && session.tournament) {
        this.sendToSocket(
          client.id,
          'tournament_state',
          this.buildTournamentStatePayload(session.tournament),
        );
      }
    }
  }

  // ── Spectators ─────────────────────────────────────────────────────────────
  // Deliberately never touch GameService here — a spectator has no session
  // membership to update, no turn to skip, no pitch to build. Their socket
  // is tracked in RoomsService.spectatorSocketIndex, a SEPARATE map from the
  // socketIndex every gameplay handler's getSocketEntry() guard reads, so a
  // spectator's socket is structurally incapable of reaching any gameplay
  // @SubscribeMessage handler — those all fail their existing
  // `if (!entry) { NOT_IN_ROOM }` check automatically, with no new guard
  // needed on any of them.

  @SubscribeMessage('spectate_room')
  handleSpectateRoom(
    @MessageBody() dto: SpectateRoomDto,
    @ConnectedSocket() client: WebSocket & { id: string },
  ): void {
    const result = this.roomsService.spectateRoom(
      dto.roomCode,
      dto.displayName,
      client.id,
    );
    if ('error' in result) {
      this.send(client, 'error', { code: result.error });
      return;
    }

    this.send(client, 'room_update', {
      ...this.roomSnapshot(result.room, undefined, result.spectatorId),
      reconnectToken: generateReconnectToken(
        result.spectatorId,
        result.room.code,
      ),
    });
    this.broadcastRoom(
      result.room.code,
      'room_update',
      this.roomSnapshot(result.room),
    );

    // A game may already be in progress — send the current (no-local-player,
    // so no private per-player data) view immediately, same "no localPlayerId"
    // treatment the shared room broadcast above already gets.
    const session = this.gameService.getSessionByRoomCode(dto.roomCode);
    if (session) {
      this.send(client, 'game_state', this.gameSnapshot(session));
    }
  }

  @SubscribeMessage('stop_spectating')
  handleStopSpectating(
    @ConnectedSocket() client: WebSocket & { id: string },
  ): void {
    const result = this.roomsService.stopSpectating(client.id);
    if (!result) return;
    this.broadcastRoom(
      result.roomCode,
      'room_update',
      this.roomSnapshot(result.room),
    );
  }

  @SubscribeMessage('spectator_reconnect')
  @Throttle({ default: { limit: 10, ttl: seconds(30) } })
  handleSpectatorReconnect(
    @MessageBody() dto: SpectatorReconnectDto,
    @ConnectedSocket() client: WebSocket & { id: string },
  ): void {
    this.logger.info(
      {
        event: 'spectator_reconnect',
        phase: 'request',
        socketId: client.id,
        spectatorId: dto.spectatorId,
        roomCode: dto.roomCode,
      },
      'spectator_reconnect: request',
    );
    if (
      !verifyReconnectToken(dto.reconnectToken, dto.spectatorId, dto.roomCode)
    ) {
      this.logger.info(
        {
          event: 'spectator_reconnect',
          phase: 'response',
          result: 'rejected',
          reason: 'invalid_token',
          socketId: client.id,
          spectatorId: dto.spectatorId,
          roomCode: dto.roomCode,
        },
        'spectator_reconnect: response (rejected — invalid token)',
      );
      this.send(client, 'error', { code: ErrorCodes.INVALID_TOKEN });
      return;
    }
    const result = this.roomsService.reconnectSpectator(
      dto.roomCode,
      dto.spectatorId,
      client.id,
    );
    // Normalized to NOT_FOUND regardless of which of reconnectSpectator's
    // internal reasons (room gone vs. spectator id gone) applied — mirrors
    // handleCheckPresence's identical treatment of its own "not found"
    // cases above. The client's RoomNotifier only recognizes NOT_FOUND and
    // INVALID_TOKEN as "this reconnect attempt definitively failed, clear
    // the presence" signals; forwarding ROOM_NOT_FOUND/PLAYER_NOT_FOUND
    // verbatim silently fell through as an unrecognized error and left a
    // stale spectator seat cached forever.
    if ('error' in result) {
      this.logger.info(
        {
          event: 'spectator_reconnect',
          phase: 'response',
          result: 'rejected',
          reason: result.error,
          socketId: client.id,
          spectatorId: dto.spectatorId,
          roomCode: dto.roomCode,
        },
        'spectator_reconnect: response (rejected)',
      );
      this.send(client, 'error', { code: ErrorCodes.NOT_FOUND });
      return;
    }
    this.logger.info(
      {
        event: 'spectator_reconnect',
        phase: 'response',
        result: 'accepted',
        socketId: client.id,
        spectatorId: dto.spectatorId,
        roomCode: result.room.code,
      },
      'spectator_reconnect: response (accepted)',
    );

    this.send(
      client,
      'room_update',
      this.roomSnapshot(result.room, undefined, dto.spectatorId),
    );
    this.broadcastRoom(
      result.room.code,
      'room_update',
      this.roomSnapshot(result.room),
    );

    const session = this.gameService.getSessionByRoomCode(dto.roomCode);
    if (session) {
      this.send(client, 'game_state', this.gameSnapshot(session));
    }
  }

  // ── End-of-game helper ─────────────────────────────────────────────────────

  private _tryEndGame(roomCode: string): boolean {
    const session = this.gameService.getSessionByRoomCode(roomCode);
    if (!session) return false;
    if (session.players.length >= MIN_ACTIVE_PLAYERS) return false;

    // Phase 7 audit: once a tournament actually begins, the bracket
    // (session.tournament) is a self-sufficient, frozen structure — every
    // match is pre-simulated server-side and AI fills any bracket slot a
    // real player doesn't occupy, so a single remaining real participant
    // can keep going through their matches alone. Declaring a "forfeit
    // win" here (a concept built for the pre-tournament single-match flow)
    // would prematurely end the entire multi-round bracket the moment a
    // room drops to 1 player, discarding AI matches already simulated or
    // in progress. A genuinely EMPTY room (0 players) still needs cleanup
    // below — nobody's left to watch it either way.
    if (session.status === 'tournament' && session.players.length >= 1) {
      return false;
    }

    if (session.players.length === 1) {
      this.gameService.declareForfeitWin(session, session.players[0].id);
    } else {
      session.isFinished = true;
      session.status = 'finished';
      session.result = { reason: 'abandoned', players: [] };
    }

    const socketIds = this.roomsService.getSocketIds(roomCode);
    for (const id of socketIds) {
      const c = this._connectedSockets.get(id);
      if (!c) continue;
      const player = session.players.find(
        (p) => p.id === this.roomsService.getSocketEntry(id)?.playerId,
      );
      this.send(c, 'game_state', this.gameSnapshot(session, player?.id));
    }

    this._clearAllTimersForSession(roomCode, session.sessionId);
    this.gameService.endSession(roomCode);
    this.roomsService.closeRoom(roomCode);
    return true;
  }

  // ── Game events ────────────────────────────────────────────────────────────

  @SubscribeMessage('start_game')
  handleStartGame(@ConnectedSocket() client: WebSocket & { id: string }): void {
    const startResult = this.roomsService.startGame(client.id);
    if ('error' in startResult) {
      this.send(client, 'error', { code: startResult.error });
      return;
    }

    const session = this.gameService.createSession(startResult.room);
    const socketIds = this.roomsService.getSocketIds(startResult.roomCode);

    for (const id of socketIds) {
      const c = this._connectedSockets.get(id);
      if (!c) continue;
      const player = startResult.room.players.find((p) => p.socketId === id);
      this.send(c, 'game_state', this.gameSnapshot(session, player?.id));
    }

    // Exactly one of these applies depending on whether the room has any
    // enabled abilities (_scheduleTurnTimer no-ops outside 'drafting',
    // _scheduleAbilityDraftTimer no-ops outside 'ability_draft' — harmless to
    // call both).
    this._scheduleTurnTimer(session, startResult.roomCode);
    this._scheduleAbilityDraftTimer(session, startResult.roomCode);
  }

  @SubscribeMessage('pick_ability')
  handlePickAbility(
    @MessageBody() dto: PickAbilityDto,
    @ConnectedSocket() client: WebSocket & { id: string },
  ): void {
    const entry = this.roomsService.getSocketEntry(client.id);
    if (!entry) {
      this.send(client, 'error', { code: ErrorCodes.NOT_IN_ROOM });
      return;
    }
    // Any recognized gameplay action counts as room activity, so a slow-but-
    // alive game is never swept by the stale-room cleanup (see _cleanStaleRooms).
    this.roomsService.touchRoomActivity(entry.roomCode);

    const result = this.gameService.pickAbilityCard(
      entry.roomCode,
      entry.playerId,
      dto.cardId,
    );
    if ('error' in result) {
      this.send(client, 'error', { code: result.error });
      return;
    }

    this._afterAbilityPick(result, entry.roomCode);
  }

  /**
   * Shared tail for both a manual `pick_ability` and the auto-pick timeout
   * (`_autoPickAbilityDraft`) — broadcasts the result and either re-arms the
   * draft timer for the next picker, or (on the final pick) holds the reveal
   * window and starts the player draft. Kept in one place so the two trigger
   * paths can't drift out of sync with each other.
   */
  private _afterAbilityPick(
    result: { session: GameSession; allPicked: boolean },
    roomCode: string,
  ): void {
    const broadcast = (session: GameSession) => {
      const socketIds = this.roomsService.getSocketIds(roomCode);
      for (const id of socketIds) {
        const c = this._connectedSockets.get(id);
        if (!c) continue;
        const roomEntry = this.roomsService.getSocketEntry(id);
        this.send(
          c,
          'game_state',
          this.gameSnapshot(session, roomEntry?.playerId),
        );
      }
    };

    broadcast(result.session);

    // After the final pick, hold a short reveal window so the last picker can
    // see their card, THEN start the player draft and arm the first turn-timer.
    if (result.allPicked) {
      this._clearAbilityDraftTimer(result.session.sessionId);
      this._clearAbilityRevealTimer(roomCode);
      const tid = setTimeout(() => {
        this._abilityRevealTimers.delete(roomCode);
        const r2 = this.gameService.beginPlayerDraft(roomCode);
        if ('error' in r2) return;
        broadcast(r2.session);
        this._scheduleTurnTimer(r2.session, roomCode);
      }, 3500);
      this._abilityRevealTimers.set(roomCode, tid);
    } else {
      // Still picks remaining — arm a fresh timer for the next picker.
      this._scheduleAbilityDraftTimer(result.session, roomCode);
    }
  }

  @SubscribeMessage('activate_ability')
  handleActivateAbility(
    @MessageBody()
    dto: ActivateAbilityDto,
    @ConnectedSocket() client: WebSocket & { id: string },
  ): void {
    const entry = this.roomsService.getSocketEntry(client.id);
    if (!entry) {
      this.send(client, 'error', { code: ErrorCodes.NOT_IN_ROOM });
      return;
    }
    // Any recognized gameplay action counts as room activity, so a slow-but-
    // alive game is never swept by the stale-room cleanup (see _cleanStaleRooms).
    this.roomsService.touchRoomActivity(entry.roomCode);

    const result = this.gameService.activateAbility(
      entry.roomCode,
      entry.playerId,
      dto,
    );
    if ('error' in result) {
      this.send(client, 'error', { code: result.error });
      return;
    }

    this._afterAbilityActivation(result, entry.roomCode);
  }

  @SubscribeMessage('discard_ability')
  handleDiscardAbility(
    @ConnectedSocket() client: WebSocket & { id: string },
  ): void {
    const entry = this.roomsService.getSocketEntry(client.id);
    if (!entry) {
      this.send(client, 'error', { code: ErrorCodes.NOT_IN_ROOM });
      return;
    }
    // Any recognized gameplay action counts as room activity, so a slow-but-
    // alive game is never swept by the stale-room cleanup (see _cleanStaleRooms).
    this.roomsService.touchRoomActivity(entry.roomCode);

    const result = this.gameService.discardAbility(
      entry.roomCode,
      entry.playerId,
    );
    if ('error' in result) {
      this.send(client, 'error', { code: result.error });
      return;
    }

    this._afterAbilityActivation(result, entry.roomCode);
  }

  /**
   * Shared tail for `activate_ability`/`discard_ability` — mirrors
   * `_afterAbilityPick` one phase later. Broadcasts the commit itself (safe:
   * the committing player's own choice is only ever visible to them via
   * `myAbility`, and nothing about OTHER players' choices is populated yet —
   * see `activateAbility`'s doc comment). Once every player has committed,
   * reveals all abilities at once, broadcasts that, then holds a short
   * window before actually advancing to subs so the reveal is visible rather
   * than flashing by.
   */
  private _afterAbilityActivation(
    result: { session: GameSession; allResolved: boolean },
    roomCode: string,
  ): void {
    this._broadcastGameStateToRoom(
      result.session,
      roomCode,
      this.roomsService.getSocketIds(roomCode),
    );
    if (!result.allResolved) return;

    // Nothing left for the auto-discard deadline to force — stop it so it
    // can't race the reveal we're about to do.
    this._clearAbilityActivationTimer(result.session.sessionId);

    const revealResult = this.gameService.revealAbilityActivations(roomCode);
    if ('error' in revealResult) return;
    this._broadcastGameStateToRoom(
      revealResult.session,
      roomCode,
      this.roomsService.getSocketIds(roomCode),
    );

    this._clearAbilityActivationRevealTimer(roomCode);
    const tid = setTimeout(() => {
      this._abilityActivationRevealTimers.delete(roomCode);
      const finishResult = this.gameService.finishAbilityActivation(roomCode);
      if ('error' in finishResult) return;
      this._broadcastGameStateToRoom(
        finishResult.session,
        roomCode,
        this.roomsService.getSocketIds(roomCode),
      );
    }, 3500);
    this._abilityActivationRevealTimers.set(roomCode, tid);
  }

  @SubscribeMessage('pick_slot')
  handlePickSlot(
    @MessageBody() dto: PickSlotDto,
    @ConnectedSocket() client: WebSocket & { id: string },
  ): void {
    const entry = this.roomsService.getSocketEntry(client.id);
    if (!entry) {
      this.send(client, 'error', { code: ErrorCodes.NOT_IN_ROOM });
      return;
    }
    // Any recognized gameplay action counts as room activity, so a slow-but-
    // alive game is never swept by the stale-room cleanup (see _cleanStaleRooms).
    this.roomsService.touchRoomActivity(entry.roomCode);

    const result = this.gameService.pickSlot(
      entry.roomCode,
      entry.playerId,
      dto.turnId,
      dto.slotIndex,
    );
    if ('error' in result) {
      this.send(client, 'error', { code: result.error });
      return;
    }

    const { session, candidates } = result;

    const socketIds = this.roomsService.getSocketIds(entry.roomCode);
    for (const id of socketIds) {
      const c = this._connectedSockets.get(id);
      if (!c) continue;
      const roomEntry = this.roomsService.getSocketEntry(id);
      this.send(
        c,
        'game_state',
        this.gameSnapshot(session, roomEntry?.playerId),
      );
    }

    // Send full candidates only to the first player (selecting_card)
    this.send(client, 'slot_candidates', {
      turnId: session.turn.turnId,
      candidates,
    });

    this._scheduleTurnTimer(session, entry.roomCode);
  }

  @SubscribeMessage('pick_card')
  handlePickCard(
    @MessageBody() dto: PickCardDto,
    @ConnectedSocket() client: WebSocket & { id: string },
  ): void {
    const entry = this.roomsService.getSocketEntry(client.id);
    if (!entry) {
      this.send(client, 'error', { code: ErrorCodes.NOT_IN_ROOM });
      return;
    }
    // Any recognized gameplay action counts as room activity, so a slow-but-
    // alive game is never swept by the stale-room cleanup (see _cleanStaleRooms).
    this.roomsService.touchRoomActivity(entry.roomCode);

    const result = this.gameService.pickCard(
      entry.roomCode,
      entry.playerId,
      dto.turnId,
      dto.cardId,
    );
    if ('error' in result) {
      this.send(client, 'error', { code: result.error });
      return;
    }

    const { session, orderPromptCards } = result;

    // Broadcast sanitized game_state to all players
    const socketIds = this.roomsService.getSocketIds(entry.roomCode);
    for (const id of socketIds) {
      const c = this._connectedSockets.get(id);
      if (!c) continue;
      const roomEntry = this.roomsService.getSocketEntry(id);
      this.send(
        c,
        'game_state',
        this.gameSnapshot(session, roomEntry?.playerId),
      );
    }

    // Multi-player: send order prompt to the first player
    if (orderPromptCards !== null) {
      this.send(client, 'first_player_order_prompt', {
        turnId: session.turn.turnId,
        cards: orderPromptCards,
      });
    }

    this._maybeArmSubsTimer(session, entry.roomCode);
    this._maybeArmAbilityActivationTimer(session, entry.roomCode);
    this._scheduleTurnTimer(session, entry.roomCode);
  }

  @SubscribeMessage('order_hidden_deck')
  handleOrderHiddenDeck(
    @MessageBody() dto: OrderHiddenDeckDto,
    @ConnectedSocket() client: WebSocket & { id: string },
  ): void {
    const entry = this.roomsService.getSocketEntry(client.id);
    if (!entry) {
      this.send(client, 'error', { code: ErrorCodes.NOT_IN_ROOM });
      return;
    }
    // Any recognized gameplay action counts as room activity, so a slow-but-
    // alive game is never swept by the stale-room cleanup (see _cleanStaleRooms).
    this.roomsService.touchRoomActivity(entry.roomCode);

    const result = this.gameService.orderHiddenDeck(
      entry.roomCode,
      entry.playerId,
      dto.turnId,
      dto.orderedCardIds,
    );
    if ('error' in result) {
      this.send(client, 'error', { code: result.error });
      return;
    }

    const { session, availableSlots } = result;

    // Broadcast sanitized game_state to all (phase = hidden_pick, no card data)
    const socketIds = this.roomsService.getSocketIds(entry.roomCode);
    for (const id of socketIds) {
      const c = this._connectedSockets.get(id);
      if (!c) continue;
      const roomEntry = this.roomsService.getSocketEntry(id);
      this.send(
        c,
        'game_state',
        this.gameSnapshot(session, roomEntry?.playerId),
      );
    }

    if (availableSlots !== undefined) {
      // Send hidden_pick_prompt only to the next active picker
      this.sendHiddenPickPromptToActivePlayer(
        session,
        entry.roomCode,
        availableSlots,
      );
      this._scheduleTurnTimer(session, entry.roomCode);
    } else {
      // undefined means this round's hidden-pick pool is exhausted and the
      // draft already wrapped to the next round (or finished) with no next
      // hidden picker to prompt. Mirrors confirmHiddenReveal's identical
      // branch.
      const freshSession = this.gameService.getSessionByRoomCode(
        entry.roomCode,
      );
      if (freshSession && !freshSession.isFinished) {
        this._scheduleTurnTimer(freshSession, entry.roomCode);
      }
    }

    // If skipping every disconnected player this round wrapped straight into
    // subs/ability_activation, arm the relevant timer (both no-op otherwise).
    this._maybeArmSubsTimer(session, entry.roomCode);
    this._maybeArmAbilityActivationTimer(session, entry.roomCode);
  }

  @SubscribeMessage('pick_hidden_slot')
  handlePickHiddenSlot(
    @MessageBody() dto: PickHiddenSlotDto,
    @ConnectedSocket() client: WebSocket & { id: string },
  ): void {
    const entry = this.roomsService.getSocketEntry(client.id);
    if (!entry) {
      this.send(client, 'error', { code: ErrorCodes.NOT_IN_ROOM });
      return;
    }
    // Any recognized gameplay action counts as room activity, so a slow-but-
    // alive game is never swept by the stale-room cleanup (see _cleanStaleRooms).
    this.roomsService.touchRoomActivity(entry.roomCode);

    const result = this.gameService.pickHiddenSlot(
      entry.roomCode,
      entry.playerId,
      dto.turnId,
      dto.slotIndex,
    );
    if ('error' in result) {
      this.send(client, 'error', { code: result.error });
      return;
    }

    const { session, revealedCard } = result;

    // Send card_revealed only to the picker (private flip animation).
    this.send(client, 'card_revealed', { card: revealedCard });

    // Broadcast hidden_pick_reveal game_state to all players.
    const socketIds = this.roomsService.getSocketIds(entry.roomCode);
    for (const id of socketIds) {
      const c = this._connectedSockets.get(id);
      if (!c) continue;
      const viewerId =
        id === client.id
          ? entry.playerId
          : this.roomsService.getSocketEntry(id)?.playerId;
      this.send(c, 'game_state', this.gameSnapshot(session, viewerId));
    }

    // Server auto-advances after 5 s if picker does not confirm first.
    this._scheduleHiddenRevealTimeout(entry.roomCode, session.turn.turnId);
    // Cancel any pending turn timer — we're now in the reveal phase.
    this._clearTurnTimer(session.sessionId);
  }

  @SubscribeMessage('confirm_hidden_reveal')
  handleConfirmHiddenReveal(
    @MessageBody() dto: ConfirmHiddenRevealDto,
    @ConnectedSocket() client: WebSocket & { id: string },
  ): void {
    const entry = this.roomsService.getSocketEntry(client.id);
    if (!entry) {
      this.send(client, 'error', { code: ErrorCodes.NOT_IN_ROOM });
      return;
    }
    // Any recognized gameplay action counts as room activity, so a slow-but-
    // alive game is never swept by the stale-room cleanup (see _cleanStaleRooms).
    this.roomsService.touchRoomActivity(entry.roomCode);

    this._clearHiddenRevealTimeout(entry.roomCode);
    this._doAdvanceFromReveal(entry.roomCode, dto.turnId, entry.playerId);
  }

  // ── Sub selection handlers ────────────────────────────────────────────────

  @SubscribeMessage('request_sub_spin')
  handleRequestSubSpin(
    @MessageBody() dto: RequestSubSpinDto,
    @ConnectedSocket() client: WebSocket & { id: string },
  ): void {
    const entry = this.roomsService.getSocketEntry(client.id);
    if (!entry) {
      this.send(client, 'error', { code: ErrorCodes.NOT_IN_ROOM });
      return;
    }
    // Any recognized gameplay action counts as room activity, so a slow-but-
    // alive game is never swept by the stale-room cleanup (see _cleanStaleRooms).
    this.roomsService.touchRoomActivity(entry.roomCode);

    const result = this.gameService.requestSubSpin(
      entry.roomCode,
      entry.playerId,
      dto.positionGroup,
    );
    if ('error' in result) {
      this.send(client, 'error', { code: result.error });
      return;
    }

    this.send(client, 'sub_spin_result', {
      positionGroup: dto.positionGroup,
      clubName: result.clubName,
      players: result.players,
    });
  }

  @SubscribeMessage('pick_sub')
  handlePickSub(
    @MessageBody() dto: PickSubDto,
    @ConnectedSocket() client: WebSocket & { id: string },
  ): void {
    const entry = this.roomsService.getSocketEntry(client.id);
    if (!entry) {
      this.send(client, 'error', { code: ErrorCodes.NOT_IN_ROOM });
      return;
    }
    // Any recognized gameplay action counts as room activity, so a slow-but-
    // alive game is never swept by the stale-room cleanup (see _cleanStaleRooms).
    this.roomsService.touchRoomActivity(entry.roomCode);

    const result = this.gameService.pickSub(
      entry.roomCode,
      entry.playerId,
      dto.positionGroup,
      dto.playerId,
    );
    if ('error' in result) {
      this.send(client, 'error', { code: result.error });
      return;
    }

    const { session } = result;
    const socketIds = this.roomsService.getSocketIds(entry.roomCode);
    this._broadcastGameStateToRoom(session, entry.roomCode, socketIds);
  }

  @SubscribeMessage('swap_sub')
  handleSwapSub(
    @MessageBody() dto: SwapSubDto,
    @ConnectedSocket() client: WebSocket & { id: string },
  ): void {
    const entry = this.roomsService.getSocketEntry(client.id);
    if (!entry) {
      this.send(client, 'error', { code: ErrorCodes.NOT_IN_ROOM });
      return;
    }
    // Any recognized gameplay action counts as room activity, so a slow-but-
    // alive game is never swept by the stale-room cleanup (see _cleanStaleRooms).
    this.roomsService.touchRoomActivity(entry.roomCode);

    const result = this.gameService.swapSub(
      entry.roomCode,
      entry.playerId,
      dto.positionGroup,
      dto.starterId,
    );
    if ('error' in result) {
      this.send(client, 'error', { code: result.error });
      return;
    }

    // Only send to the requesting player — subs are private
    this.send(
      client,
      'game_state',
      this.gameSnapshot(result.session, entry.playerId),
    );
  }

  @SubscribeMessage('swap_roster')
  handleSwapRoster(
    @MessageBody() dto: SwapRosterDto,
    @ConnectedSocket() client: WebSocket & { id: string },
  ): void {
    const entry = this.roomsService.getSocketEntry(client.id);
    if (!entry) {
      this.send(client, 'error', { code: ErrorCodes.NOT_IN_ROOM });
      return;
    }
    // Any recognized gameplay action counts as room activity, so a slow-but-
    // alive game is never swept by the stale-room cleanup (see _cleanStaleRooms).
    this.roomsService.touchRoomActivity(entry.roomCode);

    // RosterEndpointDto's `kind`/`index`/`group` shape is validated at runtime
    // by @ValidateIf (see swap-roster.dto.ts) — the discriminated narrowing
    // itself isn't expressible in class-validator, so this cast is safe given
    // that validation already ran before the handler executes.
    const result = this.gameService.swapRoster(
      entry.roomCode,
      entry.playerId,
      dto.a as RosterEndpoint,
      dto.b as RosterEndpoint,
    );
    if ('error' in result) {
      this.send(client, 'error', { code: result.error });
      return;
    }

    // Only send to the requesting player — the lineup is private during subs.
    this.send(
      client,
      'game_state',
      this.gameSnapshot(result.session, entry.playerId),
    );
  }

  @SubscribeMessage('confirm_lineup')
  handleConfirmLineup(
    @ConnectedSocket() client: WebSocket & { id: string },
  ): void {
    const entry = this.roomsService.getSocketEntry(client.id);
    if (!entry) {
      this.send(client, 'error', { code: ErrorCodes.NOT_IN_ROOM });
      return;
    }
    // Any recognized gameplay action counts as room activity, so a slow-but-
    // alive game is never swept by the stale-room cleanup (see _cleanStaleRooms).
    this.roomsService.touchRoomActivity(entry.roomCode);

    const result = this.gameService.confirmLineup(
      entry.roomCode,
      entry.playerId,
    );
    if ('error' in result) {
      this.send(client, 'error', { code: result.error });
      return;
    }

    // Broadcast to all — opponent needs to see confirmation status. Done
    // BEFORE the tournament fork below: beginBracketReveal's own broadcast
    // is a separate 'tournament_state' event clients only use for
    // navigation, so if it's delayed/dropped a client still on the
    // lineup_edit screen would otherwise be working off a stale
    // lineupConfirmed and could still interact with (already-locked) UI.
    const { session } = result;
    const socketIds = this.roomsService.getSocketIds(entry.roomCode);
    this._broadcastGameStateToRoom(session, entry.roomCode, socketIds);

    // Tournament fork: lineup_edit complete in a tournament-enabled session
    // → start the bracket reveal instead of finalizing the draft.
    if ('tournamentStarting' in result && result.tournamentStarting) {
      this.beginBracketReveal(entry.roomCode);
    }
  }

  // ── Hidden-reveal timeout helpers ─────────────────────────────────────────

  private _scheduleHiddenRevealTimeout(roomCode: string, turnId: string): void {
    this._clearHiddenRevealTimeout(roomCode);
    const tid = setTimeout(() => {
      this.hiddenRevealTimeouts.delete(roomCode);
      this._doAdvanceFromReveal(roomCode, turnId, undefined);
    }, 5000);
    this.hiddenRevealTimeouts.set(roomCode, tid);
  }

  private _clearHiddenRevealTimeout(roomCode: string): void {
    const tid = this.hiddenRevealTimeouts.get(roomCode);
    if (tid !== undefined) {
      clearTimeout(tid);
      this.hiddenRevealTimeouts.delete(roomCode);
    }
  }

  private _doAdvanceFromReveal(
    roomCode: string,
    turnId: string,
    senderId: string | undefined,
  ): void {
    const result = this.gameService.confirmHiddenReveal(
      roomCode,
      turnId,
      senderId,
    );
    if ('error' in result) return;

    const { session, nextAvailableSlots } = result;
    const socketIds = this.roomsService.getSocketIds(roomCode);
    for (const id of socketIds) {
      const c = this._connectedSockets.get(id);
      if (!c) continue;
      const roomEntry = this.roomsService.getSocketEntry(id);
      this.send(
        c,
        'game_state',
        this.gameSnapshot(session, roomEntry?.playerId),
      );
    }

    if (nextAvailableSlots !== undefined) {
      this.sendHiddenPickPromptToActivePlayer(
        session,
        roomCode,
        nextAvailableSlots,
      );
      this._scheduleTurnTimer(session, roomCode);
    } else {
      // Round or game ended — no more turn timer needed.
      const freshSession = this.gameService.getSessionByRoomCode(roomCode);
      if (freshSession && !freshSession.isFinished) {
        this._scheduleTurnTimer(freshSession, roomCode);
      }
    }

    // If this advance transitioned the game into the subs phase, arm its timer.
    this._maybeArmSubsTimer(session, roomCode);
    // ...or into ability_activation (the multiplayer round-wrap path can land
    // there directly without an intervening pick_card/activate_ability call).
    this._maybeArmAbilityActivationTimer(session, roomCode);
  }

  // ── Disconnect: crash / refresh / network drop ─────────────────────────────

  handleDisconnect(client: WebSocket & { id: string }): void {
    // Unconditional — a socket that connected but never joined any room
    // still needs removing from _connectedSockets (Task 2.1), otherwise it
    // leaks forever (the `if (!entry) return;` below would skip it).
    this._connectedSockets.delete(client.id);
    const entry = this.roomsService.getSocketEntry(client.id);
    this.logger.info(
      {
        event: 'socket_closed',
        socketId: client.id,
        roomCode: entry?.roomCode ?? null,
        playerId: entry?.playerId ?? null,
      },
      'socket closed',
    );
    if (!entry) {
      // Not a player socket — check whether it was a spectator's instead.
      // Separate index, separate handling: no GameSession, no turn to skip.
      this._handleSpectatorDisconnect(client.id);
      return;
    }

    const hasActiveSession = !!this.gameService.getSessionByRoomCode(
      entry.roomCode,
    );

    // If the disconnecting player was mid-reveal, cancel the timeout so we
    // don't fire against a session that may have already advanced via removePlayer.
    if (hasActiveSession) this._clearHiddenRevealTimeout(entry.roomCode);

    const result = this.roomsService.handleDisconnect(
      client.id,
      hasActiveSession,
    );
    if (!result) return;

    if (result.room) {
      this.broadcastRoom(
        result.roomCode,
        'room_update',
        this.roomSnapshot(result.room),
      );
    } else if (hasActiveSession) {
      // CRITICAL (found in Phase 0 production-safety review): the room was
      // just fully deleted — this was its last connected player — while a
      // game session still existed for it. roomsService already removed the
      // room itself, but the GameSession lives in a SEPARATE map (gameService)
      // that nothing else points at it anymore: _cleanStaleRooms can never
      // find it (it only scans roomsService's rooms, which no longer has this
      // one), so without this the session — and any timer still armed for it —
      // would live and keep firing FOREVER, silently auto-advancing an
      // abandoned game in the background with no one able to stop it.
      const orphaned = this.gameService.getSessionByRoomCode(result.roomCode);
      this._clearAllTimersForSession(result.roomCode, orphaned?.sessionId);
      this.gameService.endSession(result.roomCode);
      return; // No room, no session, no one left to notify.
    }

    if (hasActiveSession) {
      this.gameService.updatePlayerConnection(
        result.roomCode,
        result.playerId,
        false,
      );

      // If the disconnecting player was the CURRENT active turn holder
      // during drafting, the room shouldn't be stuck forever waiting on a
      // socket that's genuinely gone. But this fires on EVERY disconnect,
      // including the old socket closing at the start of an ordinary
      // refresh/reconnect — so the actual auto-pick is delayed by a grace
      // period (see ACTIVE_TURN_DISCONNECT_GRACE_MS) rather than applied
      // instantly, giving a normal reconnect time to land first.
      this._scheduleDisconnectedTurnResolution(result.roomCode, result.playerId);

      const session = this.gameService.getSessionByRoomCode(result.roomCode);
      if (session) {
        // Personalized per socket (not broadcastRoom) — a non-personalized
        // snapshot has no localPlayerId, so it would transiently blank every
        // recipient's own private fields (myAbility, the active selecting_card
        // player's candidate pool, scoringPreview) on every single disconnect
        // during an active game, not just kick/leave. See the identical fix
        // in handleKickPlayer/handleLeaveGamePermanently and _scheduleDisconnectedTurnResolution.
        this._broadcastGameStateToRoom(
          session,
          result.roomCode,
          this.roomsService.getSocketIds(result.roomCode),
        );
      }
    }
  }

  /**
   * Delays auto-picking for a disconnected active player by
   * ACTIVE_TURN_DISCONNECT_GRACE_MS — see that constant's docstring for why
   * an immediate auto-pick would punish a normal refresh. Cancelled by
   * _clearDisconnectedTurnTimer the moment this room's player successfully
   * reconnects (handleCheckPresence). Re-reads both the room and the session
   * fresh at fire time rather than trusting anything captured at schedule
   * time: the player may have reconnected, or the turn may have moved on for
   * an unrelated reason, any time during the grace window.
   *
   * Only schedules when `playerId` is actually the current active turn
   * holder — this timer is keyed by roomCode alone (only one active player
   * can hold a room's turn at a time), so scheduling unconditionally on
   * every disconnect would let an unrelated, non-active player's disconnect
   * overwrite (and effectively restart the clock on, or misdirect at the
   * wrong playerId) a genuinely-pending resolution for whoever actually
   * holds the turn.
   *
   * Also called from `_scheduleTurnTimer` itself whenever a turn transition
   * hands the turn to a player who's ALREADY disconnected (not just one who
   * disconnects mid-turn) — same grace window, same auto-pick outcome, one
   * mechanism for both cases. See `_scheduleTurnTimer`'s own comment.
   */
  private _scheduleDisconnectedTurnResolution(roomCode: string, playerId: string): void {
    const session = this.gameService.getSessionByRoomCode(roomCode);
    if (!session || session.turn.activePlayerId !== playerId) return;

    this._clearDisconnectedTurnTimer(roomCode);
    const tid = setTimeout(() => {
      this._disconnectedTurnTimers.delete(roomCode);

      const room = this.roomsService.getRoom(roomCode);
      const player = room?.players.find((p) => p.id === playerId);
      // Reconnected within the grace window — the turn they'd otherwise be
      // auto-picked out of is exactly the one they refreshed to keep.
      if (player?.isConnected) return;

      this._autoPickForDisconnectedPlayer(roomCode, playerId);
    }, ACTIVE_TURN_DISCONNECT_GRACE_MS);
    this._disconnectedTurnTimers.set(roomCode, tid);
  }

  /**
   * Auto-picks on behalf of a player who's still in the room but has been
   * disconnected past the grace window — reuses `_autoPickCurrentPhase`,
   * the exact same logic a connected-but-slow player's full `turnSeconds`
   * timeout already uses, so a temporary disconnect produces the identical
   * outcome a slow-but-connected player would: a real pick gets made, the
   * room keeps moving, and (unlike the old skip-based design) the
   * disconnected player still ends this round with a card like everyone
   * else. Re-validates against the LIVE session rather than anything
   * captured earlier — the turn may have already moved on for an unrelated
   * reason (e.g. everyone else already finished the round) by the time this
   * runs.
   */
  private _autoPickForDisconnectedPlayer(roomCode: string, playerId: string): void {
    const session = this.gameService.getSessionByRoomCode(roomCode);
    if (!session) return;
    if (session.status !== 'drafting') return;
    if (session.turn.activePlayerId !== playerId) return;
    // hidden_pick_reveal already self-heals via its own 5s auto-advance
    // timeout regardless of connection state — nothing to do here.
    if (session.turn.phase === 'hidden_pick_reveal') return;
    this._autoPickCurrentPhase(session, roomCode);
  }

  private _clearDisconnectedTurnTimer(roomCode: string): void {
    const tid = this._disconnectedTurnTimers.get(roomCode);
    if (tid !== undefined) {
      clearTimeout(tid);
      this._disconnectedTurnTimers.delete(roomCode);
    }
  }

  private _handleSpectatorDisconnect(socketId: string): void {
    const result = this.roomsService.handleSpectatorDisconnect(socketId);
    if (!result) return;
    this.broadcastRoom(
      result.roomCode,
      'room_update',
      this.roomSnapshot(result.room),
    );
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /**
   * On reconnect, re-sends the phase-specific prompt to the reconnected player
   * if they are the current active player and a prompt is pending.
   */
  private _resendPhasePrompt(
    client: WebSocket,
    session: GameSession,
    playerId: string,
  ): void {
    if (session.turn.activePlayerId !== playerId) return;

    if (session.turn.phase === 'first_player_order') {
      this.send(client, 'first_player_order_prompt', {
        turnId: session.turn.turnId,
        cards: session.roundCandidates,
      });
      return;
    }

    if (session.turn.phase === 'hidden_pick') {
      const availableSlots =
        this.gameService.computeAvailableHiddenSlots(session);
      this.send(client, 'hidden_pick_prompt', {
        turnId: session.turn.turnId,
        totalSlots: session.orderedHiddenDeck.length,
        availableSlots,
        previewCards: this._previewCardsFor(session),
      });
    }
  }

  // ── Per-turn timer ────────────────────────────────────────────────────────

  private _clearTurnTimer(sessionId: string): void {
    const t = this._turnTimers.get(sessionId);
    if (t !== undefined) {
      clearTimeout(t);
      this._turnTimers.delete(sessionId);
    }
  }

  private _scheduleTurnTimer(session: GameSession, roomCode: string): void {
    if (session.isFinished) return;
    // The draft turn-timer only applies while drafting players — never during
    // the ability draft/activation phases (those have no per-turn auto-pick).
    if (session.status !== 'drafting') return;

    this._clearTurnTimer(session.sessionId);

    // Turn order is connection-agnostic (see game.service.ts's block comment
    // above _nextIndexInRound) — a disconnected-but-still-in-room player can
    // legitimately be the active player. There's no real per-turn countdown
    // to arm for them (they can't act), so hand off to the disconnect-grace
    // + auto-pick mechanism instead of the normal turnSeconds timer below.
    // This check runs BEFORE the turnTimeoutPolicy gate deliberately — the
    // disconnect/auto-pick guarantee applies even when the host has turn
    // timers disabled entirely (turnSeconds is a "how long to wait for a
    // CONNECTED player" setting, not a prerequisite for this).
    const activePlayer = session.players.find(
      (p) => p.id === session.turn.activePlayerId,
    );
    if (activePlayer && !activePlayer.isConnected) {
      this._scheduleDisconnectedTurnResolution(roomCode, activePlayer.id);
      return;
    }

    const policy = session.turnTimeoutPolicy;
    this.logger.debug(
      {
        event: 'turn_timer_scheduled',
        roomCode,
        enabled: policy.enabled,
        turnSeconds: policy.turnSeconds,
        phase: session.turn.phase,
      },
      'Turn timer scheduled',
    );
    if (!policy.enabled || !policy.turnSeconds) return;

    // Stamp the start time on the session BEFORE re-broadcasting game_state,
    // so clients receive the timer data embedded in the snapshot.
    // (The initial game_state broadcast happens before _scheduleTurnTimer runs,
    // so turnStartedAt would be null in that first snapshot without this re-broadcast.)
    session.turn.turnStartedAt = Date.now();

    const socketIds = this.roomsService.getSocketIds(roomCode);

    // Re-broadcast game_state now that turnStartedAt is set.
    this._broadcastGameStateToRoom(session, roomCode, socketIds);

    // Also emit the legacy turn_timer_start event for clients already subscribed.
    this.broadcastToSockets(socketIds, 'turn_timer_start', {
      turnId: session.turn.turnId,
      turnDurationSeconds: policy.turnSeconds,
      activePlayerId: session.turn.activePlayerId,
      startedAtMs: session.turn.turnStartedAt,
    });

    const { sessionId } = session;
    const capturedTurnId = session.turn.turnId;
    const delayMs = policy.turnSeconds! * 1000;

    const t = setTimeout(() => {
      this._turnTimers.delete(sessionId);
      const current = this.gameService.getSessionByRoomCode(roomCode);
      if (
        !current ||
        current.turn.turnId !== capturedTurnId ||
        current.isFinished
      )
        return;
      this._autoPickCurrentPhase(current, roomCode);
    }, delayMs);

    this._turnTimers.set(sessionId, t);
  }

  private _autoPickCurrentPhase(session: GameSession, roomCode: string): void {
    const phase = session.turn.phase;
    const playerId = session.turn.activePlayerId;
    const socketIds = this.roomsService.getSocketIds(roomCode);

    // Notify all players that a move was auto-picked.
    this.broadcastToSockets(socketIds, 'turn_auto_picked', {
      playerId,
      reason: 'timeout',
    });

    if (phase === 'selecting_position') {
      const pitch = session.pitches[playerId];
      if (!pitch) return;
      const emptySlot = pitch.slots.find((s) => s.card === null);
      if (!emptySlot) return;

      const slotResult = this.gameService.pickSlot(
        roomCode,
        playerId,
        session.turn.turnId,
        emptySlot.index,
      );
      if ('error' in slotResult) return;

      const { session: s1, candidates } = slotResult;
      this._broadcastGameStateToRoom(s1, roomCode, socketIds);

      if (!candidates.length) return;
      const cardResult = this.gameService.pickCard(
        roomCode,
        playerId,
        s1.turn.turnId,
        candidates[0].cardId,
      );
      if ('error' in cardResult) return;

      const { session: s2, orderPromptCards } = cardResult;
      this._broadcastGameStateToRoom(s2, roomCode, socketIds);

      if (orderPromptCards !== null) {
        const orderedIds = s2.roundCandidates.map((c) => c.cardId);
        const orderResult = this.gameService.orderHiddenDeck(
          roomCode,
          playerId,
          s2.turn.turnId,
          orderedIds,
        );
        if ('error' in orderResult) return;
        const { session: s3, availableSlots } = orderResult;
        this._broadcastGameStateToRoom(s3, roomCode, socketIds);
        // availableSlots is undefined when this round's hidden-pick pool is
        // exhausted and the draft already wrapped past hidden-pick, so
        // there's no next picker to prompt.
        if (availableSlots !== undefined) {
          this.sendHiddenPickPromptToActivePlayer(s3, roomCode, availableSlots);
        }
        this._scheduleTurnTimer(s3, roomCode);
        this._maybeArmSubsTimer(s3, roomCode);
        this._maybeArmAbilityActivationTimer(s3, roomCode);
      } else {
        this._scheduleTurnTimer(s2, roomCode);
      }
      return;
    }

    if (phase === 'selecting_card') {
      const candidate = session.turn.candidates[0];
      if (!candidate) return;

      const cardResult = this.gameService.pickCard(
        roomCode,
        playerId,
        session.turn.turnId,
        candidate.cardId,
      );
      if ('error' in cardResult) return;

      const { session: s, orderPromptCards } = cardResult;
      this._broadcastGameStateToRoom(s, roomCode, socketIds);

      if (orderPromptCards !== null) {
        const orderedIds = s.roundCandidates.map((c) => c.cardId);
        const orderResult = this.gameService.orderHiddenDeck(
          roomCode,
          playerId,
          s.turn.turnId,
          orderedIds,
        );
        if ('error' in orderResult) return;
        const { session: s2, availableSlots } = orderResult;
        this._broadcastGameStateToRoom(s2, roomCode, socketIds);
        if (availableSlots !== undefined) {
          this.sendHiddenPickPromptToActivePlayer(s2, roomCode, availableSlots);
        }
        this._scheduleTurnTimer(s2, roomCode);
        this._maybeArmSubsTimer(s2, roomCode);
        this._maybeArmAbilityActivationTimer(s2, roomCode);
      } else {
        this._scheduleTurnTimer(s, roomCode);
      }
      return;
    }

    if (phase === 'first_player_order') {
      const orderedIds = session.roundCandidates.map((c) => c.cardId);
      const orderResult = this.gameService.orderHiddenDeck(
        roomCode,
        playerId,
        session.turn.turnId,
        orderedIds,
      );
      if ('error' in orderResult) return;
      const { session: s, availableSlots } = orderResult;
      this._broadcastGameStateToRoom(s, roomCode, socketIds);
      if (availableSlots !== undefined) {
        this.sendHiddenPickPromptToActivePlayer(s, roomCode, availableSlots);
      }
      this._scheduleTurnTimer(s, roomCode);
      this._maybeArmSubsTimer(s, roomCode);
      this._maybeArmAbilityActivationTimer(s, roomCode);
      return;
    }

    if (phase === 'hidden_pick') {
      const availableSlots =
        this.gameService.computeAvailableHiddenSlots(session);
      if (!availableSlots.length) return;

      const hiddenResult = this.gameService.pickHiddenSlot(
        roomCode,
        playerId,
        session.turn.turnId,
        availableSlots[0],
      );
      if ('error' in hiddenResult) return;

      const { session: s, revealedCard } = hiddenResult;

      // Send the revealed card privately to the picker.
      for (const id of socketIds) {
        const c = this._connectedSockets.get(id);
        if (!c) continue;
        if (this.roomsService.getSocketEntry(id)?.playerId === playerId) {
          this.send(c, 'card_revealed', { card: revealedCard });
        }
      }

      this._broadcastGameStateToRoom(s, roomCode, socketIds);
      // The existing 5-second reveal timeout handles advancing past this phase.
      this._scheduleHiddenRevealTimeout(roomCode, s.turn.turnId);
    }
  }

  // ── Ability-draft phase timer ─────────────────────────────────────────────
  // Same shape as the per-turn timer above (one active picker at a time, in
  // pickOrder), but keyed off `session.abilityDraft` rather than `session.turn`
  // — the two are tracked independently, so reusing `_scheduleTurnTimer`
  // directly would broadcast the wrong "active player" during this phase.

  private _clearAbilityDraftTimer(sessionId: string): void {
    const t = this._abilityDraftTimers.get(sessionId);
    if (t !== undefined) {
      clearTimeout(t);
      this._abilityDraftTimers.delete(sessionId);
    }
  }

  private _clearAbilityRevealTimer(roomCode: string): void {
    const t = this._abilityRevealTimers.get(roomCode);
    if (t !== undefined) {
      clearTimeout(t);
      this._abilityRevealTimers.delete(roomCode);
    }
  }

  private _clearAbilityActivationRevealTimer(roomCode: string): void {
    const t = this._abilityActivationRevealTimers.get(roomCode);
    if (t !== undefined) {
      clearTimeout(t);
      this._abilityActivationRevealTimers.delete(roomCode);
    }
  }

  private _scheduleAbilityDraftTimer(
    session: GameSession,
    roomCode: string,
  ): void {
    if (session.isFinished) return;
    if (session.status !== 'ability_draft' || !session.abilityDraft) {
      this._clearAbilityDraftTimer(session.sessionId);
      return;
    }
    this._clearAbilityDraftTimer(session.sessionId);

    const policy = session.turnTimeoutPolicy;
    const seconds =
      policy.enabled && policy.turnSeconds
        ? policy.turnSeconds
        : ABILITY_DRAFT_FALLBACK_SECONDS;

    const { sessionId } = session;
    const capturedPickIndex = session.abilityDraft.currentPickIndex;
    const t = setTimeout(() => {
      this._abilityDraftTimers.delete(sessionId);
      const current = this.gameService.getSessionByRoomCode(roomCode);
      if (
        !current ||
        current.isFinished ||
        current.status !== 'ability_draft' ||
        !current.abilityDraft
      )
        return;
      // The picker already moved on (e.g. picked right as the timer fired) —
      // don't double-pick for them.
      if (current.abilityDraft.currentPickIndex !== capturedPickIndex) return;
      this._autoPickAbilityDraft(current, roomCode);
    }, seconds * 1000);

    this._abilityDraftTimers.set(sessionId, t);
  }

  private _autoPickAbilityDraft(session: GameSession, roomCode: string): void {
    const ad = session.abilityDraft;
    if (!ad) return;
    const pickerId = ad.pickOrder[ad.currentPickIndex];
    const remaining = ad.pool.filter((c) => c.pickedBy == null);
    if (!pickerId || remaining.length === 0) return;

    const card = remaining[Math.floor(Math.random() * remaining.length)];
    const socketIds = this.roomsService.getSocketIds(roomCode);
    this.broadcastToSockets(socketIds, 'turn_auto_picked', {
      playerId: pickerId,
      reason: 'timeout',
    });

    const result = this.gameService.pickAbilityCard(
      roomCode,
      pickerId,
      card.id,
    );
    if ('error' in result) return;

    this._afterAbilityPick(result, roomCode);
  }

  private _broadcastGameStateToRoom(
    session: GameSession,
    roomCode: string,
    socketIds: string[],
  ): void {
    for (const id of socketIds) {
      const c = this._connectedSockets.get(id);
      if (!c) continue;
      const roomEntry = this.roomsService.getSocketEntry(id);
      this.send(
        c,
        'game_state',
        this.gameSnapshot(session, roomEntry?.playerId),
      );
    }
    this._maybeArmSubsTimer(session, roomCode);
    this._maybeArmAbilityActivationTimer(session, roomCode);
  }

  // ── Subs-phase timer ──────────────────────────────────────────────────────

  /**
   * Idempotently arms the shared `subsDeadlineAt` timer for bench_selection
   * (Track B step 2 → `forceFinalizeBenchSelection`) and lineup_edit
   * (Track B step 4 → `forceFinalizeLineupEdit`). Ability_activation uses
   * its own deadline/timer. Called after every game_state broadcast: arms
   * when either phase begins with a deadline, clears when the phase ends,
   * and re-arms when `subsDeadlineAt` changes (bench → lineup_edit).
   */
  private _maybeArmSubsTimer(session: GameSession, roomCode: string): void {
    const { sessionId } = session;

    const usesSubsDeadline =
      session.status === 'bench_selection' ||
      session.status === 'lineup_edit';

    // Not in a phase that uses this deadline → drop any stale timer.
    if (!usesSubsDeadline || session.subsDeadlineAt === null) {
      this._clearSubsTimer(sessionId);
      return;
    }

    const deadlineAt = session.subsDeadlineAt;
    const existing = this._subsTimers.get(sessionId);
    // Already armed for this exact deadline — leave it alone.
    if (existing && existing.deadlineAt === deadlineAt) return;
    // Deadline changed (or first arm) — clear any previous window first.
    if (existing) this._clearSubsTimer(sessionId);

    const delayMs = Math.max(0, deadlineAt - Date.now());
    const t = setTimeout(() => {
      this._subsTimers.delete(sessionId);
      const current = this.gameService.getSessionByRoomCode(roomCode);
      if (!current || current.isFinished) return;

      if (current.status === 'bench_selection') {
        const result = this.gameService.forceFinalizeBenchSelection(roomCode);
        if ('error' in result) return;
        const socketIds = this.roomsService.getSocketIds(roomCode);
        // Broadcast advanced state (ability_activation or lineup_edit). The
        // broadcast helper re-arms the ability-activation timer and/or the
        // fresh lineup_edit subs timer as appropriate.
        this._broadcastGameStateToRoom(result.session, roomCode, socketIds);
        return;
      }

      if (current.status !== 'lineup_edit') return;
      const result = this.gameService.forceFinalizeLineupEdit(roomCode);
      if ('error' in result) return;
      const socketIds = this.roomsService.getSocketIds(roomCode);
      // Broadcast the force-confirmed state (every lineupConfirmed flag just
      // flipped true) BEFORE any tournament transition — beginBracketReveal's
      // own broadcast is a separate 'tournament_state' event the client only
      // reacts to for navigation; if that message is delayed or dropped, a
      // client still sitting on the lineup_edit screen was working off a
      // stale lineupConfirmed=false and could still interact with
      // (already-locked) lineup_edit UI, which is exactly what let a player
      // "pick again" after their opponent's timeout force-confirmed everyone.
      this._broadcastGameStateToRoom(result.session, roomCode, socketIds);
      // Tournament fork: on lineup_edit timeout in a tournament-enabled
      // session, start the bracket instead of finalizing the game.
      if ('tournamentStarting' in result && result.tournamentStarting) {
        this.beginBracketReveal(roomCode);
        return;
      }
    }, delayMs);
    this._subsTimers.set(sessionId, { timer: t, deadlineAt });
  }

  private _clearSubsTimer(sessionId: string): void {
    const entry = this._subsTimers.get(sessionId);
    if (entry !== undefined) {
      clearTimeout(entry.timer);
      this._subsTimers.delete(sessionId);
    }
  }

  // ── Ability-activation phase timer ────────────────────────────────────────

  /**
   * Idempotently arms the ability-activation auto-discard timer. Same shape
   * as `_maybeArmSubsTimer`: arms once when the phase begins with a deadline,
   * clears itself when the phase ends. Called from every place that can
   * produce a session in this phase (mirrors the existing `_maybeArmSubsTimer`
   * call sites) so a player who never acts can't hang the match for everyone.
   */
  private _maybeArmAbilityActivationTimer(
    session: GameSession,
    roomCode: string,
  ): void {
    const { sessionId } = session;

    if (
      session.status !== 'ability_activation' ||
      session.abilityActivationDeadlineAt === null
    ) {
      this._clearAbilityActivationTimer(sessionId);
      return;
    }
    if (this._abilityActivationTimers.has(sessionId)) return;

    const delayMs = Math.max(
      0,
      session.abilityActivationDeadlineAt - Date.now(),
    );
    const t = setTimeout(() => {
      this._abilityActivationTimers.delete(sessionId);
      const current = this.gameService.getSessionByRoomCode(roomCode);
      if (
        !current ||
        current.isFinished ||
        current.status !== 'ability_activation'
      )
        return;
      const result = this.gameService.forceFinalizeAbilityActivation(roomCode);
      if ('error' in result) return;
      const socketIds = this.roomsService.getSocketIds(roomCode);
      this._broadcastGameStateToRoom(result.session, roomCode, socketIds);
    }, delayMs);
    this._abilityActivationTimers.set(sessionId, t);
  }

  private _clearAbilityActivationTimer(sessionId: string): void {
    const t = this._abilityActivationTimers.get(sessionId);
    if (t !== undefined) {
      clearTimeout(t);
      this._abilityActivationTimers.delete(sessionId);
    }
  }

  /**
   * After a player is removed, sends the appropriate next prompt if the
   * game transitioned to hidden_pick automatically.
   */
  private _maybeSendNextPrompt(
    session: GameSession,
    roomCode: string,
    removeResult: ReturnType<typeof this.gameService.removePlayer>,
  ): void {
    if (!removeResult) return;

    const { autoHiddenPickSlots } = removeResult;
    if (autoHiddenPickSlots !== undefined) {
      this.sendHiddenPickPromptToActivePlayer(
        session,
        roomCode,
        autoHiddenPickSlots,
      );
    }
  }

  /**
   * Task 3.6 — a kick/leave during 'ability_draft' or 'ability_activation'
   * previously left the removed player's slot unresolved forever (no code
   * path advanced either phase for a player who's gone). Reuses the exact
   * same orchestration a real player action would, rather than duplicating
   * it: `_afterAbilityPick` for the draft (clears/rearms the draft timer,
   * runs the reveal-window-then-beginPlayerDraft sequence on the final
   * pick) and `_maybeArmAbilityActivationTimer` for activation (clears the
   * activation timer if the phase just ended, otherwise leaves it armed).
   * Phase 5 audit: the same class of gap existed for lineup_edit (formerly
   * the combined 'subs' phase) — a removed player's un-confirmable lineup
   * could permanently block everyone else's completion check. `removePlayer`
   * now resolves that itself (deletes the entry, finalizes if that was the
   * last confirmation needed); this only has to handle the one thing
   * `removePlayer` can't do on its own — start the tournament bracket,
   * exactly like `handleConfirmLineup` does for a real confirm, when
   * `subsTournamentStarting` comes back set.
   */
  private _afterPlayerRemoved(
    removeResult: ReturnType<typeof this.gameService.removePlayer>,
    roomCode: string,
  ): void {
    if (!removeResult) return;

    if (removeResult.abilityDraftAllPicked !== undefined) {
      this._afterAbilityPick(
        {
          session: removeResult.session,
          allPicked: removeResult.abilityDraftAllPicked,
        },
        roomCode,
      );
    }

    if (removeResult.abilityActivationAllResolved !== undefined) {
      this._afterAbilityActivation(
        {
          session: removeResult.session,
          allResolved: removeResult.abilityActivationAllResolved,
        },
        roomCode,
      );
    }

    if (removeResult.subsTournamentStarting) {
      this.beginBracketReveal(roomCode);
    }

    // Phase 7 audit: a removed player who was a real participant in the
    // CURRENT ready_check round is now auto-readied by removePlayer itself
    // (see its tournament block) — this only has to do what
    // handleTournamentReady does with that same signal: broadcast the
    // updated state, and if their removal was the LAST ready needed, start
    // simulating immediately rather than leaving the round to wait out the
    // full 60s timer for someone who's no longer in the room.
    if (removeResult.tournamentAllReadyAfterRemoval !== undefined) {
      this.broadcastTournamentStateToRoom(roomCode);
      if (removeResult.tournamentAllReadyAfterRemoval) {
        this._clearTournamentReadyTimer(roomCode);
        this.beginSimulating(roomCode);
      }
    }

    this._maybeArmAbilityActivationTimer(removeResult.session, roomCode);
    this._maybeArmSubsTimer(removeResult.session, roomCode);
  }

  // ── Tournament mode ─────────────────────────────────────────────────────────

  /** Player presses Ready for their current-round match. */
  @SubscribeMessage('tournament_ready')
  handleTournamentReady(
    @ConnectedSocket() client: WebSocket & { id: string },
    @MessageBody() _dto: TournamentReadyDto,
  ): void {
    const entry = this.roomsService.getSocketEntry(client.id);
    if (!entry) {
      this.send(client, 'error', {
        code: ErrorCodes.TOURNAMENT_NOT_IN_READY_CHECK,
      });
      return;
    }
    this.roomsService.touchRoomActivity(entry.roomCode);

    const session = this.gameService.getSessionByRoomCode(entry.roomCode);
    if (
      !session ||
      session.status !== 'tournament' ||
      session.tournament?.phase !== 'ready_check'
    ) {
      this.send(client, 'error', {
        code: ErrorCodes.TOURNAMENT_NOT_IN_READY_CHECK,
      });
      return;
    }

    const result = this.gameService.recordTournamentReady(
      entry.roomCode,
      entry.playerId,
    );
    if ('error' in result) {
      this.send(client, 'error', { code: result.error });
      return;
    }

    this.broadcastTournamentStateToRoom(entry.roomCode);
    if (result.allReady) {
      this._clearTournamentReadyTimer(entry.roomCode);
      this.beginSimulating(entry.roomCode);
    }
  }

  // ── Tournament orchestration (timer callbacks + ready-driven transitions) ────

  private beginBracketReveal(roomCode: string): void {
    const tournament = this.gameService.beginTournament(roomCode);
    // Leaving the subs phase — drop any lingering subs timer so it can't fire
    // against the now-tournament session (it would no-op, but clear it anyway).
    const session = this.gameService.getSessionByRoomCode(roomCode);
    if (session) this._clearSubsTimer(session.sessionId);

    this.broadcastTournamentStateToRoom(roomCode);

    const delay = Math.max(0, tournament.bracketRevealAt - Date.now());
    const t = setTimeout(() => {
      this._tournamentRevealTimers.delete(roomCode);
      this.beginReadyCheck(roomCode);
    }, delay);
    this._tournamentRevealTimers.set(roomCode, t);
  }

  private beginReadyCheck(roomCode: string): void {
    this._clearTournamentRevealTimer(roomCode);
    this.gameService.advanceTournamentPhase(roomCode, 'ready_check');

    // Announce AI auto-readies (cosmetic; the authoritative state follows).
    const session = this.gameService.getSessionByRoomCode(roomCode);
    if (session?.tournament) {
      for (const id of session.tournament.readyPlayerIds) {
        this.broadcastRoom(roomCode, 'tournament_auto_ready', {
          participantId: id,
          reason: 'ai',
        });
      }
    }
    this.broadcastTournamentStateToRoom(roomCode);

    // All-AI round (no real participants to wait on) → simulate immediately.
    if (this._isTournamentRoundAllReady(roomCode)) {
      this.beginSimulating(roomCode);
      return;
    }

    const t = setTimeout(() => {
      this._tournamentReadyTimers.delete(roomCode);
      this.autoReadyAndBeginSimulating(roomCode);
    }, 60_000);
    this._tournamentReadyTimers.set(roomCode, t);
  }

  private autoReadyAndBeginSimulating(roomCode: string): void {
    this._clearTournamentReadyTimer(roomCode);
    const session = this.gameService.getSessionByRoomCode(roomCode);
    const before = session?.tournament
      ? [...session.tournament.readyPlayerIds]
      : [];
    const t = this.gameService.autoReadyRemainingPlayers(roomCode);
    for (const id of t.readyPlayerIds) {
      if (!before.includes(id)) {
        this.broadcastRoom(roomCode, 'tournament_auto_ready', {
          participantId: id,
          reason: 'timeout',
        });
      }
    }
    this.broadcastTournamentStateToRoom(roomCode);
    this.beginSimulating(roomCode);
  }

  /**
   * How many ms elapse between delivering each queued match event to
   * clients during `beginSimulating`. This is presentation pacing only —
   * the match result (`match.result`/`simulationEvents`) is already fully
   * computed before this timer starts, so the outcome can never change,
   * only how long watching it unfold takes. 1500ms is the pre-existing
   * default ("normal"); fast/slow scale it down/up around that baseline.
   */
  private simulationSpeedIntervalMs(speed: SimulationSpeed): number {
    switch (speed) {
      case 'fast':
        return 700;
      case 'slow':
        return 2600;
      case 'normal':
      default:
        return 1500;
    }
  }

  private beginSimulating(roomCode: string): void {
    this._clearTournamentReadyTimer(roomCode);
    this.gameService.advanceTournamentPhase(roomCode, 'simulating');
    this.broadcastTournamentStateToRoom(roomCode);

    const session = this.gameService.getSessionByRoomCode(roomCode);
    if (!session?.tournament) return;
    const t = session.tournament;
    const round = t.bracket.rounds[t.currentRound - 1];

    // Merge all matches' events into one queue, round-robin interleaved so
    // parallel matches progress at similar rates for spectators.
    const perMatch = round.matches.map((m) => ({
      match: m,
      events: m.simulationEvents,
    }));
    const maxLen = perMatch.reduce(
      (mx, pm) => Math.max(mx, pm.events.length),
      0,
    );
    const queue: {
      match: TournamentMatch;
      event: (typeof perMatch)[number]['events'][number];
    }[] = [];
    for (let i = 0; i < maxLen; i++) {
      for (const pm of perMatch) {
        if (i < pm.events.length)
          queue.push({ match: pm.match, event: pm.events[i] });
      }
    }

    const scores = new Map<string, { a: number; b: number }>();
    const delivered = new Map<string, number>();
    for (const m of round.matches) {
      scores.set(m.matchId, { a: 0, b: 0 });
      delivered.set(m.matchId, 0);
    }

    let idx = 0;
    const isFinal = t.currentRound >= t.totalRounds;
    // Host-chosen pacing (room setting, carried onto the session at creation)
    // — purely how fast events are delivered to clients, never a change to
    // the simulated result itself (already fully computed by this point).
    const eventIntervalMs = this.simulationSpeedIntervalMs(
      session.simulationSpeed,
    );
    const interval = setInterval(() => {
      if (idx >= queue.length) {
        this._clearTournamentSimTimer(roomCode);
        const rt = setTimeout(() => {
          this._tournamentResultTimers.delete(roomCode);
          if (isFinal) this.beginTournamentComplete(roomCode);
          else this.beginRoundResult(roomCode);
        }, 3_000);
        this._tournamentResultTimers.set(roomCode, rt);
        return;
      }

      const { match, event } = queue[idx++];
      const sc = scores.get(match.matchId)!;
      if (event.type === 'goal') {
        if (event.teamParticipantId === match.participantA.participantId)
          sc.a++;
        else sc.b++;
      }
      this.broadcastRoom(roomCode, 'tournament_match_event', {
        matchId: match.matchId,
        roundNumber: match.roundNumber,
        event,
        currentScoreA: sc.a,
        currentScoreB: sc.b,
      } as TournamentMatchEventPayload);

      const dcount = (delivered.get(match.matchId) ?? 0) + 1;
      delivered.set(match.matchId, dcount);
      if (dcount >= match.simulationEvents.length) {
        match.status = 'complete';
        if (match.result) {
          this.broadcastRoom(roomCode, 'tournament_match_result', {
            matchId: match.matchId,
            roundNumber: match.roundNumber,
            scoreA: match.result.scoreA,
            scoreB: match.result.scoreB,
            winnerId: match.result.winnerId,
            penaltyScoreA: match.result.penaltyScoreA,
            penaltyScoreB: match.result.penaltyScoreB,
            stats: match.result.stats,
            playerRatings: match.result.playerRatings,
            explanation: match.result.explanation,
          } as TournamentMatchResultPayload);
        }
      }
    }, eventIntervalMs);
    this._tournamentSimTimers.set(roomCode, interval);
  }

  private beginRoundResult(roomCode: string): void {
    this._clearTournamentResultTimer(roomCode);
    this.gameService.advanceTournamentPhase(roomCode, 'round_result');
    this.broadcastTournamentStateToRoom(roomCode);

    const t = setTimeout(() => {
      this._tournamentResultTimers.delete(roomCode);
      const session = this.gameService.getSessionByRoomCode(roomCode);
      if (session?.tournament) session.tournament.currentRound += 1;
      this.beginReadyCheck(roomCode);
    }, 5_000);
    this._tournamentResultTimers.set(roomCode, t);
  }

  private beginTournamentComplete(roomCode: string): void {
    this._clearTournamentResultTimer(roomCode);
    const t = this.gameService.advanceTournamentPhase(roomCode, 'complete');

    // Every other phase transition re-syncs clients via a fresh tournament_state
    // snapshot (beginReadyCheck/beginSimulating/beginRoundResult all call this).
    // Without it here, clients never learn the final match's status flipped to
    // 'complete' — they stay on the last snapshot taken at kickoff (phase
    // 'simulating'), so the final visually freezes at its last delivered event
    // minute even though the server has already finished and moved on.
    this.broadcastTournamentStateToRoom(roomCode);

    const finalRound = t.bracket.rounds[t.bracket.rounds.length - 1];
    const finalMatch = finalRound.matches[0];
    const awards = t.awards;
    if (awards) {
      const finalSnapshot = this._completedMatchSnapshot(finalMatch);
      const payload: TournamentCompletePayload = {
        champion: this._participantSnapshot(awards.champion),
        runnerUp: this._participantSnapshot(awards.runnerUp),
        topScorer: awards.topScorer,
        mostAssists: awards.mostAssists,
        topContributions: awards.topContributions,
        highestAvgRating: awards.highestAvgRating,
        cleanSheets: awards.cleanSheets,
        pointsAwarded: awards.pointsAwarded,
        blockedCategories: awards.blockedCategories,
        pointsConfig: awards.pointsConfig,
        finalMatch: finalSnapshot ?? {
          scoreA: 0,
          scoreB: 0,
          penaltyScoreA: null,
          penaltyScoreB: null,
          stats: {
            possessionA: 50,
            shotsA: 0,
            shotsOnTargetA: 0,
            bigChancesA: 0,
            shotsB: 0,
            shotsOnTargetB: 0,
            bigChancesB: 0,
          },
          explanation: '',
        },
      };
      this.broadcastRoom(roomCode, 'tournament_complete', payload);
    }

    // 3s later, send the normal game_state(finished) so the client navigates to
    // the result screen exactly as today (advanceTournamentPhase('complete')
    // already set status='finished' + populated session.result).
    const timer = setTimeout(() => {
      this._tournamentResultTimers.delete(roomCode);
      const session = this.gameService.getSessionByRoomCode(roomCode);
      if (!session) return;
      const socketIds = this.roomsService.getSocketIds(roomCode);
      this._broadcastGameStateToRoom(session, roomCode, socketIds);
    }, 3_000);
    this._tournamentResultTimers.set(roomCode, timer);
  }

  // ── Tournament broadcast / snapshot helpers ─────────────────────────────────

  private broadcastTournamentStateToRoom(roomCode: string): void {
    const session = this.gameService.getSessionByRoomCode(roomCode);
    if (!session?.tournament) return;
    const payload = this.buildTournamentStatePayload(session.tournament);
    const socketIds = this.roomsService.getSocketIds(roomCode);
    for (const id of socketIds)
      this.sendToSocket(id, 'tournament_state', payload);
  }

  /**
   * Builds the client-safe tournament snapshot. CRITICAL: must never include
   * the server-only `simulationEvents` / `nextEventIndex` fields from any
   * match — `_matchSnapshot` picks only the safe fields explicitly (no spread).
   */
  private buildTournamentStatePayload(
    tournament: TournamentState,
  ): TournamentStatePayload {
    return {
      phase: tournament.phase,
      currentRound: tournament.currentRound,
      totalRounds: tournament.totalRounds,
      readyPlayerIds: tournament.readyPlayerIds,
      readyDeadlineAt: tournament.readyDeadlineAt,
      bracketRevealAt:
        tournament.phase === 'bracket_reveal'
          ? tournament.bracketRevealAt
          : null,
      bracket: {
        size: tournament.bracket.size,
        rounds: tournament.bracket.rounds.map((round) => ({
          roundNumber: round.roundNumber,
          label: round.label,
          status: round.status,
          matches: round.matches.map((m) => this._matchSnapshot(m)),
        })),
      },
      awards: tournament.awards
        ? {
            champion: this._participantSnapshot(tournament.awards.champion),
            runnerUp: this._participantSnapshot(tournament.awards.runnerUp),
            topScorer: tournament.awards.topScorer,
            mostAssists: tournament.awards.mostAssists,
            topContributions: tournament.awards.topContributions,
            highestAvgRating: tournament.awards.highestAvgRating,
            cleanSheets: tournament.awards.cleanSheets,
            pointsAwarded: tournament.awards.pointsAwarded,
            blockedCategories: tournament.awards.blockedCategories,
            pointsConfig: tournament.awards.pointsConfig,
          }
        : null,
    };
  }

  private _matchSnapshot(m: TournamentMatch): MatchSnapshot {
    return {
      matchId: m.matchId,
      roundNumber: m.roundNumber,
      participantA: this._participantSnapshot(m.participantA),
      participantB: this._participantSnapshot(m.participantB),
      status: m.status,
      result: this._completedMatchSnapshot(m),
      winnerId: m.status === 'complete' ? m.winnerId : null,
    };
  }

  private _participantSnapshot(p: TournamentParticipant): ParticipantSnapshot {
    return {
      kind: p.kind,
      participantId: p.participantId,
      displayName: p.displayName,
      overallRating: p.lineup?.overallRating ?? 0,
      clubLogoUrl: p.clubLogoUrl,
    };
  }

  private _completedMatchSnapshot(
    m: TournamentMatch,
  ): CompletedMatchSnapshot | null {
    if (m.status !== 'complete' || !m.result) return null;
    return {
      scoreA: m.result.scoreA,
      scoreB: m.result.scoreB,
      penaltyScoreA: m.result.penaltyScoreA,
      penaltyScoreB: m.result.penaltyScoreB,
      stats: m.result.stats,
      explanation: m.result.explanation,
    };
  }

  private _isTournamentRoundAllReady(roomCode: string): boolean {
    const session = this.gameService.getSessionByRoomCode(roomCode);
    const t = session?.tournament;
    if (!t) return false;
    const round = t.bracket.rounds[t.currentRound - 1];
    for (const m of round.matches) {
      for (const p of [m.participantA, m.participantB]) {
        if (
          p.kind === 'real' &&
          p.participantId !== '' &&
          !t.readyPlayerIds.includes(p.participantId)
        ) {
          return false;
        }
      }
    }
    return true;
  }

  // ── Tournament timer clears ─────────────────────────────────────────────────

  private _clearTournamentRevealTimer(roomCode: string): void {
    const t = this._tournamentRevealTimers.get(roomCode);
    if (t) {
      clearTimeout(t);
      this._tournamentRevealTimers.delete(roomCode);
    }
  }

  private _clearTournamentReadyTimer(roomCode: string): void {
    const t = this._tournamentReadyTimers.get(roomCode);
    if (t) {
      clearTimeout(t);
      this._tournamentReadyTimers.delete(roomCode);
    }
  }

  private _clearTournamentSimTimer(roomCode: string): void {
    const t = this._tournamentSimTimers.get(roomCode);
    if (t) {
      clearInterval(t);
      this._tournamentSimTimers.delete(roomCode);
    }
  }

  private _clearTournamentResultTimer(roomCode: string): void {
    const t = this._tournamentResultTimers.get(roomCode);
    if (t) {
      clearTimeout(t);
      this._tournamentResultTimers.delete(roomCode);
    }
  }
}
