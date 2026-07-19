import { ThrottlerModuleOptions, seconds } from '@nestjs/throttler';

/**
 * Shared so AppModule and RoomsModule both register the exact same default
 * throttler — ThrottlerModule isn't a @Global() module, so it must be
 * imported wherever its providers are consumed (RoomsGateway, via
 * WsThrottlerGuard), and AppModule also imports it directly per the task
 * spec. A generous connection-wide baseline (30 calls/10s on any handler);
 * the genuinely sensitive endpoints (create_room, reconnect, check_presence)
 * layer a much tighter @Throttle() override on top — see rooms.gateway.ts.
 *
 * Join/spectate/reconnect also get a per-IP bucket inside WsThrottlerGuard
 * (15/60s join+spectate, 30/60s reconnect family) so opening a new socket
 * cannot reset room-code guessing counters.
 */
export const THROTTLER_CONFIG: ThrottlerModuleOptions = {
  throttlers: [{ name: 'default', limit: 30, ttl: seconds(10) }],
};
