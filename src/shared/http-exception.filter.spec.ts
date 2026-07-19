import { ArgumentsHost, BadRequestException, HttpStatus } from '@nestjs/common';
import { HttpExceptionFilter } from './http-exception.filter';

describe('HttpExceptionFilter (Task 1.2)', () => {
  let filter: HttpExceptionFilter;
  let statusCode: number | undefined;
  let body: unknown;
  let response: { status: jest.Mock; json: jest.Mock };

  function makeHost(type: 'http' | 'ws'): ArgumentsHost {
    return {
      getType: () => type,
      switchToHttp: () => ({ getResponse: () => response }),
    } as unknown as ArgumentsHost;
  }

  beforeEach(() => {
    filter = new HttpExceptionFilter();
    statusCode = undefined;
    body = undefined;
    response = {
      status: jest.fn(function (this: unknown, code: number) {
        statusCode = code;
        return response;
      }),
      json: jest.fn((b: unknown) => {
        body = b;
        return response;
      }),
    };
    jest.spyOn(console, 'error').mockImplementation(() => {});
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('formats a known HttpException with its real status and message', () => {
    filter.catch(new BadRequestException('displayName is required'), makeHost('http'));
    expect(statusCode).toBe(HttpStatus.BAD_REQUEST);
    expect(body).toEqual({ error: 'displayName is required' });
  });

  it('formats an unknown thrown error as a clean 500 with no leaked detail', () => {
    filter.catch(new TypeError("Cannot read properties of null (reading 'x')"), makeHost('http'));
    expect(statusCode).toBe(HttpStatus.INTERNAL_SERVER_ERROR);
    expect(body).toEqual({ error: 'INTERNAL_ERROR' });
  });

  it('does not touch the response at all for a non-HTTP host (WebSocket already has its own handler)', () => {
    filter.catch(new Error('boom'), makeHost('ws'));
    expect(response.status).not.toHaveBeenCalled();
    expect(response.json).not.toHaveBeenCalled();
  });
});
