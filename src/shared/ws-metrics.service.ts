import { Injectable } from '@nestjs/common';

/**
 * Cumulative count of inbound WebSocket messages that reached a
 * @SubscribeMessage handler — incremented from WsSafetyInterceptor
 * (ws-safety.interceptor.ts), the single choke point every gateway handler
 * already passes through, so this required no changes to individual
 * handlers. Exposed via /metrics as a raw counter (not a rate) — same
 * convention as matchesRecorded — so any scraper computes rate() itself over
 * whatever window it cares about, rather than this process guessing one.
 */
@Injectable()
export class WsMetricsService {
  private _messagesTotal = 0;

  recordMessage(): void {
    this._messagesTotal += 1;
  }

  getMessagesTotal(): number {
    return this._messagesTotal;
  }
}
