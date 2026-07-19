import { WsAdapter } from '@nestjs/platform-ws';
import { IncomingMessage } from 'http';
import { v4 as uuidv4 } from 'uuid';
import { WebSocket } from 'ws';
import type { Logger as PinoNestLogger } from 'nestjs-pino';

/**
 * Prefer the first X-Forwarded-For hop when present (trusted reverse proxy
 * in production — see deploy/Caddyfile). Fall back to X-Real-IP (also set
 * by Caddy), then the TCP peer address.
 */
export function extractClientIp(req: IncomingMessage): string {
  const forwarded = req.headers['x-forwarded-for'];
  if (typeof forwarded === 'string' && forwarded.trim().length > 0) {
    return forwarded.split(',')[0].trim();
  }
  if (Array.isArray(forwarded) && forwarded.length > 0) {
    return forwarded[0].split(',')[0].trim();
  }
  const realIp = req.headers['x-real-ip'];
  if (typeof realIp === 'string' && realIp.trim().length > 0) {
    return realIp.trim();
  }
  if (Array.isArray(realIp) && realIp.length > 0) {
    return realIp[0].trim();
  }
  return req.socket?.remoteAddress ?? 'unknown';
}

export class IdStampingWsAdapter extends WsAdapter {
  // Optional: passed in from main.ts once the app's pino logger is
  // available. Stamps and logs the correlation ID (socket.id) at the moment
  // a connection is established — every subsequent log statement for this
  // socket's lifetime (see rooms.gateway.ts) includes the same id, so a
  // single connection's full activity can be traced through the logs.
  private pinoLogger?: PinoNestLogger;

  setLogger(logger: PinoNestLogger): void {
    this.pinoLogger = logger;
  }

  bindClientConnect(server: any, callback: Function): void {
    server.on(
      'connection',
      (client: WebSocket & { id: string; clientIp?: string }, req: IncomingMessage) => {
        client.id = uuidv4();
        client.clientIp = extractClientIp(req);
        this.pinoLogger?.log(
          { socketId: client.id, clientIp: client.clientIp },
          'WebSocket connection opened',
        );
        callback(client);
      },
    );
  }
}
