import { Module } from '@nestjs/common';
import { ThrottlerModule } from '@nestjs/throttler';
import { ScheduleModule } from '@nestjs/schedule';
import { LoggerModule } from 'nestjs-pino';
import { RoomsModule } from './rooms/rooms.module.js';
import { AdminModule } from './admin/admin.module.js';
import { MatchHistoryModule } from './match-history/match-history.module.js';
import { HealthModule } from './health/health.module.js';
import { THROTTLER_CONFIG } from './shared/throttler-config.js';
import { LOGGER_CONFIG } from './shared/logger-config.js';

@Module({
  imports: [
    LoggerModule.forRoot(LOGGER_CONFIG),
    ThrottlerModule.forRoot(THROTTLER_CONFIG),
    // Enables @Cron()-decorated methods anywhere in the app (currently just
    // BackupService's daily backup) — must be imported once, at the root.
    ScheduleModule.forRoot(),
    RoomsModule,
    AdminModule,
    // Also imported by GameModule (so GameService can inject
    // MatchHistoryService) — listed here too, explicitly, so the REST
    // controller's registration doesn't depend on that transitive path
    // staying intact. Nest dedupes a module imported more than once.
    MatchHistoryModule,
    // /health + /metrics (Task 3.4) — needs RoomsModule/GameModule/
    // MatchHistoryModule for its counts, ServerState for liveness.
    HealthModule,
  ],
})
export class AppModule {}
