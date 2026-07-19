import { createHmac, timingSafeEqual } from 'crypto';

/**
 * Binds a `playerId` to the `roomCode` it was issued for, so that knowing a
 * player's UUID (which leaks trivially — it's broadcast to every player in
 * the room via `room_update.players[].id`) is no longer enough to hijack
 * their seat via `reconnect`/`check_presence`. No accounts, no server-side
 * session store: the token is self-contained (payload + HMAC-SHA256
 * signature), so verification needs nothing but the shared secret.
 *
 * Format: `<base64url(payload JSON)>.<base64url(HMAC-SHA256 signature)>`.
 */

const DEV_DEFAULT_SECRET = 'dev-insecure-reconnect-secret-do-not-use-in-production';

/** Default 30 days — long enough for normal reconnect, limits stolen-token window. */
const DEFAULT_MAX_AGE_MS = 30 * 24 * 60 * 60 * 1000;

function getMaxTokenAgeMs(): number {
  const raw = process.env.RECONNECT_TOKEN_MAX_AGE_MS;
  if (!raw || raw.trim() === '') return DEFAULT_MAX_AGE_MS;
  const parsed = Number(raw);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : DEFAULT_MAX_AGE_MS;
}

interface ReconnectTokenPayload {
  playerId: string;
  roomCode: string;
  issuedAt: number;
}

function getSecret(): string {
  const secret = process.env.RECONNECT_TOKEN_SECRET;
  if (secret && secret.trim() !== '') return secret;
  if (process.env.NODE_ENV === 'production') {
    throw new Error(
      'RECONNECT_TOKEN_SECRET must be set in production — refusing to start with an insecure default reconnect-token secret.',
    );
  }
  return DEV_DEFAULT_SECRET;
}

function sign(payloadJson: string): string {
  return createHmac('sha256', getSecret()).update(payloadJson).digest('base64url');
}

export function generateReconnectToken(playerId: string, roomCode: string): string {
  const payload: ReconnectTokenPayload = { playerId, roomCode, issuedAt: Date.now() };
  const payloadJson = JSON.stringify(payload);
  const payloadB64 = Buffer.from(payloadJson, 'utf8').toString('base64url');
  return `${payloadB64}.${sign(payloadJson)}`;
}

/**
 * Verifies that `token` was genuinely issued by this server for exactly this
 * `playerId` + `roomCode` pair. Tokens expire after RECONNECT_TOKEN_MAX_AGE_MS
 * (default 30 days) to limit hijack window if a token leaks from device storage.
 */
export function verifyReconnectToken(
  token: string | undefined | null,
  playerId: string,
  roomCode: string,
): boolean {
  if (!token || typeof token !== 'string') return false;

  const dotIndex = token.indexOf('.');
  if (dotIndex === -1) return false;
  const payloadB64 = token.slice(0, dotIndex);
  const signature = token.slice(dotIndex + 1);
  if (!payloadB64 || !signature) return false;

  let payloadJson: string;
  try {
    payloadJson = Buffer.from(payloadB64, 'base64url').toString('utf8');
  } catch {
    return false;
  }

  const expectedSignature = sign(payloadJson);
  const sigBuf = Buffer.from(signature);
  const expectedBuf = Buffer.from(expectedSignature);
  if (sigBuf.length !== expectedBuf.length || !timingSafeEqual(sigBuf, expectedBuf)) {
    return false;
  }

  let payload: ReconnectTokenPayload;
  try {
    payload = JSON.parse(payloadJson) as ReconnectTokenPayload;
  } catch {
    return false;
  }

  if (
    typeof payload.issuedAt === 'number' &&
    Date.now() - payload.issuedAt > getMaxTokenAgeMs()
  ) {
    return false;
  }

  return payload.playerId === playerId && payload.roomCode === roomCode.toUpperCase();
}
