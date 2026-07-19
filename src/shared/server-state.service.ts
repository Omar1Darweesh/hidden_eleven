import { Injectable } from '@nestjs/common';

/**
 * Process-wide liveness flag, set once by main.ts's SIGTERM handler
 * (Task 1.6's graceful shutdown sequence) so the /health endpoint (Task 3.4)
 * can report 503 during the drain window — PM2's `health_check_http` then
 * sees the unhealthy response and stops routing/expects the restart, instead
 * of relying solely on the kill_timeout race.
 */
@Injectable()
export class ServerState {
  private _isShuttingDown = false;

  get isShuttingDown(): boolean {
    return this._isShuttingDown;
  }

  markShuttingDown(): void {
    this._isShuttingDown = true;
  }
}
