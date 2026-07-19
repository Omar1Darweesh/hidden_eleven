import { ExecutionContext, CallHandler, BadRequestException } from '@nestjs/common';
import { of, throwError, firstValueFrom } from 'rxjs';
import { PinoLogger } from 'nestjs-pino';
import { WsSafetyInterceptor } from './ws-safety.interceptor';
import { RoomsService } from './rooms.service';
import { WsMetricsService } from '../shared/ws-metrics.service';

/**
 * Regression coverage for the gateway safety net. Empirically verified (see
 * IMPLEMENTATION_PROGRESS.md, Task 5) against a real server that NestJS's own
 * WsExceptionsHandler already prevents a crash — what was actually missing,
 * and what this interceptor fixes, is the originating client getting NO
 * response at all for a handler that threw. These tests assert exactly that
 * gap is closed, and that the happy path is left untouched.
 *
 * Also covers the Task 5 additions: every intercepted call increments the
 * shared WsMetricsService counter (success or failure — it's a raw "messages
 * processed" count, not an error count), and error/warn logs are correlated
 * with roomCode/playerId when the socket is resolvable via RoomsService.
 */
describe('WsSafetyInterceptor', () => {
  let interceptor: WsSafetyInterceptor;
  let roomsService: RoomsService;
  let wsMetrics: WsMetricsService;
  let logger: { warn: jest.Mock; error: jest.Mock };
  let sentMessages: string[];
  let mockClient: { id: string; readyState: number; send: (data: string) => void };

  const OPEN = 1;
  const CLOSED = 3;

  function makeContext(client: unknown): ExecutionContext {
    return {
      switchToWs: () => ({ getClient: () => client }),
      getHandler: () => ({ name: 'handleSomething' }),
    } as unknown as ExecutionContext;
  }

  beforeEach(() => {
    roomsService = new RoomsService();
    wsMetrics = new WsMetricsService();
    logger = { warn: jest.fn(), error: jest.fn() };
    interceptor = new WsSafetyInterceptor(roomsService, wsMetrics, logger as unknown as PinoLogger);
    sentMessages = [];
    mockClient = { id: 'sock-1', readyState: OPEN, send: (data: string) => sentMessages.push(data) };
  });

  it('passes through a successful handler result untouched', async () => {
    const next: CallHandler = { handle: () => of('ok') };
    const result = await firstValueFrom(interceptor.intercept(makeContext(mockClient), next));
    expect(result).toBe('ok');
    expect(sentMessages).toHaveLength(0);
  });

  it('sends a clean INTERNAL_ERROR event to the originating client when the handler throws', async () => {
    const next: CallHandler = { handle: () => throwError(() => new TypeError("Cannot read properties of null (reading 'turnId')")) };

    // The interceptor swallows the error (returns an empty observable) rather
    // than re-throwing — confirm it completes without rejecting.
    await expect(
      firstValueFrom(interceptor.intercept(makeContext(mockClient), next), { defaultValue: 'completed' }),
    ).resolves.toBe('completed');

    expect(sentMessages).toHaveLength(1);
    expect(JSON.parse(sentMessages[0])).toEqual({
      event: 'error',
      data: { code: 'INTERNAL_ERROR' },
    });
  });

  it('does not attempt to send to a client whose socket is no longer open', async () => {
    mockClient.readyState = CLOSED;
    const next: CallHandler = { handle: () => throwError(() => new Error('boom')) };

    await firstValueFrom(interceptor.intercept(makeContext(mockClient), next), { defaultValue: undefined });

    expect(sentMessages).toHaveLength(0);
  });

  it('logs the error with the failing handler name for server-side visibility', async () => {
    const next: CallHandler = { handle: () => throwError(() => new Error('boom')) };
    await firstValueFrom(interceptor.intercept(makeContext(mockClient), next), { defaultValue: undefined });

    expect(logger.error).toHaveBeenCalledWith(
      expect.objectContaining({ handler: 'handleSomething', socketId: 'sock-1' }),
      expect.any(String),
    );
  });

  it('reports a ValidationPipe (Task 1.2) failure as VALIDATION_ERROR with the validation message, not a generic INTERNAL_ERROR', async () => {
    const validationError = new BadRequestException({
      statusCode: 400,
      message: ['displayName should not be empty'],
      error: 'Bad Request',
    });
    const next: CallHandler = { handle: () => throwError(() => validationError) };

    await firstValueFrom(interceptor.intercept(makeContext(mockClient), next), { defaultValue: undefined });

    expect(sentMessages).toHaveLength(1);
    expect(JSON.parse(sentMessages[0])).toEqual({
      event: 'error',
      data: { code: 'VALIDATION_ERROR', message: ['displayName should not be empty'] },
    });
    // A client mistake, not a server bug — must not be logged as an error.
    expect(logger.error).not.toHaveBeenCalled();
    expect(logger.warn).toHaveBeenCalled();
  });

  it('increments the shared message counter on both a successful and a failing call', async () => {
    const ok: CallHandler = { handle: () => of('ok') };
    const fail: CallHandler = { handle: () => throwError(() => new Error('boom')) };

    await firstValueFrom(interceptor.intercept(makeContext(mockClient), ok));
    await firstValueFrom(interceptor.intercept(makeContext(mockClient), fail), { defaultValue: undefined });

    expect(wsMetrics.getMessagesTotal()).toBe(2);
  });

  it('correlates an error log with roomCode/playerId when the socket is resolvable via RoomsService', async () => {
    const { playerId, room } = roomsService.createRoom('Alice', 'sock-1');
    const next: CallHandler = { handle: () => throwError(() => new Error('boom')) };

    await firstValueFrom(interceptor.intercept(makeContext(mockClient), next), { defaultValue: undefined });

    expect(logger.error).toHaveBeenCalledWith(
      expect.objectContaining({ roomCode: room.code, playerId }),
      expect.any(String),
    );
  });
});
