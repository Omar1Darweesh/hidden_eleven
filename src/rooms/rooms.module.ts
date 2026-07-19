import { Module } from '@nestjs/common';
import { ThrottlerModule } from '@nestjs/throttler';
import { AdminModule } from '../admin/admin.module';
import { GameModule } from '../game/game.module';
import { RoomsGateway } from './rooms.gateway';
import { RoomsService } from './rooms.service';
import { THROTTLER_CONFIG } from '../shared/throttler-config.js';
import { WsMetricsService } from '../shared/ws-metrics.service.js';

@Module({
  imports: [GameModule, AdminModule, ThrottlerModule.forRoot(THROTTLER_CONFIG)],
  providers: [RoomsGateway, RoomsService, WsMetricsService],
  // WsMetricsService exported so HealthModule (which already imports
  // RoomsModule for RoomsService/RoomsGateway) can read the same counter
  // WsSafetyInterceptor increments, without a third module needing to know
  // about it.
  exports: [RoomsGateway, RoomsService, WsMetricsService],
})
export class RoomsModule {}
