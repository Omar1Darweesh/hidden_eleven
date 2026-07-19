import { Module } from '@nestjs/common';
import { ThrottlerModule } from '@nestjs/throttler';
import { AdminController } from './admin.controller.js';
import { AdminService } from './admin.service.js';
import { BackupService } from './backup.service.js';
import { THROTTLER_CONFIG } from '../shared/throttler-config.js';
import { AdminAuthGuard } from '../shared/admin-auth.guard.js';

@Module({
  // Same shared config RoomsModule uses for its WS guard — ThrottlerModule
  // isn't @Global(), so it must be imported here too for AdminController's
  // @UseGuards(ThrottlerGuard) to have a ThrottlerStorage to inject.
  imports: [ThrottlerModule.forRoot(THROTTLER_CONFIG)],
  controllers: [AdminController],
  providers: [AdminService, AdminAuthGuard, BackupService],
  exports: [AdminService, BackupService],
})
export class AdminModule {}
