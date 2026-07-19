import { timingSafeEqual } from 'crypto';

/**
 * Shared secret for admin-panel write access and sensitive reads.
 * When unset (local dev), AdminAuthGuard allows all requests through.
 * Required in production — see main.ts assertProductionSecretsConfigured().
 */
export function getAdminApiKey(): string | null {
  const key = process.env.ADMIN_API_KEY;
  if (!key || key.trim() === '') return null;
  return key.trim();
}

/** Constant-time comparison — rejects length mismatches without leaking timing. */
export function verifyAdminApiKey(provided: string | undefined | null): boolean {
  const expected = getAdminApiKey();
  if (!expected) return true;
  if (!provided || provided.trim() === '') return false;
  const a = Buffer.from(provided.trim());
  const b = Buffer.from(expected);
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

/** Extract Bearer token or X-Admin-Key from request headers. */
export function extractAdminTokenFromHeaders(
  headers: Record<string, string | string[] | undefined>,
): string | undefined {
  const auth = headers['authorization'];
  if (typeof auth === 'string' && auth.startsWith('Bearer ')) {
    return auth.slice(7).trim();
  }
  const headerKey = headers['x-admin-key'];
  if (typeof headerKey === 'string') return headerKey.trim();
  return undefined;
}
