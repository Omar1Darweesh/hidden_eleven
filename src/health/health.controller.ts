import { Controller, Get, ServiceUnavailableException, UseGuards } from '@nestjs/common';
import { ServerState } from '../shared/server-state.service.js';
import { EventLoopMonitorService, EventLoopLagSample } from '../shared/event-loop-monitor.service.js';
import { RoomsService } from '../rooms/rooms.service.js';
import { RoomsGateway } from '../rooms/rooms.gateway.js';
import { GameService } from '../game/game.service.js';
import { MatchHistoryService } from '../match-history/match-history.service.js';
import { WsMetricsService } from '../shared/ws-metrics.service.js';
import { AdminAuthGuard } from '../shared/admin-auth.guard.js';

export interface Metrics {
  activeRooms: number;
  activeSessions: number;
  connectedSockets: number;
  matchesRecorded: number;
  uptimeSeconds: number;
  nodeVersion: string;
  memoryMb: number;
  wsMessagesTotal: number;
  eventLoopLagMs: EventLoopLagSample;
}

// The process is CPU-bound and falling behind its own event loop, not just
// "busy" — see event-loop-monitor.service.ts's docstring for the load-test
// finding that motivated tracking this at all. p99, not mean, because a
// process can have a perfectly fine mean while regularly stalling for a
// player-visible moment; the mean alone would hide exactly the symptom this
// exists to catch.
const OVERLOAD_P99_LAG_MS = 500;

@Controller()
export class HealthController {
  constructor(
    private readonly serverState: ServerState,
    private readonly roomsService: RoomsService,
    private readonly roomsGateway: RoomsGateway,
    private readonly gameService: GameService,
    private readonly matchHistoryService: MatchHistoryService,
    private readonly wsMetrics: WsMetricsService,
    private readonly eventLoopMonitor: EventLoopMonitorService,
  ) {}

  /**
   * Liveness probe — PM2's `health_check_http` (ecosystem.config.js, Task
   * 3.4) polls this. Returns 503 for two distinct reasons a caller should
   * treat differently:
   *   - `shutting_down`: the SIGTERM drain window is in progress (main.ts) —
   *     expected, temporary, resolves itself once the process exits.
   *   - `overloaded`: the event loop is measurably falling behind
   *     (p99 lag over the last 5s window > OVERLOAD_P99_LAG_MS) — the
   *     process is still alive and will keep serving already-open
   *     connections, but a load balancer should stop routing NEW traffic
   *     here until it recovers, and this is worth paging on if it persists
   *     across several consecutive checks (a single 503 here is not itself
   *     an incident — see LOAD_TEST_RESULTS.md's alerting section).
   */
  @Get('health')
  getHealth(): { status: 'ok' } {
    if (this.serverState.isShuttingDown) {
      throw new ServiceUnavailableException('shutting_down');
    }
    const lag = this.eventLoopMonitor.getLastSample();
    if (lag.p99Ms > OVERLOAD_P99_LAG_MS) {
      throw new ServiceUnavailableException('overloaded');
    }
    return { status: 'ok' };
  }

  /**
   * Operational metrics — admin-authenticated when ADMIN_API_KEY is set.
   * /health stays public for load balancers and uptime monitors.
   */
  @UseGuards(AdminAuthGuard)
  @Get('metrics')
  getMetrics(): Metrics {
    const mem = process.memoryUsage();
    return {
      activeRooms: this.roomsService.getRoomCount(),
      activeSessions: this.gameService.getActiveSessionCount(),
      connectedSockets: this.roomsGateway.getConnectedSocketCount(),
      matchesRecorded: this.matchHistoryService.getMatchCount(),
      uptimeSeconds: Math.floor(process.uptime()),
      nodeVersion: process.version,
      memoryMb: Math.round(mem.rss / (1024 * 1024)),
      wsMessagesTotal: this.wsMetrics.getMessagesTotal(),
      eventLoopLagMs: this.eventLoopMonitor.getLastSample(),
    };
  }
}
