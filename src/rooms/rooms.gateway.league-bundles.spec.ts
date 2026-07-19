import { WebSocket } from 'ws';
import { RoomsService } from './rooms.service';
import { AdminService } from '../admin/admin.service';
import { ErrorCodes } from '../shared/error-codes';
import { RoomsGateway } from './rooms.gateway';
import { GameService } from '../game/game.service';

/**
 * Minimal stub socket for handleCreateRoom — needs OPEN readyState so
 * RoomsGateway.send actually writes (see gateway.send guard).
 */
function makeClient() {
  const frames: Array<{ event: string; data: unknown }> = [];
  const client = {
    id: 'sock-host',
    readyState: WebSocket.OPEN,
    send: (raw: string) => {
      frames.push(JSON.parse(raw) as { event: string; data: unknown });
    },
  };
  return { client: client as never, frames };
}

describe('create_room league bundle resolution', () => {
  let roomsService: RoomsService;
  let gateway: RoomsGateway;
  let adminService: AdminService;

  beforeEach(() => {
    roomsService = new RoomsService();
    adminService = {
      resolveLeagueBundleForRoom: jest.fn(),
    } as unknown as AdminService;
    gateway = new RoomsGateway(roomsService, {} as GameService, adminService);
  });

  afterEach(() => {
    // RoomsGateway starts cleanup/heartbeat intervals in its constructor.
    gateway.onModuleDestroy?.();
  });

  it('rejects ambiguous payload (manual leagues + bundle id)', () => {
    const { client, frames } = makeClient();
    gateway.handleCreateRoom(
      {
        displayName: 'Host',
        leagues: ['Premier League'],
        leagueBundleId: 'bundle-1',
      } as never,
      client,
    );
    expect(frames).toEqual([
      { event: 'error', data: { code: ErrorCodes.AMBIGUOUS_LEAGUES } },
    ]);
  });

  it('creates room with resolved league-name snapshot from bundle id', () => {
    (adminService.resolveLeagueBundleForRoom as jest.Mock).mockReturnValue({
      leagueNames: ['Premier League', 'La Liga'],
      bundle: { id: 'b1', name: 'Top 5 Leagues' },
    });

    const { client, frames } = makeClient();
    gateway.handleCreateRoom(
      {
        displayName: 'Host',
        leagueBundleId: 'b1',
      } as never,
      client,
    );

    expect(adminService.resolveLeagueBundleForRoom).toHaveBeenCalledWith('b1');
    expect(frames.some((f) => f.event === 'room_update')).toBe(true);

    const entry = roomsService as unknown as {
      socketIndex: Map<string, { roomCode: string }>;
      rooms: Map<
        string,
        {
          leagues: string[];
          selectedBundleId?: string | null;
          selectedBundleName?: string | null;
        }
      >;
    };
    const { roomCode } = entry.socketIndex.get('sock-host')!;
    const room = entry.rooms.get(roomCode)!;
    expect(room.leagues).toEqual(['Premier League', 'La Liga']);
    expect(room.selectedBundleId).toBe('b1');
    expect(room.selectedBundleName).toBe('Top 5 Leagues');
  });

  it('manual league selection still works without a bundle id', () => {
    const { client, frames } = makeClient();
    gateway.handleCreateRoom(
      {
        displayName: 'Host',
        leagues: ['Bundesliga'],
      } as never,
      client,
    );
    expect(frames.some((f) => f.event === 'room_update')).toBe(true);
    const entry = roomsService as unknown as {
      socketIndex: Map<string, { roomCode: string }>;
      rooms: Map<
        string,
        { leagues: string[]; selectedBundleId?: string | null }
      >;
    };
    const { roomCode } = entry.socketIndex.get('sock-host')!;
    const room = entry.rooms.get(roomCode)!;
    expect(room.leagues).toEqual(['Bundesliga']);
    expect(room.selectedBundleId ?? null).toBeNull();
  });

  it('invalid bundle id surfaces INVALID_LEAGUE_BUNDLE', () => {
    (adminService.resolveLeagueBundleForRoom as jest.Mock).mockImplementation(
      () => {
        throw new Error('missing');
      },
    );
    const { client, frames } = makeClient();
    gateway.handleCreateRoom(
      { displayName: 'Host', leagueBundleId: 'missing' } as never,
      client,
    );
    expect(frames).toEqual([
      { event: 'error', data: { code: ErrorCodes.INVALID_LEAGUE_BUNDLE } },
    ]);
  });
});
