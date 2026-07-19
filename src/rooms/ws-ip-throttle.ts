/**
 * Per-IP rate limits for room-access WebSocket events.
 * Complements the per-socket WsThrottlerGuard bucket so opening a new
 * socket cannot reset room-code guessing / reconnect-storm counters.
 *
 * Kept as a plain module (not Nest DI) so unit tests can drive it without
 * spinning up ThrottlerStorageService.
 */

export const IP_THROTTLED_EVENTS = new Set([
  'join_room',
  'spectate_room',
  'reconnect',
  'check_presence',
  'spectator_reconnect',
]);

/** join/spectate: room-code guessing. reconnect family: reconnect storms. */
export const IP_EVENT_LIMITS: Record<string, { limit: number; ttlMs: number }> = {
  join_room: { limit: 15, ttlMs: 60_000 },
  spectate_room: { limit: 15, ttlMs: 60_000 },
  reconnect: { limit: 30, ttlMs: 60_000 },
  check_presence: { limit: 30, ttlMs: 60_000 },
  spectator_reconnect: { limit: 30, ttlMs: 60_000 },
};

type Bucket = { count: number; resetAt: number };

const buckets = new Map<string, Bucket>();

/** @internal test helper */
export function resetIpThrottleBuckets(): void {
  buckets.clear();
}

/**
 * Returns true when the request is allowed, false when the IP is over limit.
 * No-ops (always allows) for events that are not IP-throttled.
 */
export function consumeIpEvent(
  eventName: string,
  clientIp: string,
  nowMs: number = Date.now(),
): boolean {
  if (!IP_THROTTLED_EVENTS.has(eventName)) return true;
  const rule = IP_EVENT_LIMITS[eventName];
  const key = `${eventName}:${clientIp || 'unknown'}`;
  let bucket = buckets.get(key);
  if (!bucket || nowMs >= bucket.resetAt) {
    bucket = { count: 0, resetAt: nowMs + rule.ttlMs };
    buckets.set(key, bucket);
  }
  bucket.count += 1;
  return bucket.count <= rule.limit;
}
