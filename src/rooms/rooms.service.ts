import { Injectable } from '@nestjs/common';
import { v4 as uuidv4 } from 'uuid';
import { InjectPinoLogger, PinoLogger } from 'nestjs-pino';
import { Player, Room, PendingJoinRequest, SimulationSpeed, Spectator } from './interfaces/room.interface';

const CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
const CODE_LENGTH = 6;
const MAX_PLAYERS = 10;
const MIN_PLAYERS = 2;
// Much higher than MAX_PLAYERS — spectators carry none of a player's cost
// (no pitch, no turn-order slot, no per-action validation), so there's no
// reason to cap them anywhere near as tightly. Purely a sanity ceiling
// against a single room being flooded, not a capacity concern.
const MAX_SPECTATORS = 50;

@Injectable()
export class RoomsService {
  private rooms = new Map<string, Room>();
  // socket → { roomCode, playerId } — ephemeral, cleared on disconnect or explicit exit
  private socketIndex = new Map<string, { roomCode: string; playerId: string }>();
  // player → roomCode — persists through disconnects; cleared on permanent removal
  private playerRoomIndex = new Map<string, string>();
  // Deliberately SEPARATE from socketIndex/playerRoomIndex above — a
  // spectator's socket must never resolve via getSocketEntry(), which every
  // gameplay handler already uses as its "am I in this room" guard. Keeping
  // spectators out of that map is what makes them structurally unable to
  // trigger gameplay logic, rather than relying on a role check every
  // handler would otherwise need to remember to add.
  private spectatorSocketIndex = new Map<string, { roomCode: string; spectatorId: string }>();
  private spectatorRoomIndex = new Map<string, string>();

  // Defaulted (not required) so every existing `new RoomsService()` test
  // instantiation keeps working unchanged — see the same pattern in
  // RoomsGateway's constructor for the full rationale.
  constructor(
    // Silent by default — this fallback only ever runs in a test/non-DI
    // context (production always gets the real, app-configured logger via
    // DI), and a silent default keeps test output clean.
    @InjectPinoLogger(RoomsService.name)
    private readonly logger: PinoLogger = new PinoLogger({ pinoHttp: { level: 'silent' } }),
  ) {}

  // ── Helpers ───────────────────────────────────────────────────────────────

  getRoom(roomCode: string): Room | undefined {
    return this.rooms.get(roomCode.toUpperCase());
  }

  /** Number of currently tracked rooms (lobby + in-progress). For /metrics (Task 3.4). */
  getRoomCount(): number {
    return this.rooms.size;
  }

  getRoomBySocket(socketId: string): Room | null {
    const entry = this.socketIndex.get(socketId);
    if (!entry) return null;
    return this.rooms.get(entry.roomCode) ?? null;
  }

  /**
   * Every socket that should receive this room's broadcasts — players AND
   * spectators. Every call site in rooms.gateway.ts already uses this purely
   * for fan-out (broadcastToSockets, or a per-socket loop that resolves the
   * recipient's own playerId via getSocketEntry() for a per-viewer snapshot);
   * none of them use it for a capacity/authorization decision. That's what
   * makes it safe to fold spectators in here once, instead of touching every
   * broadcast call site individually — a spectator's socket isn't in
   * socketIndex, so getSocketEntry() naturally returns undefined for it and
   * every per-viewer snapshot correctly falls back to the "no local player"
   * view (no private per-player data leaks to a spectator).
   */
  getSocketIds(roomCode: string): string[] {
    const room = this.rooms.get(roomCode);
    if (!room) return [];
    return [
      ...room.players.filter((p) => p.socketId).map((p) => p.socketId!),
      ...room.spectators.filter((s) => s.socketId).map((s) => s.socketId!),
    ];
  }

  /** Spectator sockets only — for the rare call site that needs to address just them. */
  getSpectatorSocketIds(roomCode: string): string[] {
    const room = this.rooms.get(roomCode);
    if (!room) return [];
    return room.spectators.filter((s) => s.socketId).map((s) => s.socketId!);
  }

