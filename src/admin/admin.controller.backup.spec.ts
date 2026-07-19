import * as fs from 'fs';
import * as path from 'path';
import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import { LoggerModule } from 'nestjs-pino';
import request from 'supertest';
import type { App } from 'supertest/types';
import { AdminModule } from './admin.module';

/**
 * e2e route tests for the backup controller surface — mirrors
 * admin.controller.tournament-awards-config.spec.ts's pattern (real
 * AdminModule, real ADMIN_API_KEY guard check). Backs up/restores the real
 * admin-data/backups dir around the suite so a test run never leaves a
 * stray backup archive behind.
 */
describe('AdminController — backup routes (e2e)', () => {
  let app: INestApplication<App>;
  const originalKey = process.env.ADMIN_API_KEY;
  const backupsDir = path.resolve(process.cwd(), 'backups');

  beforeAll(async () => {
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
    if (fs.existsSync(backupsDir)) fs.rmSync(backupsDir, { recursive: true, force: true });
  });

  const authHeader = { Authorization: 'Bearer test-secret-key' };

  it('GET /backup is guarded', async () => {
    await request(app.getHttpServer()).get('/api/admin/backup').expect(401);
    await request(app.getHttpServer())
      .get('/api/admin/backup')
      .set(authHeader)
      .expect(200);
  });

  it('POST /backup is guarded and, once authenticated, creates a real archive', async () => {
    await request(app.getHttpServer()).post('/api/admin/backup').expect(401);

    const res = await request(app.getHttpServer())
      .post('/api/admin/backup')
      .set(authHeader)
      .expect(201);

    expect(res.body.exists).toBe(true);
    expect(res.body.filename).toBe('hidden-eleven-backup.tar.gz');
    expect(res.body.sizeBytes).toBeGreaterThan(0);

    // GET /backup now reflects the archive just created.
    const status = await request(app.getHttpServer())
      .get('/api/admin/backup')
      .set(authHeader)
      .expect(200);
    expect(status.body.exists).toBe(true);
  });

  it('GET /backup/download is guarded and serves the archive once one exists', async () => {
    await request(app.getHttpServer()).get('/api/admin/backup/download').expect(401);

    // The previous test already created a backup — download it.
    const res = await request(app.getHttpServer())
      .get('/api/admin/backup/download')
      .set(authHeader)
      .expect(200);
    expect(res.headers['content-disposition']).toContain('hidden-eleven-backup.tar.gz');
  });
});
