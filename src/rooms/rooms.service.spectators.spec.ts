import { RoomsService } from './rooms.service';

/**
 * Spectator lifecycle coverage (multiplayer-rooms step 2 — see
 * MULTIPLAYER_ROOMS_DESIGN.md, section B). Spectators are tracked in a
 * completely separate list/index from players (Room.spectators,
 * spectatorSocketIndex/spectatorRoomIndex) specifically so a spectator's
 * socket can never resolve via getSocketEntry() — the guard every gameplay
 * @SubscribeMessage handler already has. These tests exercise the service
 * layer directly; the "spectator gameplay actions are rejected" guarantee
 * itself is proven structurally below (getSocketEntry returns undefined for
 * a spectator socket), not by re-testing every individual gameplay handler.
 */
describe('RoomsService — spectators (multiplayer-rooms step 2)', () => {
  let service: RoomsService;

  function indexes(svc: RoomsService) {
    return svc as unknown as {
      rooms: Map<string, unknown>;
      socketIndex: Map<string, unknown>;
      spectatorSocketIndex: Map<string, unknown>;
      spectatorRoomIndex: Map<string, string>;
    };
  }

  beforeEach(() => {
    service = new RoomsService();
  });

  it('spectateRoom succeeds and does not consume a player slot', () => {
    const { room } = service.createRoom('Host', 'sock-host');

    const result = service.spectateRoom(room.code, 'Watcher', 'sock-spec-1');

    expect('error' in result).toBe(false);
    if ('error' in result) return;
    expect(result.room.spectators).toHaveLength(1);
    expect(result.room.spectators[0].displayName).toBe('Watcher');
    // The player list is completely untouched — this is the core guarantee.
    expect(result.room.players).toHaveLength(1);
    expect(result.room.players.some((p) => p.displayName === 'Watcher')).toBe(false);
  });

  it('spectateRoom works on an ALREADY-STARTED room — unlike joinRoom, which rejects with ROOM_STARTED', () => {
    const { room, playerId: hostId } = service.createRoom('Host', 'sock-host');
    service.joinRoom(room.code, 'Guest', 'sock-guest');
    service.startGame('sock-host');
    expect(service.getRoom(room.code)!.isStarted).toBe(true);

    const spectateResult = service.spectateRoom(room.code, 'Watcher', 'sock-spec-1');
    expect('error' in spectateResult).toBe(false);

    // Confirm joinRoom really would have rejected the same room right now —
    // proving the distinction is intentional, not an oversight.
    const joinResult = service.joinRoom(room.code, 'LateJoiner', 'sock-late');
    expect(joinResult).toEqual({ error: 'ROOM_STARTED' });
    void hostId;
  });

  it('spectateRoom on an unknown room returns ROOM_NOT_FOUND', () => {
    expect(service.spectateRoom('NOPE99', 'Watcher', 'sock-spec-1')).toEqual({ error: 'ROOM_NOT_FOUND' });
  });

  it('a spectator socket never resolves via getSocketEntry — the exact mechanism that keeps every gameplay handler rejecting them', () => {
    const { room } = service.createRoom('Host', 'sock-host');
    const result = service.spectateRoom(room.code, 'Watcher', 'sock-spec-1');
    expect('error' in result).toBe(false);

    // This is the real guardrail: every @SubscribeMessage gameplay handler
    // calls getSocketEntry(client.id) first and rejects with NOT_IN_ROOM if
    // it's undefined. A spectator's socket must never be found here.
    expect(service.getSocketEntry('sock-spec-1')).toBeUndefined();
    // The player socket, for contrast, resolves normally.
    expect(service.getSocketEntry('sock-host')).toBeDefined();
  });

  it('getSocketIds includes both player and spectator sockets; getSpectatorSocketIds returns spectators only', () => {
    const { room } = service.createRoom('Host', 'sock-host');
    service.joinRoom(room.code, 'Guest', 'sock-guest');
    service.spectateRoom(room.code, 'Watcher', 'sock-spec-1');

    expect(service.getSocketIds(room.code).sort()).toEqual(['sock-guest', 'sock-host', 'sock-spec-1'].sort());
    expect(service.getSpectatorSocketIds(room.code)).toEqual(['sock-spec-1']);
  });

  it('stopSpectating removes the spectator cleanly with no leaked index entries', () => {
    const { room } = service.createRoom('Host', 'sock-host');
    const spectateResult = service.spectateRoom(room.code, 'Watcher', 'sock-spec-1');
    expect('error' in spectateResult).toBe(false);
    if ('error' in spectateResult) return;
    const spectatorId = spectateResult.spectatorId;

    const result = service.stopSpectating('sock-spec-1');
    expect(result?.room.spectators).toHaveLength(0);

    const idx = indexes(service);
    expect(idx.spectatorSocketIndex.has('sock-spec-1')).toBe(false);
    expect(idx.spectatorRoomIndex.has(spectatorId)).toBe(false);
  });

  it('stopSpectating on a socket that never spectated is a safe no-op', () => {
    expect(service.stopSpectating('sock-never-spectated')).toBeNull();
  });

  it('handleSpectatorDisconnect marks disconnected but keeps the spectator reconnectable, then reconnectSpectator restores them on a new socket', () => {
    const { room } = service.createRoom('Host', 'sock-host');
    const spectateResult = service.spectateRoom(room.code, 'Watcher', 'sock-spec-1');
    expect('error' in spectateResult).toBe(false);
    if ('error' in spectateResult) return;
    const spectatorId = spectateResult.spectatorId;

    const disconnectResult = service.handleSpectatorDisconnect('sock-spec-1');
    expect(disconnectResult).not.toBeNull();
    const disconnectedSpectator = disconnectResult!.room.spectators.find((s) => s.id === spectatorId);
    expect(disconnectedSpectator?.isConnected).toBe(false);
    expect(disconnectedSpectator?.socketId).toBeNull();
    // Still present in the room (not removed) — this is what makes reconnect possible.
    expect(disconnectResult!.room.spectators).toHaveLength(1);

    const reconnectResult = service.reconnectSpectator(room.code, spectatorId, 'sock-spec-1-new');
    expect('error' in reconnectResult).toBe(false);
    if ('error' in reconnectResult) return;
    const reconnected = reconnectResult.room.spectators.find((s) => s.id === spectatorId);
    expect(reconnected?.isConnected).toBe(true);
    expect(reconnected?.socketId).toBe('sock-spec-1-new');
    expect(service.getSocketEntry('sock-spec-1-new')).toBeUndefined(); // still structurally invisible to gameplay
  });

  it('reconnectSpectator with an unknown spectatorId is rejected', () => {
    const { room } = service.createRoom('Host', 'sock-host');
    const result = service.reconnectSpectator(room.code, 'not-a-real-id', 'sock-new');
    expect(result).toEqual({ error: 'PLAYER_NOT_FOUND' });
  });

  it('handleSpectatorDisconnect on a socket that was never spectating is a safe no-op', () => {
    expect(service.handleSpectatorDisconnect('sock-never-spectated')).toBeNull();
  });

  it('the SPECTATORS_FULL cap is enforced independently of MAX_PLAYERS', () => {
    const { room } = service.createRoom('Host', 'sock-host');
    for (let i = 0; i < 50; i++) {
      const r = service.spectateRoom(room.code, `Watcher${i}`, `sock-spec-${i}`);
      expect('error' in r).toBe(false);
    }
    const overflow = service.spectateRoom(room.code, 'OneTooMany', 'sock-spec-overflow');
    expect(overflow).toEqual({ error: 'SPECTATORS_FULL' });
  });

  it('when the last player disconnects and the room is deleted, all spectators are evicted with no leaked index entries', () => {
    const { room } = service.createRoom('Host', 'sock-host');
    const spectateResult = service.spectateRoom(room.code, 'Watcher', 'sock-spec-1');
    expect('error' in spectateResult).toBe(false);
    if ('error' in spectateResult) return;
    const spectatorId = spectateResult.spectatorId;

    // hasActiveSession=true so this goes through the "temporary disconnect,
    // then allGone deletes the room" path rather than instant permanent removal.
    const disconnectResult = service.handleDisconnect('sock-host', true);
    expect(disconnectResult?.room).toBeNull();
    expect(service.getRoom(room.code)).toBeUndefined();

    const idx = indexes(service);
    expect(idx.spectatorSocketIndex.has('sock-spec-1')).toBe(false);
    expect(idx.spectatorRoomIndex.has(spectatorId)).toBe(false);
  });

  it('when the last player leaves permanently, all spectators are evicted with no leaked index entries', () => {
    const { room, playerId } = service.createRoom('Host', 'sock-host');
    const spectateResult = service.spectateRoom(room.code, 'Watcher', 'sock-spec-1');
    expect('error' in spectateResult).toBe(false);
    if ('error' in spectateResult) return;
    const spectatorId = spectateResult.spectatorId;

    const result = service.leaveGamePermanently('sock-host', playerId, room.code);
    expect(result?.room).toBeNull();

    const idx = indexes(service);
    expect(idx.spectatorSocketIndex.has('sock-spec-1')).toBe(false);
    expect(idx.spectatorRoomIndex.has(spectatorId)).toBe(false);
  });
});
