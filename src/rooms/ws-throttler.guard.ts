import { Injectable } from '@nestjs/common';
import { ThrottlerGuard, ThrottlerRequest } from '@nestjs/throttler';
import { MESSAGE_METADATA } from '@nestjs/websockets/constants';
import { WebSocket } from 'ws';
import { ErrorCodes } from '../shared/error-codes.js';
import { consumeIpEvent } from './ws-ip-throttle.js';

type WsClient = WebSocket & { id?: string; clientIp?: string };

/**
 * Extends stock ThrottlerGuard for WebSocket:
 * 1. Tracks by socket id (existing behaviour — connection-wide baseline).
 * 2. For join/spectate/reconnect events, also tracks by client IP so a
 *    reconnecting abuser cannot bypass limits by opening a new socket.
 *
 * On any limit breach, sends RATE_LIMITED and returns false (does not throw —
 * Nest WS guards run before interceptors; see prior comment).
 */
@Injectable()
export class WsThrottlerGuard extends ThrottlerGuard {
  protected async handleRequest(requestProps: ThrottlerRequest): Promise<boolean> {
    const { context, limit, ttl, throttler, blockDuration, generateKey } =
      requestProps;
    const client = context.switchToWs().getClient<WsClient>();
    const tracker = client?.id ?? 'unknown';
    const throttlerName = throttler.name ?? 'default';
    const key = generateKey(context, tracker, throttlerName);

    const { isBlocked } = await this.storageService.increment(
      key,
      ttl,
      limit,
      blockDuration,
      throttlerName,
    );

    if (isBlocked) {
      this.sendRateLimited(client);
      return false;
    }

    const eventName = this.resolveEventName(context);
    if (eventName) {
      const allowed = consumeIpEvent(eventName, client?.clientIp ?? 'unknown');
      if (!allowed) {
        this.sendRateLimited(client);
        return false;
      }
    }

    return true;
  }

  private resolveEventName(context: ThrottlerRequest['context']): string | undefined {
    try {
      const handler = context.getHandler();
      const meta = Reflect.getMetadata(MESSAGE_METADATA, handler);
      if (typeof meta === 'string') return meta;
      if (meta && typeof meta === 'object' && 'message' in meta) {
        const m = (meta as { message?: unknown }).message;
        return typeof m === 'string' ? m : undefined;
      }
    } catch {
      // Unit tests that stub getHandler without metadata skip IP throttling.
    }
    return undefined;
  }

  private sendRateLimited(client: WsClient | undefined): void {
    if (client && client.readyState === WebSocket.OPEN) {
      client.send(
        JSON.stringify({
          event: 'error',
          data: { code: ErrorCodes.RATE_LIMITED },
        }),
      );
    }
  }
}
