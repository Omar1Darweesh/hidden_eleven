import {
  consumeIpEvent,
  resetIpThrottleBuckets,
  IP_EVENT_LIMITS,
} from './ws-ip-throttle';

describe('ws-ip-throttle', () => {
  beforeEach(() => resetIpThrottleBuckets());

  it('allows a normal join_room flow under the limit', () => {
    const t0 = 1_000_000;
    for (let i = 0; i < IP_EVENT_LIMITS.join_room.limit; i++) {
      expect(consumeIpEvent('join_room', '203.0.113.1', t0)).toBe(true);
    }
  });

  it('blocks excessive join_room attempts from one IP', () => {
    const t0 = 1_000_000;
    const limit = IP_EVENT_LIMITS.join_room.limit;
    for (let i = 0; i < limit; i++) {
      expect(consumeIpEvent('join_room', '203.0.113.1', t0)).toBe(true);
    }
    expect(consumeIpEvent('join_room', '203.0.113.1', t0)).toBe(false);
  });

  it('does not share buckets across IPs', () => {
    const t0 = 1_000_000;
    const limit = IP_EVENT_LIMITS.join_room.limit;
    for (let i = 0; i < limit; i++) {
      consumeIpEvent('join_room', '203.0.113.1', t0);
    }
    expect(consumeIpEvent('join_room', '203.0.113.1', t0)).toBe(false);
    expect(consumeIpEvent('join_room', '203.0.113.2', t0)).toBe(true);
  });

  it('resets after the TTL window', () => {
    const t0 = 1_000_000;
    const limit = IP_EVENT_LIMITS.spectate_room.limit;
    for (let i = 0; i < limit; i++) {
      consumeIpEvent('spectate_room', '203.0.113.5', t0);
    }
    expect(consumeIpEvent('spectate_room', '203.0.113.5', t0)).toBe(false);
    expect(
      consumeIpEvent(
        'spectate_room',
        '203.0.113.5',
        t0 + IP_EVENT_LIMITS.spectate_room.ttlMs,
      ),
    ).toBe(true);
  });

  it('ignores non-throttled events (e.g. pick_slot)', () => {
    const t0 = 1_000_000;
    for (let i = 0; i < 100; i++) {
      expect(consumeIpEvent('pick_slot', '203.0.113.9', t0)).toBe(true);
    }
  });
});
