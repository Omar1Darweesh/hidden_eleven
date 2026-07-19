import * as fs from 'fs';
import * as path from 'path';
import { execFile } from 'child_process';
import { promisify } from 'util';
import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import nodemailer from 'nodemailer';

const execFileAsync = promisify(execFile);

const DATA_DIR = path.resolve(process.cwd(), 'admin-data');
const ASSETS_ROOT = path.resolve(process.cwd(), 'assets');
const BACKUPS_DIR = path.resolve(process.cwd(), 'backups');
const ARCHIVE_NAME = 'hidden-eleven-backup.tar.gz';

export interface BackupStatus {
  exists: boolean;
  filename?: string;
  sizeBytes?: number;
  createdAt?: string;
}

/**
 * Single-rotating-file backup of everything that isn't reproducible from
 * source control: admin-data/ (players, clubs, scoring config, etc.),
 * assets/ (uploaded player photos/club logos/nation flags/league logos),
 * and match-history.db (the SQLite match-history store). Every run —
 * whether the daily cron or a manual "Backup Now" — OVERWRITES the same
 * archive (backups/hidden-eleven-backup.tar.gz), by design: this is meant
 * to protect against disk/server loss, not to be a version-history tool,
 * so there is deliberately no accumulating history of old backups to
 * manage or clean up.
 */
@Injectable()
export class BackupService {
  private readonly logger = new Logger(BackupService.name);

  /** Runs once daily at 03:00 server time — quiet hours for real player traffic. */
  @Cron(CronExpression.EVERY_DAY_AT_3AM)
  async runScheduledBackup(): Promise<void> {
    try {
      const result = await this.createBackup();
      this.logger.log(`Scheduled backup completed: ${result.filename} (${result.sizeBytes} bytes)`);
      await this.emailBackupOffServer(this.getArchivePath(), result.sizeBytes);
    } catch (err) {
      // A failed scheduled backup must never crash the server or block
      // gameplay — log it loudly so an admin notices, and leave whatever
      // the PREVIOUS successful backup was untouched (see createBackup's
      // atomic-rename doc comment) rather than losing it.
      this.logger.error(`Scheduled backup failed: ${(err as Error).message}`);
    }
  }

  /**
   * Best-effort: mails the archive off the VPS so a lost/corrupted server
   * doesn't also mean a lost backup. Silently no-ops if the email env vars
   * aren't set (e.g. local dev, or before the admin has configured it), and
   * never throws — a mail failure must not be mistaken for a backup failure.
   */
  private async emailBackupOffServer(archivePath: string, sizeBytes: number): Promise<void> {
    const user = process.env.BACKUP_EMAIL_USER;
    const pass = process.env.BACKUP_EMAIL_APP_PASSWORD;
    const to = process.env.BACKUP_EMAIL_TO;
    if (!user || !pass || !to) {
      this.logger.warn(
        'BACKUP_EMAIL_USER/APP_PASSWORD/TO not set — skipping off-server email copy.',
      );
      return;
    }
    try {
      const transporter = nodemailer.createTransport({
        service: 'gmail',
        auth: { user, pass },
      });
      await transporter.sendMail({
        from: user,
        to,
        subject: `Hidden Eleven backup — ${new Date().toISOString().slice(0, 10)}`,
        text: `Daily backup attached (${(sizeBytes / (1024 * 1024)).toFixed(1)} MB).`,
        attachments: [{ filename: 'hidden-eleven-backup.tar.gz', path: archivePath }],
      });
      this.logger.log(`Backup emailed to ${to}`);
    } catch (err) {
      this.logger.error(`Failed to email backup off-server: ${(err as Error).message}`);
    }
  }

  getStatus(): BackupStatus {
    const archivePath = path.join(BACKUPS_DIR, ARCHIVE_NAME);
    if (!fs.existsSync(archivePath)) return { exists: false };
    const stat = fs.statSync(archivePath);
    return {
      exists: true,
      filename: ARCHIVE_NAME,
      sizeBytes: stat.size,
      createdAt: stat.mtime.toISOString(),
    };
  }

  getArchivePath(): string {
    return path.join(BACKUPS_DIR, ARCHIVE_NAME);
  }

  /**
   * Stages a copy of admin-data/, assets/, and match-history.db into a temp
   * directory, tars+gzips it, then atomically renames it over the previous
   * archive. The atomic rename (not writing directly to the final filename)
   * means a crash or error mid-tar can never leave a corrupt/truncated
   * "latest" backup in place — the old good one survives untouched until
   * the new one has fully, successfully written.
   */
  async createBackup(): Promise<BackupStatus & { filename: string; sizeBytes: number; createdAt: string }> {
    if (!fs.existsSync(BACKUPS_DIR)) fs.mkdirSync(BACKUPS_DIR, { recursive: true });

    const stagingDir = path.join(BACKUPS_DIR, '.staging');
    if (fs.existsSync(stagingDir)) fs.rmSync(stagingDir, { recursive: true, force: true });
    fs.mkdirSync(stagingDir, { recursive: true });

    try {
      if (fs.existsSync(DATA_DIR)) {
        fs.cpSync(DATA_DIR, path.join(stagingDir, 'admin-data'), { recursive: true });
      }
      if (fs.existsSync(ASSETS_ROOT)) {
        fs.cpSync(ASSETS_ROOT, path.join(stagingDir, 'assets'), { recursive: true });
      }
      const dbPath = process.env.DB_PATH ?? path.resolve(process.cwd(), 'match-history.db');
      if (fs.existsSync(dbPath)) {
        fs.copyFileSync(dbPath, path.join(stagingDir, 'match-history.db'));
      }

      const finalPath = path.join(BACKUPS_DIR, ARCHIVE_NAME);
      const tmpPath = path.join(BACKUPS_DIR, `.${ARCHIVE_NAME}.tmp`);
      // --force-local: without it, GNU tar (present on PATH on some Windows
      // dev setups, e.g. via Git for Windows) misparses an absolute
      // "C:\..." path as a "host:path" remote-tar spec because of the
      // drive-letter colon, and fails with a bogus "Cannot connect to C:"
      // error. Harmless no-op on Linux (the actual production target).
      await execFileAsync('tar', ['czf', tmpPath, '--force-local', '-C', stagingDir, '.']);
      fs.renameSync(tmpPath, finalPath);

      const stat = fs.statSync(finalPath);
      return {
        exists: true,
        filename: ARCHIVE_NAME,
        sizeBytes: stat.size,
        createdAt: stat.mtime.toISOString(),
      };
    } finally {
      fs.rmSync(stagingDir, { recursive: true, force: true });
    }
  }
}
