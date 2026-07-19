import { BadRequestException, CallHandler, ExecutionContext, Injectable, NestInterceptor } from '@nestjs/common';
import { InjectPinoLogger, PinoLogger } from 'nestjs-pino';
import { Observable } from 'rxjs';
import { catchError } from 'rxjs/operators';
import { WebSocket } from 'ws';
import { ErrorCodes } from '../shared/error-codes.js';
import { RoomsService } from './rooms.service.js';
import { WsMetricsService } from '../shared/ws-metrics.service.js';

/**
 * Applied to RoomsGateway so a malformed/unexpected payload on ANY
 * @SubscribeMessage handler always produces a clean, consistent error
 * response to the originating client, instead of silence — either
 * `{ code: 'VALIDATION_ERROR', message }` for a ValidationPipe rejection
 * (Task 1.2 — the client's fault, with detail on what was wrong), or
 * `{ code: 'INTERNAL_ERROR' }` for anything else (a genuine server bug —
 * detail is logged server-side only, never sent to the client).
 *
 * Verified empirically (see IMPLEMENTATION_PROGRESS.md, Task 5) that NestJS's
 * own WsExceptionsHandler already catches handler exceptions and keeps the
 * process alive — so this interceptor's job is NOT crash prevention (already
 * handled upstream), it's closing the gap where a caught-but-unreported
 * exception left the calling client waiting forever with no response at all,
 * which is inconsistent with every other error path in this gateway (they all
 * send `{ code: '<SOME_CODE>' }`).
 *
 * Also the single choke point EVERY gateway handler passes through — used
 * for two more things, neither of which required touching individual
 * handlers: (1) a raw inbound-message counter for /metrics, and (2)
 * resolving roomCode/playerId from the socket so error logs are
 * correlatable, since most handlers themselves log nothing at all today.
 */
@Injectable()
export class WsSafetyInterceptor implements NestInterceptor {
  constructor(
    private readonly roomsService: RoomsService,
    private readonly wsMetrics: WsMetricsService,
    @InjectPinoLogger(WsSafetyInterceptor.name)
    private readonly logger: PinoLogger = new PinoLogger({ pinoHttp: { level: 'silent' } }),
  ) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    this.wsMetrics.recordMessage();
    const client = context.switchToWs().getClient<WebSocket & { id?: string }>();
    const socketId = client?.id;
    const entry = socketId ? this.roomsService.getSocketEntry(socketId) : undefined;
    const handler = context.getHandler().name;

    return next.handle().pipe(
      catchError((err: unknown) => {
        // ValidationPipe (Task 1.2) throws BadRequestException for a
        // malformed payload — that's a client mistake, not a server bug, so
        // it's reported distinctly: a specific code, the actual validation
        // message(s) (so a misbehaving client integration can see exactly
        // what it sent wrong), and logged at a lower severity than a genuine
        // unhandled exception.
        if (err instanceof BadRequestException) {
          const response = err.getResponse();
          const message =
            typeof response === 'object' && response !== null && 'message' in response
              ? (response as { message: unknown }).message
              : err.message;
          this.logger.warn(
            { handler, socketId, roomCode: entry?.roomCode, playerId: entry?.playerId, message },
            'WS validation failed',
          );
          if (client && client.readyState === WebSocket.OPEN) {
            client.send(JSON.stringify({ event: 'error', data: { code: ErrorCodes.VALIDATION_ERROR, message } }));
          }
          return [];
        }

        this.logger.error(
          { handler, socketId, roomCode: entry?.roomCode, playerId: entry?.playerId, err },
          'Unhandled error in WS handler',
        );
        if (client && client.readyState === WebSocket.OPEN) {
          client.send(JSON.stringify({ event: 'error', data: { code: ErrorCodes.INTERNAL_ERROR } }));
        }
        // Swallow — already reported above. @SubscribeMessage handlers return
        // void; there's no downstream consumer that needs this re-thrown, and
        // re-throwing here would just hand it back to NestJS's own handler.
        return [];
      }),
    );
  }
}
