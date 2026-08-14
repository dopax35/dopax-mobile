import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { PostgreSqlContainer, type StartedPostgreSqlContainer } from '@testcontainers/postgresql';
import { migrate as drizzleMigrate } from 'drizzle-orm/postgres-js/migrator';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildApp } from '../src/app.js';
import { CustomTokenUnavailable, type CustomTokenMinter } from '../src/auth/custom-token.js';
import { loadEnv } from '../src/config/env.js';
import { createConnection, createDatabase, type Database } from '../src/db/client.js';
import { emailOtpCodes } from '../src/db/schema/identity.js';
import {
  EmailOtpRateLimited,
  MAX_ATTEMPTS,
  MAX_SENDS_PER_HOUR,
  RESEND_COOLDOWN_SECONDS,
  issueEmailCode,
  verifyEmailCode,
} from '../src/domain/auth/email-otp.js';
import { MailDeliveryFailed, type Mailer, type OutboundEmail } from '../src/infra/mail/index.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function baseEnv(databaseUrl: string, overrides: Record<string, string> = {}) {
  return loadEnv({
    NODE_ENV: 'test',
    DATABASE_URL: databaseUrl,
    FIREBASE_PROJECT_ID: 'dopa-x-app',
    JWT_SECRET: 'x'.repeat(48),
    ADMIN_API_ENABLED: 'false',
    BOTH_ARCH: 'true',
    LEGACY_DRIVE_DRAIN: 'true',
    LEGACY_DRIVE_FOLDER_ID: 'test-folder',
    EMAIL_AUTH_ENABLED: 'true',
    SMTP_HOST: 'smtp.example.com',
    SMTP_FROM: 'dopa-X <no-reply@example.com>',
    GOOGLE_APPLICATION_CREDENTIALS: '/tmp/does-not-need-to-exist.json',
    ...overrides,
  });
}

function recordingMailer(): Mailer & { sent: OutboundEmail[] } {
  const sent: OutboundEmail[] = [];
  return {
    kind: 'log',
    sent,
    async send(message) {
      sent.push(message);
    },
  };
}

const stubMinter: CustomTokenMinter = {
  kind: 'dev',
  async mintForEmail(email) {
    return { uid: `uid-${email}`, token: `custom-${email}` };
  },
};

/** Pulls the 6-digit code straight out of the message we would have emailed. */
function codeFrom(message: OutboundEmail): string {
  const match = /\b(\d{6})\b/.exec(message.text);
  if (!match) throw new Error(`no code in message: ${message.text}`);
  return match[1]!;
}

