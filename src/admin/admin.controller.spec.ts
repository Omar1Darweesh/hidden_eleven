import { EventEmitter } from 'events';
import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import { LoggerModule } from 'nestjs-pino';
import request from 'supertest';
import type { App } from 'supertest/types';
import type { Response } from 'express';
import * as https from 'https';
import { AdminModule } from './admin.module';
import { AdminController } from './admin.controller';
import { AdminService } from './admin.service';

jest.mock('https');

function makeRes(): Response & { status: jest.Mock; setHeader: jest.Mock; end: jest.Mock } {
  const res = {
    headersSent: false,
    status: jest.fn().mockReturnThis(),
    setHeader: jest.fn().mockReturnThis(),
    end: jest.fn().mockReturnThis(),
  };
  return res as unknown as Response & typeof res;
}

class FakeRequest extends EventEmitter {
  destroy = jest.fn();
}

describe('AdminController — proxy/image timeout & error handling (unit)', () => {
  let controller: AdminController;

  // Instantiated directly (not via Nest's TestingModule/DI), matching the
  // convention already used for MatchHistoryService's own spec file — the
  // constructor's PinoLogger param has a silent-default fallback specifically
  // so a plain `new` works without wiring nestjs-pino's LoggerModule.
  beforeEach(() => {
    jest.clearAllMocks();
    controller = new AdminController(new AdminService());
  });

  it('pipes the upstream response through on success', () => {
    const fakeUpstream = new EventEmitter() as EventEmitter & { headers: Record<string, string>; pipe: jest.Mock };
    fakeUpstream.headers = { 'content-type': 'image/png' };
    fakeUpstream.pipe = jest.fn();

    (https.get as jest.Mock).mockImplementation((_url, _opts, cb) => {
      cb(fakeUpstream);
      return new FakeRequest();
    });

    const res = makeRes();
    controller.proxyImage('https://cdn.sofifa.net/players/1.png', res);

    expect(res.setHeader).toHaveBeenCalledWith('Content-Type', 'image/png');
    expect(res.setHeader).toHaveBeenCalledWith('Cache-Control', 'public, max-age=86400');
    expect(fakeUpstream.pipe).toHaveBeenCalledWith(res);
  });

  it('passes a timeout option to the upstream request and destroys the socket if it fires', () => {
    const fakeReq = new FakeRequest();
    (https.get as jest.Mock).mockImplementation((_url, opts) => {
      expect(opts.timeout).toBe(5000);
      return fakeReq;
    });

    const res = makeRes();
    controller.proxyImage('https://cdn.sofifa.net/players/1.png', res);

    fakeReq.emit('timeout');

    expect(fakeReq.destroy).toHaveBeenCalledTimes(1);
    expect(fakeReq.destroy.mock.calls[0][0]).toBeInstanceOf(Error);
  });

  it('returns a clean 502 and never hangs when the upstream request errors (including a destroyed timeout)', () => {
    const fakeReq = new FakeRequest();
    (https.get as jest.Mock).mockImplementation(() => fakeReq);

    const res = makeRes();
    controller.proxyImage('https://cdn.sofifa.net/players/1.png', res);

    fakeReq.emit('error', new Error('socket hang up'));

    expect(res.status).toHaveBeenCalledWith(502);
    expect(res.end).toHaveBeenCalledTimes(1);
  });

  it('does not double-respond if the response already started streaming before an error fires', () => {
    const fakeReq = new FakeRequest();
    (https.get as jest.Mock).mockImplementation(() => fakeReq);

    const res = makeRes();
    (res as unknown as { headersSent: boolean }).headersSent = true;
    controller.proxyImage('https://cdn.sofifa.net/players/1.png', res);

    fakeReq.emit('error', new Error('connection reset mid-stream'));

    expect(res.status).not.toHaveBeenCalled();
    expect(res.end).not.toHaveBeenCalled();
  });

  it('rejects a disallowed host before ever touching the network', () => {
    const res = makeRes();
    expect(() => controller.proxyImage('https://evil.example.com/x.png', res)).toThrow('host not allowed');
    expect(https.get).not.toHaveBeenCalled();
  });
});

describe('AdminController — HTTP rate limiting (e2e)', () => {
  let app: INestApplication<App>;

  beforeEach(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      // AdminModule alone has no LoggerModule of its own (that's registered
      // once, app-wide, in AppModule) — added here so AdminController's
      // @InjectPinoLogger has a real provider to resolve in this isolated
      // e2e-style test, matching how AppModule wires it in production.
      imports: [LoggerModule.forRoot({}), AdminModule],
    }).compile();
    app = moduleFixture.createNestApplication();
    await app.init();
  });

  afterEach(async () => {
    await app.close();
  });

  it('throttles proxy/image at its tighter 20/10s limit — the 21st call in the window is rejected', async () => {
    // No `url` query param → the handler 400s before any network call, so
    // this exercises only the guard, deterministically and without mocking
    // the network at the e2e layer.
    for (let i = 0; i < 20; i++) {
      await request(app.getHttpServer()).get('/api/admin/proxy/image').expect(400);
    }
    await request(app.getHttpServer()).get('/api/admin/proxy/image').expect(429);
  });

  it('does not throttle a normal admin route after the same handful of calls that trips the proxy limit', async () => {
    for (let i = 0; i < 20; i++) {
      await request(app.getHttpServer()).get('/api/admin/players').expect(200);
    }
  });
});
