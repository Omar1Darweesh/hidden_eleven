import { MatchHistoryController } from './match-history.controller';
import { MatchHistoryService } from './match-history.service';

describe('MatchHistoryController (Task 2.3)', () => {
  let controller: MatchHistoryController;
  let service: MatchHistoryService;
  const ORIGINAL_ENV = process.env;

  beforeEach(() => {
    process.env = { ...ORIGINAL_ENV, DB_PATH: ':memory:' };
    service = new MatchHistoryService();
    service.onModuleInit();
    controller = new MatchHistoryController(service);
  });

  afterEach(() => {
    service.onModuleDestroy();
    process.env = ORIGINAL_ENV;
  });

  it('GET /api/matches/recent returns the expected shape', () => {
    service.recordMatch('ABCDEF', 600, [
      { playerId: 'p1', displayName: 'Alice', score: 90, rank: 1 },
    ]);

    const result = controller.getRecent();

    expect(Array.isArray(result)).toBe(true);
    expect(result[0]).toMatchObject({
      roomCode: 'ABCDEF',
      durationSeconds: 600,
      playerCount: 1,
      results: [{ playerId: 'p1', displayName: 'Alice', score: 90, rank: 1 }],
    });
  });

  it('respects a valid ?limit query param', () => {
    for (let i = 0; i < 5; i++) {
      service.recordMatch(`ROOM${i}`, 100, [{ playerId: 'p1', displayName: 'Alice', score: 50, rank: 1 }]);
    }

    expect(controller.getRecent('2')).toHaveLength(2);
  });

  it('falls back to the default limit (20) for a missing, malformed, or non-positive ?limit', () => {
    for (let i = 0; i < 3; i++) {
      service.recordMatch(`ROOM${i}`, 100, [{ playerId: 'p1', displayName: 'Alice', score: 50, rank: 1 }]);
    }

    expect(controller.getRecent(undefined)).toHaveLength(3);
    expect(controller.getRecent('not-a-number')).toHaveLength(3);
    expect(controller.getRecent('-1')).toHaveLength(3);
    expect(controller.getRecent('0')).toHaveLength(3);
  });
});
