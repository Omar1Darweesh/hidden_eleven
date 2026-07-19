import { RoomsService } from './rooms.service';
import { GameService } from '../game/game.service';

describe('RoomsService — stale-room activity tracking', () => {
  let service: RoomsService;
  const T0 = 1_000_000_000; // arbitrary fixed "now" for deterministic tests
  const ONE_HOUR_MS = 60 * 60 * 1000;

  beforeEach(() => {
    service = new RoomsService();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('marks a room stale once its lastActivityAt is older than the cutoff', () => {
    jest.spyOn(Date, 'now').mockReturnValue(T0);
    const { room } = service.createRoom('Host', 'sock-host');

    // 61 minutes later, with a 60-minute cutoff, the room should show as stale.
    const cutoff = T0 + 61 * 60 * 1000 - ONE_HOUR_MS;
    expect(service.getStaleRooms(cutoff)).toContain(room.code);
  });

  it('touchRoomActivity() refreshes lastActivityAt so the room is no longer stale', () => {
    jest.spyOn(Date, 'now').mockReturnValue(T0);
    const { room } = service.createRoom('Host', 'sock-host');

    // Jump forward 61 minutes — without a touch, this room would be stale.
    const laterNow = T0 + 61 * 60 * 1000;
    jest.spyOn(Date, 'now').mockReturnValue(laterNow);

    // Simulate a gameplay action happening right now.
    service.touchRoomActivity(room.code);

    // Same cutoff as before (60 minutes back from "now") — the room must NOT
    // be reported stale anymore, because touchRoomActivity() just refreshed it.
    const cutoff = laterNow - ONE_HOUR_MS;
    expect(service.getStaleRooms(cutoff)).not.toContain(room.code);
  });

  it('touchRoomActivity() on an unknown room code is a safe no-op', () => {
    expect(() => service.touchRoomActivity('NOPE99')).not.toThrow();
  });

  it('a room genuinely idle past the cutoff (no activity at all) is still reported stale', () => {
    jest.spyOn(Date, 'now').mockReturnValue(T0);
    const { room } = service.createRoom('Host', 'sock-host');

    const laterNow = T0 + 61 * 60 * 1000;
    jest.spyOn(Date, 'now').mockReturnValue(laterNow);
    // No touchRoomActivity() call here — room is genuinely abandoned.

    const cutoff = laterNow - ONE_HOUR_MS;
    expect(service.getStaleRooms(cutoff)).toContain(room.code);
  });
});

/**
 * Room lifecycle tests (Task 2.4 Part B) — the paths hardest to reach in
 * live testing but most dangerous if wrong: every one of these is a real
 * memory-leak vector if `playerRoomIndex`/`socketIndex` aren't kept in
 * lockstep with `rooms` (exactly the class of bug Phase 0's orphaned-session
 * fix was about). Reads the actual current rooms.service.ts source above
 * fresh, not from memory, before writing any of these.
 */
describe('RoomsService — room lifecycle (Task 2.4)', () => {
  let service: RoomsService;

  function indexes(svc: RoomsService) {
    return svc as unknown as {
      rooms: Map<string, unknown>;
      socketIndex: Map<string, unknown>;
      playerRoomIndex: Map<string, string>;
    };
  }

  beforeEach(() => {
    service = new RoomsService();
  });

  it('createRoom → joinRoom → all players disconnect (mid-game) → room is deleted and playerRoomIndex has no stale entries for either player', () => {
    const { room, playerId: hostId } = service.createRoom('Host', 'sock-host');
    const joinResult = service.joinRoom(room.code, 'Player2', 'sock-p2');
    expect('error' in joinResult).toBe(false);
    if ('error' in joinResult) return;
    const p2Id = joinResult.playerId;

    // GAME disconnect (hasActiveSession=true) — temporary at first.
    const first = service.handleDisconnect('sock-host', true);
    expect(first?.room).not.toBeNull(); // player2 still connected — room survives
    expect(service.getRoom(room.code)).toBeDefined();

    // The last connected player disconnects — room becomes fully empty.
    const second = service.handleDisconnect('sock-p2', true);
    expect(second?.room).toBeNull();

    expect(service.getRoom(room.code)).toBeUndefined();
    // Neither player's identity should still resolve to this (or any) room.
    expect(indexes(service).playerRoomIndex.has(hostId)).toBe(false);
    expect(indexes(service).playerRoomIndex.has(p2Id)).toBe(false);
    // Both sockets fully cleared too.
    expect(indexes(service).socketIndex.has('sock-host')).toBe(false);
    expect(indexes(service).socketIndex.has('sock-p2')).toBe(false);
  });

  it('createRoom → joinRoom → startGame → one player disconnects → endSession leaves no entry in GameService\'s session map for that roomCode', () => {
    const gameService = new GameService();
    const { room } = service.createRoom('Host', 'sock-host');
    const joinResult = service.joinRoom(room.code, 'Player2', 'sock-p2');
    expect('error' in joinResult).toBe(false);
    if ('error' in joinResult) return;

    const startResult = service.startGame('sock-host');
    expect('error' in startResult).toBe(false);
    if ('error' in startResult) return;

    const session = gameService.createSession(startResult.room);
    expect(gameService.getSessionByRoomCode(room.code)).toBe(session);

    // Player2 disconnects mid-game — a real game-end decision (forfeit, in
    // the real gateway's _tryEndGame) is what would actually call
    // endSession() here; that decision logic lives in RoomsGateway (already
    // covered in rooms.gateway.spec.ts's orphaned-session tests) — this test
    // is scoped to RoomsService+GameService's own contract: once a caller
    // (the gateway, in production) decides the game is over and calls
    // endSession(), the session map must genuinely be empty afterward, with
    // nothing left to leak.
    service.handleDisconnect('sock-p2', true);
    gameService.endSession(room.code);

    expect(gameService.getSessionByRoomCode(room.code)).toBeUndefined();
  });

  it('closeRoom is idempotent — a second call for the same roomCode is a safe no-op, not a crash', () => {
    const { room, playerId } = service.createRoom('Host', 'sock-host');

    service.closeRoom(room.code);
    expect(service.getRoom(room.code)).toBeUndefined();
    expect(indexes(service).playerRoomIndex.has(playerId)).toBe(false);

    expect(() => service.closeRoom(room.code)).not.toThrow();
    // Still gone, not resurrected or double-removed into some bad state.
    expect(service.getRoom(room.code)).toBeUndefined();
  });

  it('playerRoomIndex reflects only the current room for a socket that joined, left, then joined a different room', () => {
    const { room: roomA, playerId: p1InA } = service.createRoom('Host', 'sock-host');
    expect(indexes(service).playerRoomIndex.get(p1InA)).toBe(roomA.code);

    // Permanent leave (lobby) — roomA had exactly one player, so it's now
    // fully torn down and p1InA's identity is retired entirely (joining
    // again always mints a fresh playerId — there's no persistent "this
    // socket is the same human" identity across a full leave+rejoin).
    service.leaveLobby('sock-host');
    expect(indexes(service).playerRoomIndex.has(p1InA)).toBe(false);
    expect(service.getRoom(roomA.code)).toBeUndefined();

    // The same underlying socket now joins (creates) a brand new room.
    const { room: roomB, playerId: p2InB } = service.createRoom('Host', 'sock-host');
    expect(roomB.code).not.toBe(roomA.code);
    expect(indexes(service).playerRoomIndex.get(p2InB)).toBe(roomB.code);
    // The old identity must not have been resurrected or left dangling.
    expect(indexes(service).playerRoomIndex.has(p1InA)).toBe(false);
  });
});

/**
 * Lobby production-hardening pass — presence/kick/host-transfer/rejoin.
 * Written against the actual current rooms.service.ts (read fresh, not from
 * memory) rather than assuming behavior from older design docs, several of
 * which turned out to already be stale relative to this file.
 */
describe('RoomsService — kick', () => {
  let service: RoomsService;
  beforeEach(() => { service = new RoomsService(); });

  it('a non-host cannot kick anyone', () => {
    const { room } = service.createRoom('Host', 'sock-host');
    const joinResult = service.joinRoom(room.code, 'P2', 'sock-p2');
    if ('error' in joinResult) throw new Error('unexpected join error');
    const p3 = service.joinRoom(room.code, 'P3', 'sock-p3');
    if ('error' in p3) throw new Error('unexpected join error');

    // P2 (not host) tries to kick P3.
    const result = service.kickPlayer('sock-p2', p3.playerId);
    expect('error' in result && result.error).toBe('NOT_HOST');
  });

  it('the host cannot kick themself', () => {
    const { room, playerId: hostId } = service.createRoom('Host', 'sock-host');
    expect(room).toBeDefined();
    const result = service.kickPlayer('sock-host', hostId);
    expect('error' in result && result.error).toBe('CANNOT_KICK_SELF');
  });

  it('host kicks a player: they are removed from players, and playerRoomIndex no longer resolves them', () => {
    const { room } = service.createRoom('Host', 'sock-host');
    const joinResult = service.joinRoom(room.code, 'P2', 'sock-p2');
    if ('error' in joinResult) throw new Error('unexpected join error');
    const p2Id = joinResult.playerId;

    const result = service.kickPlayer('sock-host', p2Id);
    if ('error' in result) throw new Error('unexpected kick error');

    expect(result.room.players.some((p) => p.id === p2Id)).toBe(false);
    expect(result.targetSocketId).toBe('sock-p2');
    expect(service.checkPresence(p2Id, room.code)).toEqual({ found: false });
  });

  it('a kicked player is blocked from rejoining under the same display name, but the room still accepts a different name from anyone else', () => {
    const { room } = service.createRoom('Host', 'sock-host');
    const joinResult = service.joinRoom(room.code, 'Alice', 'sock-alice');
    if ('error' in joinResult) throw new Error('unexpected join error');

    service.kickPlayer('sock-host', joinResult.playerId);

    const rejoinAttempt = service.joinRoom(room.code, 'Alice', 'sock-alice-2');
    expect('error' in rejoinAttempt && rejoinAttempt.error).toBe('KICKED');

    // A display-name match is case-insensitive.
    const rejoinAttemptCased = service.joinRoom(room.code, 'ALICE', 'sock-alice-3');
    expect('error' in rejoinAttemptCased && rejoinAttemptCased.error).toBe('KICKED');

    // An unrelated player under a different name is unaffected.
    const otherJoin = service.joinRoom(room.code, 'Bob', 'sock-bob');
    expect('error' in otherJoin).toBe(false);
  });

  it('kicking the last non-host player leaves a valid single-player room, not a crash', () => {
    const { room } = service.createRoom('Host', 'sock-host');
    const joinResult = service.joinRoom(room.code, 'P2', 'sock-p2');
    if ('error' in joinResult) throw new Error('unexpected join error');

    const result = service.kickPlayer('sock-host', joinResult.playerId);
    if ('error' in result) throw new Error('unexpected kick error');
    expect(result.room.players).toHaveLength(1);
    expect(result.room.players[0].isHost).toBe(true);
  });
});

describe('RoomsService — transferHost', () => {
  let service: RoomsService;
  beforeEach(() => { service = new RoomsService(); });

  it('a non-host cannot transfer host', () => {
    const { room } = service.createRoom('Host', 'sock-host');
    const joinResult = service.joinRoom(room.code, 'P2', 'sock-p2');
    if ('error' in joinResult) throw new Error('unexpected join error');

    const result = service.transferHost('sock-p2', joinResult.playerId);
    expect('error' in result && result.error).toBe('NOT_HOST');
  });

  it('transferring host to yourself is rejected', () => {
    const { room, playerId: hostId } = service.createRoom('Host', 'sock-host');
    expect(room).toBeDefined();
    const result = service.transferHost('sock-host', hostId);
    expect('error' in result && result.error).toBe('ALREADY_HOST');
  });

  it('transferring host to a player who is not in the room is rejected', () => {
    const { room } = service.createRoom('Host', 'sock-host');
    expect(room).toBeDefined();
    const result = service.transferHost('sock-host', 'not-a-real-player-id');
    expect('error' in result && result.error).toBe('PLAYER_NOT_FOUND');
  });

  it('a successful transfer flips isHost on exactly the two players involved', () => {
    const { room, playerId: hostId } = service.createRoom('Host', 'sock-host');
    const joinResult = service.joinRoom(room.code, 'P2', 'sock-p2');
    if ('error' in joinResult) throw new Error('unexpected join error');
    const p2Id = joinResult.playerId;

    const result = service.transferHost('sock-host', p2Id);
    if ('error' in result) throw new Error('unexpected transfer error');

    const oldHost = result.room.players.find((p) => p.id === hostId)!;
    const newHost = result.room.players.find((p) => p.id === p2Id)!;
    expect(oldHost.isHost).toBe(false);
    expect(newHost.isHost).toBe(true);
  });

  it('transferring host to a currently-disconnected player is rejected (would strand the room with no reachable host)', () => {
    const { room } = service.createRoom('Host', 'sock-host');
    const joinResult = service.joinRoom(room.code, 'P2', 'sock-p2');
    if ('error' in joinResult) throw new Error('unexpected join error');
    const p2Id = joinResult.playerId;

    // P2 goes offline (GAME disconnect — temporary, slot preserved).
    service.handleDisconnect('sock-p2', true);
    expect(service.getRoom(room.code)?.players.find((p) => p.id === p2Id)?.isConnected).toBe(false);

    const result = service.transferHost('sock-host', p2Id);
    expect('error' in result && result.error).toBe('TARGET_DISCONNECTED');
    // Host unchanged.
    expect(service.getRoom(room.code)?.players.find((p) => p.isHost)?.id).not.toBe(p2Id);
  });

  it('a player who reconnects becomes a valid host-transfer target again', () => {
    const { room } = service.createRoom('Host', 'sock-host');
    const joinResult = service.joinRoom(room.code, 'P2', 'sock-p2');
    if ('error' in joinResult) throw new Error('unexpected join error');
    const p2Id = joinResult.playerId;

    service.handleDisconnect('sock-p2', true);
    expect('error' in service.transferHost('sock-host', p2Id)).toBe(true);

    service.reconnect(room.code, p2Id, 'sock-p2-new');
    const result = service.transferHost('sock-host', p2Id);
    expect('error' in result).toBe(false);
  });
});

describe('RoomsService — host reassignment on departure', () => {
  let service: RoomsService;
  beforeEach(() => { service = new RoomsService(); });

  it('leaveLobby: when the host leaves, the next remaining player is deterministically promoted (first connected, else first remaining)', () => {
    const { room } = service.createRoom('Host', 'sock-host');
    const p2 = service.joinRoom(room.code, 'P2', 'sock-p2');
    const p3 = service.joinRoom(room.code, 'P3', 'sock-p3');
    if ('error' in p2 || 'error' in p3) throw new Error('unexpected join error');

    const result = service.leaveLobby('sock-host');
    expect(result?.room).not.toBeNull();
    const newHosts = result!.room!.players.filter((p) => p.isHost);
    expect(newHosts).toHaveLength(1);
    // First remaining player (P2, join order) is promoted.
    expect(newHosts[0].id).toBe(p2.playerId);
  });

  it('handleDisconnect (mid-game): the host disconnecting does NOT reassign host — they stay host, just disconnected, until they reconnect or leave permanently', () => {
    // Deliberate design choice (see MULTIPLAYER_ROOMS_DESIGN.md's reconnect
    // section) — a temporary mid-game disconnect must not silently hand host
    // powers to someone else while the original host might come straight
    // back. Host reassignment only ever happens on a PERMANENT departure
    // (leaveLobby/leaveGamePermanently/kickPlayer's shared permanentlyRemove
    // path), never on the "GAME disconnect = temporary" branch of
    // handleDisconnect. This test locks that distinction in.
    const { room, playerId: hostId } = service.createRoom('Host', 'sock-host');
    const p2 = service.joinRoom(room.code, 'P2', 'sock-p2');
    if ('error' in p2) throw new Error('unexpected join error');

    const result = service.handleDisconnect('sock-host', true);

    expect(result?.room).not.toBeNull();
    const host = result!.room!.players.find((p) => p.id === hostId)!;
    expect(host.isHost).toBe(true);
    expect(host.isConnected).toBe(false);
    // No one else was silently promoted.
    expect(result!.room!.players.filter((p) => p.isHost)).toHaveLength(1);
  });

  it('leaveGamePermanently (mid-game): unlike a mere disconnect, the host permanently leaving DOES reassign host to a connected remaining player', () => {
    const { room } = service.createRoom('Host', 'sock-host');
    const p2 = service.joinRoom(room.code, 'P2', 'sock-p2');
    const p3 = service.joinRoom(room.code, 'P3', 'sock-p3');
    if ('error' in p2 || 'error' in p3) throw new Error('unexpected join error');

    // P2 is offline (temporary) when the host leaves permanently.
    service.handleDisconnect('sock-p2', true);
    const result = service.leaveGamePermanently('sock-host');

    expect(result?.room).not.toBeNull();
    const newHost = result!.room!.players.find((p) => p.isHost);
    // P3 (still connected) is promoted over P2 (disconnected) — permanent
    // removal prefers a connected player so the new host can actually act.
    expect(newHost?.id).toBe(p3.playerId);
  });

  it('a room never ends up with zero hosts or more than one host after any departure', () => {
    const { room } = service.createRoom('Host', 'sock-host');
    const p2 = service.joinRoom(room.code, 'P2', 'sock-p2');
    const p3 = service.joinRoom(room.code, 'P3', 'sock-p3');
    if ('error' in p2 || 'error' in p3) throw new Error('unexpected join error');

    service.leaveLobby('sock-host');
    const afterFirstLeave = service.getRoom(room.code)!;
    expect(afterFirstLeave.players.filter((p) => p.isHost)).toHaveLength(1);

    // Whoever is host now leaves too.
    const currentHostSocket = afterFirstLeave.players.find((p) => p.isHost)!.id === p2.playerId
      ? 'sock-p2' : 'sock-p3';
    service.leaveLobby(currentHostSocket);
    const afterSecondLeave = service.getRoom(room.code)!;
    expect(afterSecondLeave.players).toHaveLength(1);
    expect(afterSecondLeave.players[0].isHost).toBe(true);
  });
});

describe('RoomsService — reconnect / checkPresence', () => {
  let service: RoomsService;
  beforeEach(() => { service = new RoomsService(); });

  it('reconnect fails cleanly for a room that no longer exists', () => {
    const result = service.reconnect('NOPE99', 'some-player-id', 'sock-new');
    expect('error' in result && result.error).toBe('ROOM_NOT_FOUND');
  });

  it('reconnect fails cleanly for a player id that is not in the (real) room — e.g. already kicked', () => {
    const { room } = service.createRoom('Host', 'sock-host');
    const result = service.reconnect(room.code, 'not-a-real-player-id', 'sock-new');
    expect('error' in result && result.error).toBe('PLAYER_NOT_FOUND');
  });

  it('reconnect re-associates a new socket with the existing player and marks them connected', () => {
    const { room } = service.createRoom('Host', 'sock-host');
    const joinResult = service.joinRoom(room.code, 'P2', 'sock-p2');
    if ('error' in joinResult) throw new Error('unexpected join error');
    const p2Id = joinResult.playerId;

    service.handleDisconnect('sock-p2', true);
    expect(service.getRoom(room.code)?.players.find((p) => p.id === p2Id)?.isConnected).toBe(false);

    const result = service.reconnect(room.code, p2Id, 'sock-p2-new');
    if ('error' in result) throw new Error('unexpected reconnect error');
    const reconnected = result.room.players.find((p) => p.id === p2Id)!;
    expect(reconnected.isConnected).toBe(true);
    expect(reconnected.socketId).toBe('sock-p2-new');
    // The new socket resolves back to this player/room.
    expect(service.getSocketEntry('sock-p2-new')).toEqual({ roomCode: room.code, playerId: p2Id });
  });

  it('checkPresence: not found when the stored room for this playerId does not match the room code supplied (stale or wrong room)', () => {
    const { room: roomA } = service.createRoom('Host', 'sock-host');
    const { room: roomB, playerId: otherPlayerId } = service.createRoom('Host2', 'sock-host2');
    expect(roomA.code).not.toBe(roomB.code);

    // otherPlayerId genuinely belongs to roomB, not roomA.
    expect(service.checkPresence(otherPlayerId, roomA.code)).toEqual({ found: false });
  });

  it('checkPresence: not found (and index cleaned up) once the room has been fully closed', () => {
    const { room, playerId } = service.createRoom('Host', 'sock-host');
    service.closeRoom(room.code);
    expect(service.checkPresence(playerId, room.code)).toEqual({ found: false });
  });

  it('checkPresence: found for a genuinely still-live player/room pair', () => {
    const { room, playerId } = service.createRoom('Host', 'sock-host');
    const result = service.checkPresence(playerId, room.code);
    expect(result.found).toBe(true);
  });
});

/**
 * lockRoom/unlockRoom + the approve_join/reject_join flow they gate — had
 * zero test coverage anywhere in the suite before this pass, despite being
 * core lobby-moderation behavior. Covers the full locked-room round trip:
 * lock → join becomes pending → host approves/rejects it, plus the
 * host-only and stale-request guards on each step.
 */
describe('RoomsService — lock/unlock room and the locked-room join-request flow', () => {
  let service: RoomsService;
  beforeEach(() => { service = new RoomsService(); });

  it('a non-host cannot lock or unlock the room', () => {
    const { room } = service.createRoom('Host', 'sock-host');
    const joinResult = service.joinRoom(room.code, 'P2', 'sock-p2');
    if ('error' in joinResult) throw new Error('unexpected join error');

    expect('error' in service.lockRoom('sock-p2') && (service.lockRoom('sock-p2') as { error: string }).error).toBe('NOT_HOST');
    expect('error' in service.unlockRoom('sock-p2') && (service.unlockRoom('sock-p2') as { error: string }).error).toBe('NOT_HOST');
  });

  it('locking the room turns a subsequent join_room into a pending request instead of a direct join', () => {
    const { room } = service.createRoom('Host', 'sock-host');
    const lockResult = service.lockRoom('sock-host');
    if ('error' in lockResult) throw new Error('unexpected lock error');
    expect(lockResult.room.isLocked).toBe(true);

    const joinResult = service.joinRoom(room.code, 'P2', 'sock-p2');
    expect('pending' in joinResult).toBe(true);
    if (!('pending' in joinResult)) return;
    expect(joinResult.hostSocketId).toBe('sock-host');
    // Not actually seated yet — no direct player entry for them.
    expect(service.getRoom(room.code)?.players).toHaveLength(1);
  });

  it('unlocking the room restores direct joins', () => {
    const { room } = service.createRoom('Host', 'sock-host');
    service.lockRoom('sock-host');
    const unlockResult = service.unlockRoom('sock-host');
    if ('error' in unlockResult) throw new Error('unexpected unlock error');
    expect(unlockResult.room.isLocked).toBe(false);

    const joinResult = service.joinRoom(room.code, 'P2', 'sock-p2');
    expect('pending' in joinResult).toBe(false);
    expect('error' in joinResult).toBe(false);
  });

  it('approveJoin: a non-host real player cannot approve someone else\'s pending request', () => {
    const { room } = service.createRoom('Host', 'sock-host');
    // P2 seats normally, before the room locks.
    const p2Join = service.joinRoom(room.code, 'P2', 'sock-p2');
    if ('error' in p2Join || 'pending' in p2Join) throw new Error('expected a direct join');

    service.lockRoom('sock-host');
    const p3Request = service.joinRoom(room.code, 'P3', 'sock-p3');
    if (!('pending' in p3Request)) throw new Error('expected a pending request');

    const result = service.approveJoin('sock-p2', p3Request.request.requestId);
    expect('error' in result && result.error).toBe('NOT_HOST');
  });

  it('approveJoin: a socket with no room membership at all (e.g. the requester itself) cannot approve its own request', () => {
    const { room } = service.createRoom('Host', 'sock-host');
    service.lockRoom('sock-host');
    const joinResult = service.joinRoom(room.code, 'P2', 'sock-p2');
    if (!('pending' in joinResult)) throw new Error('expected a pending request');

    // The pending requester's own socket resolves to a pseudo playerId
    // (the requestId itself) that never matches any real seated player —
    // so this correctly fails as NOT_HOST (no real player found for that
    // id), not NOT_IN_ROOM (the socket IS indexed, just not as a player).
    const result = service.approveJoin('sock-p2', joinResult.request.requestId);
    expect('error' in result && result.error).toBe('NOT_HOST');
  });

  it('approveJoin: an unknown/already-resolved requestId is rejected cleanly, not a crash', () => {
    const { room } = service.createRoom('Host', 'sock-host');
    expect(room).toBeDefined();
    const result = service.approveJoin('sock-host', 'not-a-real-request-id');
    expect('error' in result && result.error).toBe('REQUEST_NOT_FOUND');
  });

  it('approveJoin: seats the requester as a real player and the request cannot be approved twice', () => {
    const { room } = service.createRoom('Host', 'sock-host');
    service.lockRoom('sock-host');
    const joinResult = service.joinRoom(room.code, 'P2', 'sock-p2');
    if (!('pending' in joinResult)) throw new Error('expected a pending request');

    const approveResult = service.approveJoin('sock-host', joinResult.request.requestId);
    if ('error' in approveResult) throw new Error('unexpected approve error');
    expect(approveResult.room.players.some((p) => p.id === approveResult.playerId)).toBe(true);
    expect(approveResult.approvedSocketId).toBe('sock-p2');

    // Same requestId again — already consumed.
    const secondAttempt = service.approveJoin('sock-host', joinResult.request.requestId);
    expect('error' in secondAttempt && secondAttempt.error).toBe('REQUEST_NOT_FOUND');
  });

  it('approveJoin: re-checks room capacity at approval time — two requests queued while the room had exactly one free slot cannot BOTH be approved', () => {
    // Cross-phase-cleanup pass: joinRoom already checks capacity when a
    // request is first QUEUED, but approveJoin never re-checked it at
    // approval time. Two requests can each pass that initial check while
    // the room still has room for ONE of them (9/10 connected), then both
    // get approved in sequence, pushing the room to 11 — over MAX_PLAYERS.
    const { room } = service.createRoom('Host', 'sock-host');
    // Fill to 9 connected players (host + 8 more), then lock.
    for (let i = 2; i <= 9; i++) {
      const r = service.joinRoom(room.code, `P${i}`, `sock-p${i}`);
      if ('error' in r || 'pending' in r) throw new Error(`unexpected join error for P${i}`);
    }
    expect(service.getRoom(room.code)!.players).toHaveLength(9);
    service.lockRoom('sock-host');

    // Both requests are queued while there's still exactly 1 free slot —
    // joinRoom's own capacity check (9 < 10) lets both through.
    const reqA = service.joinRoom(room.code, 'RequesterA', 'sock-a');
    const reqB = service.joinRoom(room.code, 'RequesterB', 'sock-b');
    if (!('pending' in reqA) || !('pending' in reqB)) throw new Error('expected both to be pending');

    const approveA = service.approveJoin('sock-host', reqA.request.requestId);
    if ('error' in approveA) throw new Error('unexpected error approving the first request');
    expect(service.getRoom(room.code)!.players).toHaveLength(10);

    // The room is now full — approving the SECOND request must be rejected,
    // not silently pushed through to 11 players.
    const approveB = service.approveJoin('sock-host', reqB.request.requestId);
    expect('error' in approveB && approveB.error).toBe('ROOM_FULL');
    expect(service.getRoom(room.code)!.players).toHaveLength(10); // unchanged

    // The rejected request is left in the queue (not silently dropped) —
    // the host can still act on it later (e.g. once a slot frees up), or
    // reject it explicitly.
    expect(
      service.getRoom(room.code)!.pendingJoinRequests.some((r) => r.requestId === reqB.request.requestId),
    ).toBe(true);
  });

  it('rejectJoin: removes the pending request without seating the requester, and it cannot be rejected twice', () => {
    const { room } = service.createRoom('Host', 'sock-host');
    service.lockRoom('sock-host');
    const joinResult = service.joinRoom(room.code, 'P2', 'sock-p2');
    if (!('pending' in joinResult)) throw new Error('expected a pending request');

    const rejectResult = service.rejectJoin('sock-host', joinResult.request.requestId);
    if ('error' in rejectResult) throw new Error('unexpected reject error');
    expect(rejectResult.rejectedSocketId).toBe('sock-p2');
    expect(service.getRoom(room.code)?.players).toHaveLength(1);

    const secondAttempt = service.rejectJoin('sock-host', joinResult.request.requestId);
    expect('error' in secondAttempt && secondAttempt.error).toBe('REQUEST_NOT_FOUND');
  });
});

describe('RoomsService — simulationSpeed (host pacing setting)', () => {
  let service: RoomsService;
  beforeEach(() => { service = new RoomsService(); });

  it('defaults to "normal" when the host does not choose a speed', () => {
    const { room } = service.createRoom('Host', 'sock-host');
    expect(room.simulationSpeed).toBe('normal');
  });

  it('preserves an explicit host choice of "fast" or "slow"', () => {
    const { room: fastRoom } = service.createRoom(
      'Host', 'sock-1', [], null, null, null, false, 'fast',
    );
    expect(fastRoom.simulationSpeed).toBe('fast');

    const { room: slowRoom } = service.createRoom(
      'Host', 'sock-2', [], null, null, null, false, 'slow',
    );
    expect(slowRoom.simulationSpeed).toBe('slow');
  });
});
