import { Module } from '@nestjs/common';
import { HealthController } from './health.controller.js';
import { ServerState } from '../shared/server-state.service.js';
import { EventLoopMonitorService } from '../shared/event-loop-monitor.service.js';
import { RoomsModule } from '../rooms/rooms.module.js';
import { GameModule } from '../game/game.module.js';
import { MatchHistoryModule } from '../match-history/match-history.module.js';
import { AdminAuthGuard } from '../shared/admin-auth.guard.js';

@Module({
  imports: [RoomsModule, GameModule, MatchHistoryModule],
  controllers: [HealthController],
  providers: [ServerState, EventLoopMonitorService, AdminAuthGuard],
  exports: [ServerState],
})
export class HealthModule {}
