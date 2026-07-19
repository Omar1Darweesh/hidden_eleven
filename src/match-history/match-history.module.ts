import { Module } from '@nestjs/common';
import { ThrottlerModule } from '@nestjs/throttler';
import { MatchHistoryController } from './match-history.controller.js';
import { MatchHistoryService } from './match-history.service.js';
import { THROTTLER_CONFIG } from '../shared/throttler-config.js';

@Module({
  imports: [ThrottlerModule.forRoot(THROTTLER_CONFIG)],
  controllers: [MatchHistoryController],
  providers: [MatchHistoryService],
  exports: [MatchHistoryService],
})
export class MatchHistoryModule {}
