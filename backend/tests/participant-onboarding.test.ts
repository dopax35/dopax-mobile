import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { PostgreSqlContainer, type StartedPostgreSqlContainer } from '@testcontainers/postgresql';
import { migrate as drizzleMigrate } from 'drizzle-orm/postgres-js/migrator';
import { createConnection, createDatabase, type Database } from '../src/db/client.js';
import { resolveParticipant } from '../src/domain/participants/resolve.js';
import {
  ProfileRevisionConflict,
  getProfile,
  putProfile,
} from '../src/domain/participants/profile.js';
import { appendConsent } from '../src/domain/participants/consent.js';
import { buildApp } from '../src/app.js';
import { IdTokenInvalid, type IdTokenVerifier } from '../src/auth/id-token.js';
import { loadEnv } from '../src/config/env.js';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

describe('participant onboarding API', () => {
  let container: StartedPostgreSqlContainer;
  let database: Database;
  let sql: ReturnType<typeof createConnection>;

  beforeAll(async () => {
    container = await new PostgreSqlContainer('postgres:16-alpine').start();
    const url = container.getConnectionUri();
    sql = createConnection(url, 5);
    database = createDatabase(sql);
    await drizzleMigrate(database, {
      migrationsFolder: path.join(__dirname, '../src/db/migrations'),
    });
  }, 120_000);

  afterAll(async () => {
    await sql?.end({ timeout: 5 });
    await container?.stop();
  });

  it('resolves the same firebase uid to the same participant without renumbering', async () => {
    const first = await resolveParticipant(database, {
      firebaseUid: 'uid-legacy-1',
      preferredParticipantCode: 'pd_legacy01',
      email: 'legacy@example.com',
    });
    expect(first.created).toBe(true);
    expect(first.participantCode).toBe('pd_legacy01');

    const second = await resolveParticipant(database, {
      firebaseUid: 'uid-legacy-1',
      preferredParticipantCode: 'SHOULD_NOT_APPLY',
    });
    expect(second.created).toBe(false);
    expect(second.participantId).toBe(first.participantId);
    expect(second.participantCode).toBe('pd_legacy01');
  });

  it('stores profile + consent and enforces revision conflicts', async () => {
    const resolved = await resolveParticipant(database, {
      firebaseUid: 'uid-profile-1',
      preferredParticipantCode: 'AAAAAA',
    });

    const created = await putProfile(database, resolved.participantId, {
      revision: 1,
      age: 68,
      gender: 'Female',
      dominantHand: 'Right',
      affectedSide: 'Left',
      signatureName: 'Alex',
      medications: [{ name: 'Levodopa', dosage: '100mg' }],
      sessionWindows: { morning: '08:00-10:00', evening: '18:00-20:00', custom: '14:00' },
      healthConnections: { appleHealth: 'skipped' },
      permissions: { notifications: true },
      profileComplete: true,
      onboardingVersion: 2,
    });

    expect(created.revision).toBe(1);
    expect(created.age).toBe(68);
    expect((created.settings as { sessionWindows: { custom: string } }).sessionWindows.custom).toBe(
      '14:00',
    );

    await expect(
      putProfile(database, resolved.participantId, {
        revision: 99,
        age: 70,
      }),
    ).rejects.toBeInstanceOf(ProfileRevisionConflict);

    const updated = await putProfile(database, resolved.participantId, {
      revision: created.revision,
      age: 69,
      sessionWindows: { morning: '08:00-10:00', evening: '18:00-20:00', custom: '15:00' },
    });
    expect(updated.revision).toBe(created.revision + 1);
    expect(updated.age).toBe(69);

    const consent = await appendConsent(database, resolved.participantId, {
      signatureName: 'Alex',
      documentVersion: 'onboarding-v2',
      platform: 'ios',
    });
    expect(consent.signatureName).toBe('Alex');

    const loaded = await getProfile(database, resolved.participantId);
    expect(loaded?.revision).toBe(created.revision + 1);
  });

  it('exposes session + profile HTTP endpoints', async () => {
    const safeVerifier: IdTokenVerifier = {
      kind: 'dev',
      async verify(idToken) {
        if (idToken !== 'good-token') throw new IdTokenInvalid('bad');
        return {
          uid: 'uid-http-1',
          email: 'http@example.com',
          emailVerified: true,
          provider: 'google.com',
        };
      },
    };

    const config = loadEnv({
      NODE_ENV: 'test',
      DATABASE_URL: container.getConnectionUri(),
      FIREBASE_PROJECT_ID: 'dopa-x-app',
      JWT_SECRET: 'x'.repeat(48),
      ADMIN_API_ENABLED: 'false',
      BOTH_ARCH: 'true',
      LEGACY_DRIVE_DRAIN: 'true',
      LEGACY_DRIVE_FOLDER_ID: 'test-folder',
    });

    const app = await buildApp({
      config,
      database,
      idTokenVerifier: safeVerifier,
    });

    const session = await app.inject({
      method: 'POST',
      url: '/v1/auth/session',
      payload: { idToken: 'good-token', preferredParticipantCode: 'pd_http001' },
    });
    expect(session.statusCode).toBe(200);
    const body = session.json() as {
      token: string;
      participant: { code: string; created: boolean };
    };
    expect(body.participant.code).toBe('pd_http001');
    expect(body.token).toBeTruthy();

    const put = await app.inject({
      method: 'PUT',
      url: '/v1/participants/me/profile',
      headers: { authorization: `Bearer ${body.token}` },
      payload: {
        revision: 1,
        age: 55,
        gender: 'Male',
        dominantHand: 'Left',
        affectedSide: 'Both',
        profileComplete: true,
        onboardingVersion: 2,
        sessionWindows: { morning: '08:00-10:00', evening: '18:00-20:00', custom: '11:00' },
      },
    });
    expect(put.statusCode).toBe(200);
    expect(put.json().profile.age).toBe(55);

    const me = await app.inject({
      method: 'GET',
      url: '/v1/participants/me',
      headers: { authorization: `Bearer ${body.token}` },
    });
    expect(me.statusCode).toBe(200);
    expect(me.json().profile.age).toBe(55);

    await app.close();
  }, 60_000);
});
