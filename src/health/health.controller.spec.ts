import { ServiceUnavailableException } from '@nestjs/common';
import { HealthController } from './health.controller';
import { ServerState } from '../shared/server-state.service';
import { EventLoopMonitorService } from '../shared/event-loop-monitor.service';
import { WsMetricsService } from '../shared/ws-metrics.service';
import { RoomsService } from '../rooms/rooms.service';
import { RoomsGateway } from '../rooms/rooms.gateway';
import { GameService } from '../game/game.service';
import { MatchHistoryService } from '../match-history/match-history.service';

describe('HealthController (Task 3.4)', () => {
  let controller: HealthController;
  let serverState: ServerState;
  let roomsService: RoomsService;
  let roomsGateway: RoomsGateway;
  let gameService: GameService;
  let matchHistoryService: MatchHistoryService;
  let wsMetrics: WsMetricsService;
  let eventLoopMonitor: EventLoopMonitorService;

  beforeEach(() => {
    serverState = new ServerState();
    roomsService = new RoomsService();
    gameService = new GameService();
    matchHistoryService = new MatchHistoryService();
    roomsGateway = new RoomsGateway(roomsService, gameService);
    wsMetrics = new WsMetricsService();
    // Not onModuleInit()'d — no real setInterval/histogram running, so
    // getLastSample() deterministically returns the zeroed default until a
    // test explicitly stubs it, matching how RoomsGateway's own timers are
    // handled in this same file.
    eventLoopMonitor = new EventLoopMonitorService();
    controller = new HealthController(
      serverState,
      roomsService,
      roomsGateway,
      gameService,
      matchHistoryService,
      wsMetrics,
      eventLoopMonitor,
    );
  });

  afterEach(() => {
    // RoomsGateway's constructor arms two setInterval timers (Task 1.7
    // heartbeat + stale-room sweep) — never started via onModuleInit/Nest
    // lifecycle here, so they're cleared directly to avoid leaking open
    // handles across test files (the same pattern used in rooms.gateway.spec.ts).
    roomsGateway.onModuleDestroy();
  });

  describe('GET /health', () => {
    it('returns { status: "ok" } when the server is not shutting down', () => {
      expect(controller.getHealth()).toEqual({ status: 'ok' });
    });

    it('throws a 503 ServiceUnavailableException once ServerState.markShuttingDown() has been called', () => {
      serverState.markShuttingDown();
      expect(() => controller.getHealth()).toThrow(ServiceUnavailableException);
      try {
        controller.getHealth();
      } catch (err) {
        expect((err as ServiceUnavailableException).getStatus()).toBe(503);
      }
    });
  });

  describe('GET /metrics', () => {
    it('reports zeroed counts for a freshly constructed, empty server', () => {
      const metrics = controller.getMetrics();
      expect(metrics.activeRooms).toBe(0);
      expect(metrics.activeSessions).toBe(0);
      expect(metrics.connectedSockets).toBe(0);
      // matchHistoryService here was never onModuleInit()'d (no real DB),
      // matching getMatchCount()'s documented "uninitialized → 0" contract.
      expect(metrics.matchesRecorded).toBe(0);
      expect(typeof metrics.uptimeSeconds).toBe('number');
      expect(metrics.uptimeSeconds).toBeGreaterThanOrEqual(0);
      expect(metrics.nodeVersion).toBe(process.version);
      expect(typeof metrics.memoryMb).toBe('number');
      expect(metrics.memoryMb).toBeGreaterThan(0);
    });

    it('activeRooms reflects RoomsService.getRoomCount() after a real room is created', () => {
      roomsService.createRoom('Alice', 'socket-1');
      expect(controller.getMetrics().activeRooms).toBe(1);
    });

    it('connectedSockets reflects RoomsGateway.getConnectedSocketCount() after a real connection', () => {
      const fakeClient = { id: 'sock-1', on: jest.fn() } as unknown as Parameters<
        RoomsGateway['handleConnection']
      >[0];
      roomsGateway.handleConnection(fakeClient);
      expect(controller.getMetrics().connectedSockets).toBe(1);
    });

    it('matchesRecorded reflects MatchHistoryService.getMatchCount() against a real in-memory DB', () => {
      process.env = { ...process.env, DB_PATH: ':memory:' };
      const realMatchHistory = new MatchHistoryService();
      realMatchHistory.onModuleInit();
      realMatchHistory.recordMatch('ABCDEF', 100, [
        { playerId: 'p1', displayName: 'Alice', score: 50, rank: 1 },
      ]);
      const realController = new HealthController(
        serverState,
        roomsService,
        roomsGateway,
        gameService,
        realMatchHistory,
        wsMetrics,
        eventLoopMonitor,
      );
      expect(realController.getMetrics().matchesRecorded).toBe(1);
      realMatchHistory.onModuleDestroy();
    });

    it('wsMessagesTotal reflects WsMetricsService.recordMessage()', () => {
      wsMetrics.recordMessage();
      wsMetrics.recordMessage();
      expect(controller.getMetrics().wsMessagesTotal).toBe(2);
    });

    it('eventLoopLagMs reflects EventLoopMonitorService.getLastSample()', () => {
      expect(controller.getMetrics().eventLoopLagMs).toEqual({ meanMs: 0, p99Ms: 0, maxMs: 0 });
    });
  });

  describe('GET /health — overload detection (Task 5)', () => {
    it('returns ok when event-loop lag is within the normal range', () => {
      jest.spyOn(eventLoopMonitor, 'getLastSample').mockReturnValue({ meanMs: 5, p99Ms: 20, maxMs: 40 });
      expect(controller.getHealth()).toEqual({ status: 'ok' });
    });

    it('throws a 503 "overloaded" once p99 event-loop lag exceeds the threshold', () => {
      jest.spyOn(eventLoopMonitor, 'getLastSample').mockReturnValue({ meanMs: 100, p99Ms: 900, maxMs: 1200 });
      expect(() => controller.getHealth()).toThrow(ServiceUnavailableException);
      try {
        controller.getHealth();
      } catch (err) {
        expect((err as ServiceUnavailableException).getStatus()).toBe(503);
        expect((err as ServiceUnavailableException).message).toBe('overloaded');
      }
    });

    it('shutting-down takes priority over an overload reading — reports "shutting_down", not "overloaded"', () => {
      serverState.markShuttingDown();
      jest.spyOn(eventLoopMonitor, 'getLastSample').mockReturnValue({ meanMs: 900, p99Ms: 900, maxMs: 900 });
      try {
        controller.getHealth();
        fail('expected getHealth() to throw');
      } catch (err) {
        expect((err as ServiceUnavailableException).message).toBe('shutting_down');
      }
    });
  });
});
