import { GameService } from './game.service';
import type { Room } from '../rooms/interfaces/room.interface';

/**
 * Covers the pre-start pool-sufficiency gate + rating window. Runs against
 * the real seeded player pool (admin-data/players.json), choosing rating
 * windows whose outcome is unambiguous regardless of the exact dataset:
 *   • full 1–99 range, few players → always enough,
 *   • a 99–99 sliver → never enough for a full 11-position formation.
 */
describe('GameService.checkDraftPoolSufficiency', () => {
  const gs = new GameService();

  function room(overrides: Partial<Room>): Room {
    return {
      code: 'RM1',
      players: [
        { id: 'p1', displayName: 'A', isHost: true, isConnected: true, socketId: 's1' },
        { id: 'p2', displayName: 'B', isHost: false, isConnected: true, socketId: 's2' },
      ],
      spectators: [],
      isStarted: false,
      isLocked: false,
      kickedPlayerIds: [],
      kickedDisplayNames: [],
      pendingJoinRequests: [],
      lastActivityAt: Date.now(),
      leagues: [],
      turnTimerSeconds: null,
      subsTimerSeconds: null,
      abilityTimerSeconds: null,
      formationSlug: null,
      minRating: null,
      maxRating: null,
      tournamentEnabled: false,
      simulationSpeed: 'normal',
      ...overrides,
    } as Room;
  }

  it('reports no shortages for the full rating range with 2 players', () => {
    const shortages = gs.checkDraftPoolSufficiency(room({}));
    expect(shortages).toEqual([]);
  });

  it('reports shortages when the rating window is too narrow (99–99)', () => {
    const shortages = gs.checkDraftPoolSufficiency(
      room({ minRating: 99, maxRating: 99 }),
    );
    expect(shortages.length).toBeGreaterThan(0);
    // Each shortage names a position and quantifies the gap for the UI.
    for (const s of shortages) {
      expect(typeof s.position).toBe('string');
      expect(s.needed).toBeGreaterThan(s.available);
    }
  });

  it('needs more players per position as the room grows (needed scales with count)', () => {
    const twoPlayers = gs.checkDraftPoolSufficiency(
      room({ minRating: 85, maxRating: 99 }),
    );
    const eightPlayers = gs.checkDraftPoolSufficiency(
      room({
        minRating: 85,
        maxRating: 99,
        players: Array.from({ length: 8 }, (_, i) => ({
          id: `p${i}`,
          displayName: `P${i}`,
          isHost: i === 0,
          isConnected: true,
          socketId: `s${i}`,
        })),
      }),
    );
    // A larger room can only ever have >= as many shortages at the same
    // filter (needed grows with player count, available is unchanged).
    expect(eightPlayers.length).toBeGreaterThanOrEqual(twoPlayers.length);
  });
});
