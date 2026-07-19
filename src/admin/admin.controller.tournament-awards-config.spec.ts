import * as fs from 'fs';
import * as path from 'path';
import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import { LoggerModule } from 'nestjs-pino';
import request from 'supertest';
import type { App } from 'supertest/types';
import { AdminModule } from './admin.module';
import { DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1 } from '../game/tournament-awards-config';

// This suite hits the real AdminModule (like admin.controller.spec.ts's
// throttle e2e tests) and, unlike those read-only tests, actually writes a
// draft/publish through the real admin-data/ dir — back up and restore the
// real file around the suite so a test run never permanently mutates this
// repo's seed data.
const CONFIG_PATH = path.resolve(process.cwd(), 'admin-data', 'tournament-awards-config.json');
let backup: string | null = null;

/**
 * e2e route tests for the tournament-awards-config controller surface added
 * in Track A Step 2 — mirrors the scoring-config route pattern exactly
 * (unguarded published read, AdminAuthGuard on the rest). Exercises the real
 * AdminAuthGuard against real HTTP requests (not the guard's own unit spec,
 * which calls canActivate() directly) by setting ADMIN_API_KEY for the
 * duration of this suite.
 */
describe('AdminController — tournament awards config routes (e2e)', () => {
  let app: INestApplication<App>;
  const originalKey = process.env.ADMIN_API_KEY;

  beforeAll(async () => {
    backup = fs.existsSync(CONFIG_PATH) ? fs.readFileSync(CONFIG_PATH, 'utf8') : null;
    process.env.ADMIN_API_KEY = 'test-secret-key';
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [LoggerModule.forRoot({}), AdminModule],
    }).compile();
    app = moduleFixture.createNestApplication();
    await app.init();
  });

  afterAll(async () => {
    await app.close();
    if (originalKey === undefined) {
      delete process.env.ADMIN_API_KEY;
    } else {
      process.env.ADMIN_API_KEY = originalKey;
    }
    if (backup !== null) {
      fs.writeFileSync(CONFIG_PATH, backup, 'utf8');
    } else if (fs.existsSync(CONFIG_PATH)) {
      fs.unlinkSync(CONFIG_PATH);
    }
  });

  const authHeader = { Authorization: 'Bearer test-secret-key' };

  it('GET /tournament-awards-config/published is accessible without admin auth', async () => {
    const res = await request(app.getHttpServer())
      .get('/api/admin/tournament-awards-config/published')
      .expect(200);

    expect(res.body.status).toBe('published');
    expect(res.body.values).toBeDefined();
  });

  it('GET /tournament-awards-config is guarded', async () => {
    await request(app.getHttpServer())
      .get('/api/admin/tournament-awards-config')
      .expect(401);

    await request(app.getHttpServer())
      .get('/api/admin/tournament-awards-config')
      .set(authHeader)
      .expect(200);
  });

  it('PUT /tournament-awards-config/draft is guarded', async () => {
    await request(app.getHttpServer())
      .put('/api/admin/tournament-awards-config/draft')
      .send(DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1)
      .expect(401);

    await request(app.getHttpServer())
      .put('/api/admin/tournament-awards-config/draft')
      .set(authHeader)
      .send(DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1)
      .expect(200);
  });

  it('POST /tournament-awards-config/publish is guarded', async () => {
    await request(app.getHttpServer())
      .post('/api/admin/tournament-awards-config/publish')
      .send({})
      .expect(401);

    await request(app.getHttpServer())
      .post('/api/admin/tournament-awards-config/publish')
      .set(authHeader)
      .send({})
      .expect(201);
  });

  it('success payload shape matches the service output', async () => {
    // draft → publish, then verify GET /tournament-awards-config's shape
    // exactly mirrors AdminService.getTournamentAwardsConfig()'s
    // { draft, published, history } file shape, and /published exactly
    // mirrors the .published slice of it — end to end through real HTTP,
    // not just asserting against the service directly.
    const edited = { ...DEFAULT_TOURNAMENT_AWARDS_CONFIG_V1, championPoints: 77 };

    const draftRes = await request(app.getHttpServer())
      .put('/api/admin/tournament-awards-config/draft')
      .set(authHeader)
      .send(edited)
      .expect(200);
    expect(draftRes.body).toMatchObject({
      status: 'draft',
      values: edited,
    });
    expect(typeof draftRes.body.version).toBe('number');

    const publishRes = await request(app.getHttpServer())
      .post('/api/admin/tournament-awards-config/publish')
      .set(authHeader)
      .send({ note: 'e2e publish' })
      .expect(201);
    expect(publishRes.body).toMatchObject({
      draft: { status: 'draft' },
      published: { status: 'published', note: 'e2e publish', values: edited },
      history: expect.any(Array),
    });

    const fullRes = await request(app.getHttpServer())
      .get('/api/admin/tournament-awards-config')
      .set(authHeader)
      .expect(200);
    expect(fullRes.body).toEqual(publishRes.body);

    const publishedRes = await request(app.getHttpServer())
      .get('/api/admin/tournament-awards-config/published')
      .expect(200);
    expect(publishedRes.body).toEqual(fullRes.body.published);
  });
});
