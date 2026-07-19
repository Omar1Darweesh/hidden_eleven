import * as fs from 'fs';
import * as path from 'path';
import { execFile } from 'child_process';
import { promisify } from 'util';
import nodemailer from 'nodemailer';
import { BackupService } from './backup.service';

const execFileAsync = promisify(execFile);

jest.mock('nodemailer');

/**
 * Runs for real against this repo's actual admin-data/ and assets/ dirs
 * (read-only copies only — never mutates them) and a throwaway backups/
 * directory cleaned up afterward, since a real `tar` invocation is the
 * point under test, not something worth mocking away.
 */
describe('BackupService', () => {
  const backupsDir = path.resolve(process.cwd(), 'backups');
  const archivePath = path.join(backupsDir, 'hidden-eleven-backup.tar.gz');

  const originalEnv = { ...process.env };

  afterEach(() => {
    if (fs.existsSync(backupsDir)) fs.rmSync(backupsDir, { recursive: true, force: true });
    process.env = { ...originalEnv };
    jest.clearAllMocks();
  });

  it('getStatus reports exists: false when no backup has ever been created', () => {
    const service = new BackupService();
    expect(service.getStatus()).toEqual({ exists: false });
  });

  it('createBackup produces a real archive containing admin-data and reports its status', async () => {
    const service = new BackupService();

    const result = await service.createBackup();

    expect(result.exists).toBe(true);
    expect(result.filename).toBe('hidden-eleven-backup.tar.gz');
    expect(result.sizeBytes).toBeGreaterThan(0);
    expect(fs.existsSync(archivePath)).toBe(true);

    // Prove it's a genuine, readable archive containing our admin-data —
    // not just an empty/corrupt file — by listing its contents.
    const { stdout } = await execFileAsync('tar', ['tzf', archivePath, '--force-local']);
    expect(stdout).toContain('admin-data/');
    expect(stdout).toContain('admin-data/players.json');

    // getStatus now reflects the freshly created archive.
    const status = service.getStatus();
    expect(status.exists).toBe(true);
    expect(status.filename).toBe('hidden-eleven-backup.tar.gz');
    expect(status.sizeBytes).toBe(result.sizeBytes);
  });

  it('createBackup overwrites the previous archive rather than accumulating multiple files', async () => {
    const service = new BackupService();

    await service.createBackup();
    const firstStat = fs.statSync(archivePath);
    await new Promise((r) => setTimeout(r, 1100)); // ensure mtime actually advances
    await service.createBackup();
    const secondStat = fs.statSync(archivePath);

    // Same single filename, just refreshed — no "-2"/timestamped sibling file left behind.
    expect(fs.readdirSync(backupsDir).filter((f) => f.endsWith('.tar.gz'))).toEqual([
      'hidden-eleven-backup.tar.gz',
    ]);
    expect(secondStat.mtimeMs).toBeGreaterThan(firstStat.mtimeMs);
  });

  it('getArchivePath returns the exact path createBackup writes to', async () => {
    const service = new BackupService();
    await service.createBackup();

    expect(service.getArchivePath()).toBe(archivePath);
    expect(fs.existsSync(service.getArchivePath())).toBe(true);
  });

  it('createBackup cleans up its staging directory even on success (no .staging leftover)', async () => {
    const service = new BackupService();
    await service.createBackup();

    expect(fs.existsSync(path.join(backupsDir, '.staging'))).toBe(false);
  });

  describe('runScheduledBackup — off-server email copy', () => {
    it('skips emailing when BACKUP_EMAIL_* env vars are unset (no throw)', async () => {
      delete process.env.BACKUP_EMAIL_USER;
      delete process.env.BACKUP_EMAIL_APP_PASSWORD;
      delete process.env.BACKUP_EMAIL_TO;
      const service = new BackupService();

      await expect(service.runScheduledBackup()).resolves.toBeUndefined();
      expect(nodemailer.createTransport).not.toHaveBeenCalled();
    });

    it('emails the archive as an attachment when env vars are set', async () => {
      process.env.BACKUP_EMAIL_USER = 'sender@gmail.com';
      process.env.BACKUP_EMAIL_APP_PASSWORD = 'app-password';
      process.env.BACKUP_EMAIL_TO = 'owner@gmail.com';
      const sendMail = jest.fn().mockResolvedValue(undefined);
      (nodemailer.createTransport as jest.Mock).mockReturnValue({ sendMail });
      const service = new BackupService();

      await service.runScheduledBackup();

      expect(nodemailer.createTransport).toHaveBeenCalledWith(
        expect.objectContaining({
          auth: { user: 'sender@gmail.com', pass: 'app-password' },
        }),
      );
      expect(sendMail).toHaveBeenCalledWith(
        expect.objectContaining({
          from: 'sender@gmail.com',
          to: 'owner@gmail.com',
          attachments: [
            expect.objectContaining({ filename: 'hidden-eleven-backup.tar.gz' }),
          ],
        }),
      );
    });

    it('a mail-send failure is swallowed — never crashes the scheduled job', async () => {
      process.env.BACKUP_EMAIL_USER = 'sender@gmail.com';
      process.env.BACKUP_EMAIL_APP_PASSWORD = 'app-password';
      process.env.BACKUP_EMAIL_TO = 'owner@gmail.com';
      const sendMail = jest.fn().mockRejectedValue(new Error('SMTP down'));
      (nodemailer.createTransport as jest.Mock).mockReturnValue({ sendMail });
      const service = new BackupService();

      await expect(service.runScheduledBackup()).resolves.toBeUndefined();
    });
  });
});
