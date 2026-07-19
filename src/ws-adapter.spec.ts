import { IncomingMessage } from 'http';
import { extractClientIp } from './ws-adapter';

describe('extractClientIp', () => {
  it('uses the first X-Forwarded-For hop when present', () => {
    const req = {
      headers: { 'x-forwarded-for': '203.0.113.1, 10.0.0.1' },
      socket: { remoteAddress: '127.0.0.1' },
    } as unknown as IncomingMessage;
    expect(extractClientIp(req)).toBe('203.0.113.1');
  });

  it('falls back to remoteAddress when no forwarded header', () => {
    const req = {
      headers: {},
      socket: { remoteAddress: '192.0.2.50' },
    } as unknown as IncomingMessage;
    expect(extractClientIp(req)).toBe('192.0.2.50');
  });

  it('uses X-Real-IP when X-Forwarded-For is absent (Caddy default)', () => {
    const req = {
      headers: { 'x-real-ip': '198.51.100.42' },
      socket: { remoteAddress: '127.0.0.1' },
    } as unknown as IncomingMessage;
    expect(extractClientIp(req)).toBe('198.51.100.42');
  });

  it('returns unknown when nothing is available', () => {
    const req = { headers: {}, socket: {} } as unknown as IncomingMessage;
    expect(extractClientIp(req)).toBe('unknown');
  });
});
