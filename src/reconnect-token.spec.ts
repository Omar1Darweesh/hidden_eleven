import { createHmac } from 'crypto';
import { generateReconnectToken, verifyReconnectToken } from './reconnect-token';

describe('reconnect-token', () => {
  const ORIGINAL_ENV = process.env;

  beforeEach(() => {
    process.env = { ...ORIGINAL_ENV, RECONNECT_TOKEN_SECRET: 'test-secret-do-not-use' };
  });

  afterEach(() => {
    process.env = ORIGINAL_ENV;
  });

  it('a token generated for a playerId/roomCode pair verifies successfully', () => {
    const token = generateReconnectToken('player-1', 'ABCDEF');
    expect(verifyReconnectToken(token, 'player-1', 'ABCDEF')).toBe(true);
  });

  it('accepts a lowercase roomCode at verification time (rooms are case-insensitive)', () => {
    const token = generateReconnectToken('player-1', 'ABCDEF');
    expect(verifyReconnectToken(token, 'player-1', 'abcdef')).toBe(true);
  });

  it('rejects a token for the wrong playerId', () => {
    const token = generateReconnectToken('player-1', 'ABCDEF');
    expect(verifyReconnectToken(token, 'player-2', 'ABCDEF')).toBe(false);
  });

  it('rejects a token for the wrong roomCode', () => {
    const token = generateReconnectToken('player-1', 'ABCDEF');
    expect(verifyReconnectToken(token, 'player-1', 'ZZZZZZ')).toBe(false);
  });

  it('rejects a tampered payload (signature no longer matches)', () => {
    const token = generateReconnectToken('player-1', 'ABCDEF');
    const [payloadB64, signature] = token.split('.');
    const forgedPayload = Buffer.from(
      JSON.stringify({ playerId: 'player-1', roomCode: 'ZZZZZZ', issuedAt: Date.now() }),
      'utf8',
    ).toString('base64url');
    const forgedToken = `${forgedPayload}.${signature}`;
    expect(verifyReconnectToken(forgedToken, 'player-1', 'ZZZZZZ')).toBe(false);
    void payloadB64;
  });

  it('rejects a tampered signature', () => {
    const token = generateReconnectToken('player-1', 'ABCDEF');
    const [payloadB64] = token.split('.');
    expect(verifyReconnectToken(`${payloadB64}.not-a-real-signature`, 'player-1', 'ABCDEF')).toBe(false);
  });

  it('rejects a token signed with a different secret', () => {
    const token = generateReconnectToken('player-1', 'ABCDEF');
    process.env.RECONNECT_TOKEN_SECRET = 'a-completely-different-secret';
    expect(verifyReconnectToken(token, 'player-1', 'ABCDEF')).toBe(false);
  });

  it('rejects missing, empty, or malformed tokens without throwing', () => {
    expect(verifyReconnectToken(undefined, 'player-1', 'ABCDEF')).toBe(false);
    expect(verifyReconnectToken(null, 'player-1', 'ABCDEF')).toBe(false);
    expect(verifyReconnectToken('', 'player-1', 'ABCDEF')).toBe(false);
    expect(verifyReconnectToken('not-a-token-at-all', 'player-1', 'ABCDEF')).toBe(false);
    expect(verifyReconnectToken('..', 'player-1', 'ABCDEF')).toBe(false);
    expect(verifyReconnectToken('not-base64!!!.signature', 'player-1', 'ABCDEF')).toBe(false);
  });

  it('falls back to the fixed dev secret outside production (not a crash)', () => {
    process.env.RECONNECT_TOKEN_SECRET = '';
    process.env.NODE_ENV = 'test';
    const token = generateReconnectToken('player-1', 'ABCDEF');
    expect(verifyReconnectToken(token, 'player-1', 'ABCDEF')).toBe(true);
  });

  it('rejects a token older than RECONNECT_TOKEN_MAX_AGE_MS', () => {
    process.env.RECONNECT_TOKEN_MAX_AGE_MS = '1000';
    const token = generateReconnectToken('player-1', 'ABCDEF');
    // Backdate issuedAt inside the payload (invalidates signature) — instead
    // wait for expiry naturally by forging via generate with mocked Date — use
    // a token we know is expired by sleeping:
    const oldPayload = Buffer.from(
      JSON.stringify({
        playerId: 'player-1',
        roomCode: 'ABCDEF',
        issuedAt: Date.now() - 5000,
      }),
      'utf8',
    ).toString('base64url');
    const oldJson = Buffer.from(oldPayload, 'base64url').toString('utf8');
    const sig = createHmac('sha256', 'test-secret-do-not-use')
      .update(oldJson)
      .digest('base64url');
    const expiredToken = `${oldPayload}.${sig}`;
    expect(verifyReconnectToken(expiredToken, 'player-1', 'ABCDEF')).toBe(false);
  });

  it('requires RECONNECT_TOKEN_SECRET in production', () => {
    process.env.RECONNECT_TOKEN_SECRET = '';
    process.env.NODE_ENV = 'production';
    expect(() => generateReconnectToken('player-1', 'ABCDEF')).toThrow(/RECONNECT_TOKEN_SECRET/);
  });
});
