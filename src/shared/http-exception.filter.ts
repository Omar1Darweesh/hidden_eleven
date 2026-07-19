import { ArgumentsHost, Catch, ExceptionFilter, HttpException, HttpStatus } from '@nestjs/common';
import type { Response } from 'express';
import { ErrorCodes } from './error-codes.js';

/**
 * Applies to the HTTP side only (admin REST API + static serving) — WebSocket
 * exceptions already have a complete handling path (NestJS's own
 * WsExceptionsHandler + WsSafetyInterceptor, see ws-safety.interceptor.ts)
 * and a global filter has no usable Express `Response` to write to in that
 * context, so it explicitly no-ops for any non-HTTP host rather than risk
 * interfering with that already-verified path.
 *
 * Ensures every admin API error is a clean `{ error: '<code or message>' }`
 * JSON body instead of NestJS's default stack-trace-shaped error response —
 * an unhandled exception becomes a generic 500 with no internal detail
 * leaked to the client (the real error is still logged server-side).
 */
@Catch()
export class HttpExceptionFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost): void {
    if (host.getType() !== 'http') return;

    const response = host.switchToHttp().getResponse<Response>();

    if (exception instanceof HttpException) {
      const status = exception.getStatus();
      const body = exception.getResponse();
      const error =
        typeof body === 'object' && body !== null && 'message' in body
          ? (body as { message: unknown }).message
          : exception.message;
      response.status(status).json({ error });
      return;
    }

    console.error('[http] unhandled exception:', exception);
    response.status(HttpStatus.INTERNAL_SERVER_ERROR).json({ error: ErrorCodes.INTERNAL_ERROR });
  }
}
