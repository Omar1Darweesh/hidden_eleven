/**
 * Resolves the allowed CORS origin(s) from the `ALLOWED_ORIGINS` environment
 * variable (comma-separated, e.g. "https://app.example.com,https://staging.example.com").
 * Falls back to localhost:3000 so local development keeps working with zero
 * configuration. Shared by `main.ts` (HTTP/admin REST API) and
 * `rooms.gateway.ts` (WebSocket layer) so the two transports can never drift
 * out of sync with each other — there is exactly one place that decides
 * "who is allowed to talk to this server."
 */
export function getAllowedOrigins(): string[] {
  const raw = process.env.ALLOWED_ORIGINS;
  if (!raw || raw.trim() === '') return ['http://localhost:3000'];
  return raw
    .split(',')
    .map((origin) => origin.trim())
    .filter((origin) => origin.length > 0);
}