  getSpectatorSocketEntry(socketId: string): { roomCode: string; spectatorId: string } | undefined {
    return this.spectatorSocketIndex.get(socketId);
  }

  getSocketEntry(socketId: string): { roomCode: string; playerId: string } | undefined {
    return this.socketIndex.get(socketId);
  }

  /**
   * Marks a room as active right now. Called on every recognized gameplay
   * action so a slow-but-alive game is never mistaken for an abandoned one by
   * the stale-room sweep (`getStaleRooms`/`_cleanStaleRooms`). No-op if the
   * room no longer exists (e.g. a late message arrives after teardown).
   */
  touchRoomActivity(roomCode: string): void {
    const room = this.rooms.get(roomCode);
    if (room) room.lastActivityAt = Date.now();
  }

  // ── Room code generation ──────────────────────────────────────────────────

  private generateCode(): string {
    let code: string;
    let attempts = 0;
    do {
      code = Array.from({ length: CODE_LENGTH }, () =>
        CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)],
      ).join('');
      attempts++;
      if (attempts > 100) throw new Error('Failed to generate unique room code');
    } while (this.rooms.has(code));
    return code;
  }

  // ── Shared: permanent removal ──────────────────────────────────────────────

  /**
   * Every spectator loses their seat once no players are left — there's
   * nothing left to watch, and leaving them tracked would leak
   * spectatorSocketIndex/spectatorRoomIndex entries for a room that no
   * longer exists. Called from every path that deletes a room outright
   * (last player permanently removed, last player disconnects).
   */
  private _evictAllSpectators(room: Room): void {
    for (const s of room.spectators) {
      if (s.socketId) this.spectatorSocketIndex.delete(s.socketId);
      this.spectatorRoomIndex.delete(s.id);
    }
    room.spectators = [];
  }

  private permanentlyRemove(
    room: Room,
    playerId: string,
    socketId?: string,
  ): { room: Room | null; roomCode: string } {
    this.playerRoomIndex.delete(playerId);
    if (socketId) this.socketIndex.delete(socketId);

    room.pendingJoinRequests = room.pendingJoinRequests.filter((r) => r.requestId !== playerId);
    room.players = room.players.filter((p) => p.id !== playerId);

    if (room.players.length === 0) {
      this._evictAllSpectators(room);
      this.rooms.delete(room.code);
      return { room: null, roomCode: room.code };
    }

    if (!room.players.some((p) => p.isHost)) {
      const next = room.players.find((p) => p.isConnected) ?? room.players[0];
      next.isHost = true;
    }

    return { room, roomCode: room.code };
  }

  // ── Create ────────────────────────────────────────────────────────────────

  createRoom(
    displayName: string,
    socketId: string,
    leagues: string[] = [],
    turnTimerSeconds: number | null = null,
    subsTimerSeconds: number | null = null,
    formationSlug: string | null = null,
    tournamentEnabled: boolean = false,
    simulationSpeed: SimulationSpeed = 'normal',
    abilityTimerSeconds: number | null = null,
    selectedBundleId: string | null = null,
    selectedBundleName: string | null = null,
  ): { room: Room; playerId: string } {
    const code = this.generateCode();
    const playerId = uuidv4();
    const host: Player = { id: playerId, displayName, isHost: true, isConnected: true, socketId };
    const room: Room = {
      code,
      players: [host],
      spectators: [],
      isStarted: false,
      isLocked: false,
      kickedPlayerIds: [],
      kickedDisplayNames: [],
      pendingJoinRequests: [],
      lastActivityAt: Date.now(),
      leagues,
      selectedBundleId,
      selectedBundleName,
      turnTimerSeconds,
      subsTimerSeconds,
      abilityTimerSeconds,
      formationSlug,
      tournamentEnabled,
      simulationSpeed,
    };
    this.rooms.set(code, room);
    this.socketIndex.set(socketId, { roomCode: code, playerId });
    this.playerRoomIndex.set(playerId, code);
    return { room, playerId };
  }

  // ── Join ──────────────────────────────────────────────────────────────────

  joinRoom(
    roomCode: string,
    displayName: string,
    socketId: string,
  ):
    | { room: Room; playerId: string }
    | { pending: true; request: PendingJoinRequest; hostSocketId: string | null; roomCode: string }
    | { error: string } {
    const room = this.rooms.get(roomCode.toUpperCase());
    if (!room) return { error: 'ROOM_NOT_FOUND' };
    if (room.isStarted) return { error: 'ROOM_STARTED' };

    if (room.kickedDisplayNames.includes(displayName.toLowerCase())) {
      return { error: 'KICKED' };
    }

    const existingActive = room.players.find((p) => p.socketId === socketId && p.isConnected);
    if (existingActive) return { error: 'ALREADY_IN_ROOM' };

    const connected = room.players.filter((p) => p.isConnected).length;
    if (connected >= MAX_PLAYERS) return { error: 'ROOM_FULL' };

    if (room.isLocked) {
      const requestId = uuidv4();
      const req: PendingJoinRequest = { requestId, displayName, socketId };
      room.pendingJoinRequests.push(req);
      this.socketIndex.set(socketId, { roomCode: room.code, playerId: requestId });
      const host = room.players.find((p) => p.isHost);
      return { pending: true, request: req, hostSocketId: host?.socketId ?? null, roomCode: room.code };
    }

    const playerId = uuidv4();
    room.players.push({ id: playerId, displayName, isHost: false, isConnected: true, socketId });
    this.socketIndex.set(socketId, { roomCode: room.code, playerId });
    this.playerRoomIndex.set(playerId, room.code);
    room.lastActivityAt = Date.now();
    return { room, playerId };
  }

  // ── Join request: approve ─────────────────────────────────────────────────

  approveJoin(
    hostSocketId: string,
    requestId: string,
  ): { room: Room; roomCode: string; approvedSocketId: string; playerId: string } | { error: string } {
    const entry = this.socketIndex.get(hostSocketId);
    if (!entry) return { error: 'NOT_IN_ROOM' };

    const { roomCode, playerId: hostPlayerId } = entry;
    const room = this.rooms.get(roomCode);
    if (!room) return { error: 'ROOM_NOT_FOUND' };

    const host = room.players.find((p) => p.id === hostPlayerId);
    if (!host?.isHost) return { error: 'NOT_HOST' };

    const reqIndex = room.pendingJoinRequests.findIndex((r) => r.requestId === requestId);
    if (reqIndex === -1) return { error: 'REQUEST_NOT_FOUND' };

    // joinRoom checks capacity when a request is first QUEUED, but not again
    // here at approval time — two requests can each pass that initial check
    // while the room still has room for one of them, then both get approved
    // in sequence, pushing the room over MAX_PLAYERS. The request is left in
    // the queue (not spliced out) on this rejection, so the host can still
    // approve someone else, or retry this one later if a slot frees up.
    const connected = room.players.filter((p) => p.isConnected).length;
    if (connected >= MAX_PLAYERS) return { error: 'ROOM_FULL' };

    const req = room.pendingJoinRequests[reqIndex];
    room.pendingJoinRequests.splice(reqIndex, 1);

    const newPlayer: Player = {
      id: req.requestId,
      displayName: req.displayName,
      isHost: false,
      isConnected: true,
      socketId: req.socketId,
    };
    room.players.push(newPlayer);
    this.socketIndex.set(req.socketId, { roomCode, playerId: req.requestId });
    this.playerRoomIndex.set(req.requestId, roomCode);
    room.lastActivityAt = Date.now();

    return { room, roomCode, approvedSocketId: req.socketId, playerId: req.requestId };
  }

  // ── Join request: reject ──────────────────────────────────────────────────

  rejectJoin(
    hostSocketId: string,
    requestId: string,
  ): { roomCode: string; rejectedSocketId: string } | { error: string } {
    const entry = this.socketIndex.get(hostSocketId);
    if (!entry) return { error: 'NOT_IN_ROOM' };

    const { roomCode, playerId: hostPlayerId } = entry;
    const room = this.rooms.get(roomCode);
    if (!room) return { error: 'ROOM_NOT_FOUND' };

    const host = room.players.find((p) => p.id === hostPlayerId);
    if (!host?.isHost) return { error: 'NOT_HOST' };

    const reqIndex = room.pendingJoinRequests.findIndex((r) => r.requestId === requestId);
    if (reqIndex === -1) return { error: 'REQUEST_NOT_FOUND' };

    const req = room.pendingJoinRequests[reqIndex];
    room.pendingJoinRequests.splice(reqIndex, 1);
    this.socketIndex.delete(req.socketId);

    return { roomCode, rejectedSocketId: req.socketId };
  }

  // ── Reconnect (after check_presence) ─────────────────────────────────────

  reconnect(
    roomCode: string,
    playerId: string,
    socketId: string,
  ): { room: Room } | { error: string } {
    const room = this.rooms.get(roomCode.toUpperCase());
    if (!room) return { error: 'ROOM_NOT_FOUND' };
    const player = room.players.find((p) => p.id === playerId);
    if (!player) return { error: 'PLAYER_NOT_FOUND' };

    if (player.socketId) this.socketIndex.delete(player.socketId);
    player.isConnected = true;
    player.socketId = socketId;
    this.socketIndex.set(socketId, { roomCode: room.code, playerId });
    this.playerRoomIndex.set(playerId, room.code);
    room.lastActivityAt = Date.now();
    return { room };
  }

  // ── Leave lobby (permanent, pre-game only) ────────────────────────────────

  leaveLobby(socketId: string): { room: Room | null; roomCode: string } | null {
    const entry = this.socketIndex.get(socketId);
    if (!entry) return null;

    const { roomCode, playerId } = entry;
    const room = this.rooms.get(roomCode);
    if (!room) return null;

    // Clean up pending requests from this player first
    const pendingIdx = room.pendingJoinRequests.findIndex((r) => r.requestId === playerId);
    if (pendingIdx !== -1) {
      room.pendingJoinRequests.splice(pendingIdx, 1);
      this.socketIndex.delete(socketId);
      return null;
    }

    return this.permanentlyRemove(room, playerId, socketId);
  }

  // ── Exit game to home (temporary — player stays in game session) ──────────

  exitGameToHome(socketId: string): { room: Room; roomCode: string; playerId: string } | null {
    const entry = this.socketIndex.get(socketId);
    if (!entry) return null;

    this.socketIndex.delete(socketId); // clear so handleDisconnect is a no-op
    const { roomCode, playerId } = entry;
    const room = this.rooms.get(roomCode);
    if (!room) return null;

    const player = room.players.find((p) => p.id === playerId);
    if (!player) return null;

    player.isConnected = false;
    player.socketId = null;
    // playerRoomIndex kept — player can check_presence later

    return { room, roomCode, playerId };
  }

  // ── Leave game permanently (full removal during running game) ─────────────

  leaveGamePermanently(
    socketId: string,
    fallbackPlayerId?: string,
    fallbackRoomCode?: string,
  ): { room: Room | null; roomCode: string; playerId: string } | null {
    let entry = this.socketIndex.get(socketId);

    if (!entry && fallbackPlayerId && fallbackRoomCode) {
      const storedCode = this.playerRoomIndex.get(fallbackPlayerId);
      if (storedCode && storedCode === fallbackRoomCode.toUpperCase()) {
        entry = { roomCode: storedCode, playerId: fallbackPlayerId };
      }
    }

    if (!entry) return null;

    const { roomCode, playerId } = entry;
    const room = this.rooms.get(roomCode);
    if (!room) return null;

    const result = this.permanentlyRemove(room, playerId, socketId);
    return { ...result, playerId };
  }

  // ── Kick ──────────────────────────────────────────────────────────────────

  kickPlayer(
    socketId: string,
    targetPlayerId: string,
  ): { room: Room; roomCode: string; targetSocketId: string | null } | { error: string } {
    const entry = this.socketIndex.get(socketId);
    if (!entry) return { error: 'NOT_IN_ROOM' };

    const { roomCode, playerId } = entry;
    const room = this.rooms.get(roomCode);
    if (!room) return { error: 'ROOM_NOT_FOUND' };

    const requester = room.players.find((p) => p.id === playerId);
    if (!requester?.isHost) return { error: 'NOT_HOST' };
    if (targetPlayerId === playerId) return { error: 'CANNOT_KICK_SELF' };

    const target = room.players.find((p) => p.id === targetPlayerId);
    if (!target) return { error: 'PLAYER_NOT_FOUND' };

    const targetSocketId = target.socketId;

    room.kickedPlayerIds.push(targetPlayerId);
    room.kickedDisplayNames.push(target.displayName.toLowerCase());

    this.permanentlyRemove(room, targetPlayerId, targetSocketId ?? undefined);

    return { room, roomCode, targetSocketId };
  }

  // ── Transfer host ─────────────────────────────────────────────────────────

  transferHost(
    socketId: string,
    targetPlayerId: string,
  ): { room: Room; roomCode: string } | { error: string } {
    const entry = this.socketIndex.get(socketId);
    if (!entry) return { error: 'NOT_IN_ROOM' };

    const { roomCode, playerId } = entry;
    const room = this.rooms.get(roomCode);
    if (!room) return { error: 'ROOM_NOT_FOUND' };

    const requester = room.players.find((p) => p.id === playerId);
    if (!requester?.isHost) return { error: 'NOT_HOST' };
    if (targetPlayerId === playerId) return { error: 'ALREADY_HOST' };

    const target = room.players.find((p) => p.id === targetPlayerId);
    if (!target) return { error: 'PLAYER_NOT_FOUND' };
    // A disconnected player can't act as host — no one could lock/unlock,
    // kick, approve joins, or start the game until they happened to
    // reconnect, effectively stranding the room. Mirrors the same
    // connected-player requirement permanentlyRemove's auto-reassignment
    // already applies when a host leaves outright.
    if (!target.isConnected) return { error: 'TARGET_DISCONNECTED' };

    requester.isHost = false;
    target.isHost = true;

    return { room, roomCode };
  }

  // ── Lock / Unlock ─────────────────────────────────────────────────────────

  lockRoom(socketId: string): { room: Room; roomCode: string } | { error: string } {
    return this.setLocked(socketId, true);
  }

  unlockRoom(socketId: string): { room: Room; roomCode: string } | { error: string } {
    return this.setLocked(socketId, false);
  }

  private setLocked(socketId: string, locked: boolean): { room: Room; roomCode: string } | { error: string } {
    const entry = this.socketIndex.get(socketId);
    if (!entry) return { error: 'NOT_IN_ROOM' };

    const { roomCode, playerId } = entry;
    const room = this.rooms.get(roomCode);
    if (!room) return { error: 'ROOM_NOT_FOUND' };

    const player = room.players.find((p) => p.id === playerId);
    if (!player?.isHost) return { error: 'NOT_HOST' };

    room.isLocked = locked;
    return { room, roomCode };
  }

  // ── Check Presence ────────────────────────────────────────────────────────

  checkPresence(
    playerId: string,
    roomCode: string,
  ): { found: true; room: Room } | { found: false } {
    const storedCode = this.playerRoomIndex.get(playerId);
    if (!storedCode || storedCode !== roomCode.toUpperCase()) {
      this.logger.info(
        { event: 'check_presence', result: 'not_found', reason: 'stale_or_wrong_room', playerId, roomCode, storedCode },
        'check_presence: not found',
      );
      return { found: false };
    }

    const room = this.rooms.get(storedCode);
    if (!room) {
      this.logger.info(
        { event: 'check_presence', result: 'not_found', reason: 'room_gone', playerId, roomCode: storedCode },
        'check_presence: not found',
      );
      this.playerRoomIndex.delete(playerId);
      return { found: false };
    }

    const player = room.players.find((p) => p.id === playerId);
    if (!player) {
      this.logger.info(
        { event: 'check_presence', result: 'not_found', reason: 'player_not_in_room', playerId, roomCode: storedCode },
        'check_presence: not found',
      );
      this.playerRoomIndex.delete(playerId);
      return { found: false };
    }

    return { found: true, room };
  }

  // ── Spectators ──────────────────────────────────────────────────────────────
  // Deliberately independent of every player-membership method above: no
  // interaction with MAX_PLAYERS/MIN_PLAYERS, no isHost, no baseTurnOrder
  // implications (spectators never reach GameService at all — see
  // rooms.gateway.ts's spectate_room handler). Unlike joinRoom, spectating is
  // allowed on an already-started room — watching a live game is the primary
  // real use case, not just a lobby.

  spectateRoom(
    roomCode: string,
    displayName: string,
    socketId: string,
  ): { room: Room; spectatorId: string } | { error: string } {
    const room = this.rooms.get(roomCode.toUpperCase());
    if (!room) return { error: 'ROOM_NOT_FOUND' };

    const existingActive = room.spectators.find((s) => s.socketId === socketId && s.isConnected);
    if (existingActive) return { error: 'ALREADY_IN_ROOM' };

    const connected = room.spectators.filter((s) => s.isConnected).length;
    if (connected >= MAX_SPECTATORS) return { error: 'SPECTATORS_FULL' };

    const spectatorId = uuidv4();
    room.spectators.push({ id: spectatorId, displayName, isConnected: true, socketId });
    this.spectatorSocketIndex.set(socketId, { roomCode: room.code, spectatorId });
    this.spectatorRoomIndex.set(spectatorId, room.code);
    return { room, spectatorId };
  }

  /** Explicit, permanent leave — unlike a player, a spectator has no in-progress turn state worth preserving through a "temporary" state. */
  stopSpectating(socketId: string): { room: Room; roomCode: string } | null {
    const entry = this.spectatorSocketIndex.get(socketId);
    if (!entry) return null;

    const { roomCode, spectatorId } = entry;
    const room = this.rooms.get(roomCode);
    this.spectatorSocketIndex.delete(socketId);
    this.spectatorRoomIndex.delete(spectatorId);
    if (!room) return null;

    room.spectators = room.spectators.filter((s) => s.id !== spectatorId);
    return { room, roomCode };
  }

  /** Mirrors handleDisconnect's player path, minus every GameSession-related concern spectators never touch. */
  handleSpectatorDisconnect(socketId: string): { room: Room; roomCode: string; spectatorId: string } | null {
    const entry = this.spectatorSocketIndex.get(socketId);
    if (!entry) return null;
    this.spectatorSocketIndex.delete(socketId);

    const { roomCode, spectatorId } = entry;
    const room = this.rooms.get(roomCode);
    if (!room) return null;

    const spectator = room.spectators.find((s) => s.id === spectatorId);
    if (!spectator) return null;

    spectator.isConnected = false;
    spectator.socketId = null;
    // spectatorRoomIndex kept — they can spectator_reconnect later, same
    // pattern as playerRoomIndex surviving a player's temporary disconnect.
    return { room, roomCode, spectatorId };
  }

  reconnectSpectator(
    roomCode: string,
    spectatorId: string,
    socketId: string,
  ): { room: Room } | { error: string } {
    const room = this.rooms.get(roomCode.toUpperCase());
    if (!room) return { error: 'ROOM_NOT_FOUND' };
    const spectator = room.spectators.find((s) => s.id === spectatorId);
    if (!spectator) return { error: 'PLAYER_NOT_FOUND' };

    if (spectator.socketId) this.spectatorSocketIndex.delete(spectator.socketId);
    spectator.isConnected = true;
    spectator.socketId = socketId;
    this.spectatorSocketIndex.set(socketId, { roomCode: room.code, spectatorId });
    this.spectatorRoomIndex.set(spectatorId, room.code);
    return { room };
  }

  // ── Handle socket disconnect (crash / network drop / close) ───────────────
  // hasActiveSession is resolved by the gateway using gameService before calling this.

  handleDisconnect(
    socketId: string,
    hasActiveSession: boolean,
  ): { room: Room | null; roomCode: string; playerId: string } | null {
    const entry = this.socketIndex.get(socketId);
    if (!entry) return null; // already cleaned up by an explicit event
    this.socketIndex.delete(socketId);

    const { roomCode, playerId } = entry;
    const room = this.rooms.get(roomCode);
    if (!room) return null;

    // Pending requester disconnected — remove request silently
    const pendingIdx = room.pendingJoinRequests.findIndex((r) => r.requestId === playerId);
    if (pendingIdx !== -1) {
      room.pendingJoinRequests.splice(pendingIdx, 1);
      return null;
    }

    const player = room.players.find((p) => p.id === playerId);
    if (!player) return null;

    if (!hasActiveSession) {
      // LOBBY disconnect = permanent removal
      const result = this.permanentlyRemove(room, playerId);
      return { ...result, playerId };
    }

    // GAME disconnect = temporary (player can rejoin via check_presence)
    player.isConnected = false;
    player.socketId = null;

    const allGone = room.players.every((p) => !p.isConnected);
    if (allGone) {
      this._evictAllSpectators(room);
      this.rooms.delete(roomCode);
      for (const p of room.players) this.playerRoomIndex.delete(p.id);
      return { room: null, roomCode, playerId };
    }

    return { room, roomCode, playerId };
  }

  // ── Start game ────────────────────────────────────────────────────────────

  startGame(socketId: string): { room: Room; roomCode: string } | { error: string } {
    const entry = this.socketIndex.get(socketId);
    if (!entry) return { error: 'NOT_IN_ROOM' };

    const { roomCode, playerId } = entry;
    const room = this.rooms.get(roomCode);
    if (!room) return { error: 'ROOM_NOT_FOUND' };

    const player = room.players.find((p) => p.id === playerId);
    if (!player?.isHost) return { error: 'NOT_HOST' };

    const connectedCount = room.players.filter((p) => p.isConnected).length;
    if (connectedCount < MIN_PLAYERS) return { error: 'NOT_ENOUGH_PLAYERS' };

    room.isStarted = true;
    room.lastActivityAt = Date.now();
    return { room, roomCode };
  }

  // ── Bulk cleanup ──────────────────────────────────────────────────────────

  /**
   * Fully delete a room and all associated index entries.
   * Use after game ends or when closing a stale room.
   */
  closeRoom(roomCode: string): void {
    const room = this.rooms.get(roomCode);
    if (!room) return;
    for (const p of room.players) {
      this.playerRoomIndex.delete(p.id);
      if (p.socketId) this.socketIndex.delete(p.socketId);
    }
    this._evictAllSpectators(room);
    this.rooms.delete(roomCode);
  }

  /** Return room codes with no activity since [cutoffMs]. */
  getStaleRooms(cutoffMs: number): string[] {
    const stale: string[] = [];
    for (const [code, room] of this.rooms.entries()) {
      if (room.lastActivityAt < cutoffMs) stale.push(code);
    }
    return stale;
  }
}