describe('email sign-in codes', () => {
  let container: StartedPostgreSqlContainer;
  let database: Database;
  let sql: ReturnType<typeof createConnection>;

  beforeAll(async () => {
    container = await new PostgreSqlContainer('postgres:16-alpine').start();
    sql = createConnection(container.getConnectionUri(), 5);
    database = createDatabase(sql);
    await drizzleMigrate(database, {
      migrationsFolder: path.join(__dirname, '../src/db/migrations'),
    });
  }, 120_000);

  afterAll(async () => {
    await sql?.end({ timeout: 5 });
    await container?.stop();
  });

  beforeEach(async () => {
    await database.delete(emailOtpCodes);
  });

  describe('domain', () => {
    it('issues a code that verifies once and is then spent', async () => {
      const issued = await issueEmailCode(database, { email: 'Alex@Example.com ' });
      expect(issued.email).toBe('alex@example.com');
      expect(issued.code).toMatch(/^\d{6}$/);

      const first = await verifyEmailCode(database, {
        email: 'alex@example.com',
        code: issued.code,
      });
      expect(first).toEqual({ ok: true, email: 'alex@example.com' });

      const replay = await verifyEmailCode(database, {
        email: 'alex@example.com',
        code: issued.code,
      });
      expect(replay).toEqual({ ok: false, reason: 'no_active_code' });
    });

    it('matches the address case-insensitively', async () => {
      const issued = await issueEmailCode(database, { email: 'casing@example.com' });
      const result = await verifyEmailCode(database, {
        email: 'CASING@Example.com',
        code: issued.code,
      });
      expect(result.ok).toBe(true);
    });

    it('never stores the code in the clear', async () => {
      const issued = await issueEmailCode(database, { email: 'hash@example.com' });
      const [row] = await database.select().from(emailOtpCodes);
      expect(row!.codeHash).not.toContain(issued.code);
      expect(row!.codeHash).toHaveLength(64);
    });

    it('rejects an expired code', async () => {
      const past = new Date(Date.now() - 3_600_000);
      const issued = await issueEmailCode(database, { email: 'stale@example.com' }, { now: past });

      const result = await verifyEmailCode(database, {
        email: 'stale@example.com',
        code: issued.code,
      });
      expect(result).toEqual({ ok: false, reason: 'expired' });
    });

    it('locks the code after too many wrong guesses', async () => {
      const issued = await issueEmailCode(database, { email: 'brute@example.com' });
      const wrong = issued.code === '000000' ? '111111' : '000000';

      for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1) {
        const result = await verifyEmailCode(database, {
          email: 'brute@example.com',
          code: wrong,
        });
        expect(result).toEqual({
          ok: false,
          reason: 'mismatch',
          attemptsRemaining: MAX_ATTEMPTS - attempt,
        });
      }

      // The correct code must not rescue a locked row, or the attempt cap only
      // costs an attacker the guesses they already spent.
      const afterLock = await verifyEmailCode(database, {
        email: 'brute@example.com',
        code: issued.code,
      });
      expect(afterLock).toEqual({ ok: false, reason: 'too_many_attempts' });
    });

    it('supersedes the previous code when a new one is requested', async () => {
      const now = new Date();
      const first = await issueEmailCode(database, { email: 'resend@example.com' }, { now });
      const later = new Date(now.getTime() + (RESEND_COOLDOWN_SECONDS + 1) * 1000);
      const second = await issueEmailCode(
        database,
        { email: 'resend@example.com' },
        { now: later },
      );

      expect(
        await verifyEmailCode(database, { email: 'resend@example.com', code: first.code }),
      ).toEqual({ ok: false, reason: 'mismatch', attemptsRemaining: MAX_ATTEMPTS - 1 });

      expect(
        await verifyEmailCode(database, { email: 'resend@example.com', code: second.code }),
      ).toEqual({ ok: true, email: 'resend@example.com' });
    });

    it('holds a resend behind the cooldown', async () => {
      const now = new Date();
      await issueEmailCode(database, { email: 'cooldown@example.com' }, { now });

      await expect(
        issueEmailCode(
          database,
          { email: 'cooldown@example.com' },
          { now: new Date(now.getTime() + 5_000) },
        ),
      ).rejects.toBeInstanceOf(EmailOtpRateLimited);
    });

    it('caps how many codes one address can request in an hour', async () => {
      const start = Date.now();
      for (let index = 0; index < MAX_SENDS_PER_HOUR; index += 1) {
        await issueEmailCode(
          database,
          { email: 'flood@example.com' },
          { now: new Date(start + index * (RESEND_COOLDOWN_SECONDS + 1) * 1000) },
        );
      }

      await expect(
        issueEmailCode(
          database,
          { email: 'flood@example.com' },
          { now: new Date(start + MAX_SENDS_PER_HOUR * 60_000) },
        ),
      ).rejects.toBeInstanceOf(EmailOtpRateLimited);
    });

    it('reports no active code for an address that never asked', async () => {
      expect(
        await verifyEmailCode(database, { email: 'stranger@example.com', code: '123456' }),
      ).toEqual({ ok: false, reason: 'no_active_code' });
    });
  });

  describe('HTTP', () => {
    it('mails a code and exchanges it for a firebase custom token', async () => {
      const mailer = recordingMailer();
      const app = await buildApp({
        config: baseEnv(container.getConnectionUri()),
        database,
        mailer,
        customTokenMinter: stubMinter,
      });

      const start = await app.inject({
        method: 'POST',
        url: '/v1/auth/email/start',
        payload: { email: 'http@example.com' },
      });
      expect(start.statusCode).toBe(202);
      expect(start.json().status).toBe('sent');
      expect(mailer.sent).toHaveLength(1);
      expect(mailer.sent[0]!.to).toBe('http@example.com');

      const verify = await app.inject({
        method: 'POST',
        url: '/v1/auth/email/verify',
        payload: { email: 'http@example.com', code: codeFrom(mailer.sent[0]!) },
      });
      expect(verify.statusCode).toBe(200);
      expect(verify.json()).toEqual({
        customToken: 'custom-http@example.com',
        firebaseUid: 'uid-http@example.com',
      });

      await app.close();
    }, 60_000);

    it('answers 202 for an unknown address so sign-in is not a membership oracle', async () => {
      const mailer = recordingMailer();
      const app = await buildApp({
        config: baseEnv(container.getConnectionUri()),
        database,
        mailer,
        customTokenMinter: stubMinter,
      });

      const response = await app.inject({
        method: 'POST',
        url: '/v1/auth/email/start',
        payload: { email: 'never-enrolled@example.com' },
      });
      expect(response.statusCode).toBe(202);

      await app.close();
    }, 60_000);

    it('rejects a malformed address and a malformed code', async () => {
      const app = await buildApp({
        config: baseEnv(container.getConnectionUri()),
        database,
        mailer: recordingMailer(),
        customTokenMinter: stubMinter,
      });

      expect(
        (
          await app.inject({
            method: 'POST',
            url: '/v1/auth/email/start',
            payload: { email: 'not-an-address' },
          })
        ).statusCode,
      ).toBe(400);

      expect(
        (
          await app.inject({
            method: 'POST',
            url: '/v1/auth/email/verify',
            payload: { email: 'a@example.com', code: '12' },
          })
        ).statusCode,
      ).toBe(400);

      await app.close();
    }, 60_000);

    it('surfaces a wrong code as 401 with the remaining attempts', async () => {
      const mailer = recordingMailer();
      const app = await buildApp({
        config: baseEnv(container.getConnectionUri()),
        database,
        mailer,
        customTokenMinter: stubMinter,
      });

      await app.inject({
        method: 'POST',
        url: '/v1/auth/email/start',
        payload: { email: 'wrong@example.com' },
      });

      const correct = codeFrom(mailer.sent[0]!);
      const wrong = correct === '000000' ? '111111' : '000000';

      const response = await app.inject({
        method: 'POST',
        url: '/v1/auth/email/verify',
        payload: { email: 'wrong@example.com', code: wrong },
      });
      expect(response.statusCode).toBe(401);
      expect(response.json()).toMatchObject({ error: 'invalid_code', reason: 'mismatch' });

      await app.close();
    }, 60_000);

    it('reports 502 when the code cannot be delivered', async () => {
      const app = await buildApp({
        config: baseEnv(container.getConnectionUri()),
        database,
        mailer: {
          kind: 'smtp',
          async send() {
            throw new MailDeliveryFailed('connection refused');
          },
        },
        customTokenMinter: stubMinter,
      });

      const response = await app.inject({
        method: 'POST',
        url: '/v1/auth/email/start',
        payload: { email: 'undeliverable@example.com' },
      });
      expect(response.statusCode).toBe(502);

      await app.close();
    }, 60_000);

    it('reports 503 when custom tokens cannot be minted', async () => {
      const mailer = recordingMailer();
      const app = await buildApp({
        config: baseEnv(container.getConnectionUri()),
        database,
        mailer,
        customTokenMinter: {
          kind: 'firebase',
          async mintForEmail() {
            throw new CustomTokenUnavailable('no service account credential');
          },
        },
      });

      await app.inject({
        method: 'POST',
        url: '/v1/auth/email/start',
        payload: { email: 'nocreds@example.com' },
      });

      const response = await app.inject({
        method: 'POST',
        url: '/v1/auth/email/verify',
        payload: { email: 'nocreds@example.com', code: codeFrom(mailer.sent[0]!) },
      });
      expect(response.statusCode).toBe(503);

      await app.close();
    }, 60_000);

    it('does not mount the routes when email auth is disabled', async () => {
      const app = await buildApp({
        config: baseEnv(container.getConnectionUri(), {
          EMAIL_AUTH_ENABLED: 'false',
          SMTP_HOST: '',
          SMTP_FROM: '',
          GOOGLE_APPLICATION_CREDENTIALS: '',
        }),
        database,
      });

      const response = await app.inject({
        method: 'POST',
        url: '/v1/auth/email/start',
        payload: { email: 'off@example.com' },
      });
      expect(response.statusCode).toBe(404);
      expect((await app.inject({ method: 'GET', url: '/v1/config' })).json().auth).toEqual({
        emailCodeEnabled: false,
      });

      await app.close();
    }, 60_000);
  });
});
