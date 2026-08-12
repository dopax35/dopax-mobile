import type { FastifyInstance } from 'fastify';
import { afterEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';
import { signAdminToken, type StaffRole } from '../src/auth/admin-token.js';
import { IdTokenInvalid, type IdTokenVerifier } from '../src/auth/id-token.js';
import { loadEnv } from '../src/config/env.js';
import type { Database } from '../src/db/client.js';

const adminSecret = 'c'.repeat(48);

const baseEnv = {
  NODE_ENV: 'test',
  DATABASE_URL: 'postgres://dopax:dopax@localhost:55432/dopax',
  FIREBASE_PROJECT_ID: 'dopa-x-app',
  JWT_SECRET: 'x'.repeat(48),
  LEGACY_DRIVE_FOLDER_ID: '1QLsYUTmXIha7rn7wNIJDXVTtrcWoXdly',
  ADMIN_API_ENABLED: 'true',
  ADMIN_JWT_SECRET: adminSecret,
};

/**
 * A scripted stand-in for the database. The behaviour under test here is the
 * scope's auth, role and audit hooks, which must hold regardless of what any
 * query returns — so the queries are not the subject and a container would only
 * slow the suite down.
 */
function fakeDatabase(options: { selects?: unknown[][]; failInserts?: boolean } = {}) {
  const selects = [...(options.selects ?? [])];
  const inserted: Record<string, unknown>[] = [];
  const updates: Record<string, unknown>[] = [];

  const chainable = () => {
    const node: Record<string, unknown> = {
      then(resolve: (value: unknown) => unknown, reject: (reason: unknown) => unknown) {
        return Promise.resolve(selects.shift() ?? []).then(resolve, reject);
      },
    };

    for (const method of [
      'from',
      'where',
      'groupBy',
      'leftJoin',
      'innerJoin',
      'orderBy',
      'limit',
      'offset',
      'returning',
    ]) {
      node[method] = () => node;
    }

    return node;
  };

  const database = {
    select: () => chainable(),
    insert: () => ({
      values: async (values: Record<string, unknown>) => {
        if (options.failInserts) throw new Error('audit_log is unavailable');
        inserted.push(values);
      },
    }),
    update: () => ({
      set: (values: Record<string, unknown>) => {
        updates.push(values);
        return chainable();
      },
    }),
  };

  return { database: database as unknown as Database, inserted, updates };
}

function fakeVerifier(identity: { email?: string } | 'invalid'): IdTokenVerifier {
  return {
    kind: 'dev',
    async verify() {
      if (identity === 'invalid') throw new IdTokenInvalid('test');
      return { uid: 'uid-1', emailVerified: true, provider: 'password', ...identity };
    },
  };
}

const apps: FastifyInstance[] = [];

async function appWith(options: {
  database: Database;
  verifier?: IdTokenVerifier;
  env?: Record<string, string>;
}) {
  const app = await buildApp({
    config: loadEnv({ ...baseEnv, ...options.env }),
    database: options.database,
    idTokenVerifier: options.verifier ?? fakeVerifier({ email: 'staff@example.com' }),
  });

  apps.push(app);
  return app;
}

async function tokenFor(role: StaffRole) {
  const { token } = await signAdminToken(
    { staffId: '11111111-1111-4111-8111-111111111111', email: `${role}@example.com`, role },
    { secret: adminSecret, ttlSeconds: 300 },
  );

  return `Bearer ${token}`;
}

afterEach(async () => {
  await Promise.all(apps.splice(0).map((app) => app.close()));
});

describe('admin surface mounting', () => {
  it('is absent entirely unless the environment enables it', async () => {
    const { database } = fakeDatabase();
    const app = await appWith({ database, env: { ADMIN_API_ENABLED: 'false' } });

    const response = await app.inject({ method: 'GET', url: '/v1/admin/overview' });
    expect(response.statusCode).toBe(404);
  });

  it('refuses to boot with the admin surface on and no secret', () => {
    const { ADMIN_JWT_SECRET: _omitted, ...withoutSecret } = baseEnv;
    expect(() => loadEnv(withoutSecret)).toThrow(/ADMIN_JWT_SECRET/);
  });

  it('refuses to boot when staff and participant tokens share a secret', () => {
    expect(() =>
      loadEnv({ ...baseEnv, ADMIN_JWT_SECRET: baseEnv.JWT_SECRET }),
    ).toThrow(/must differ/);
  });
});

describe('authentication', () => {
  it('rejects a request with no token', async () => {
    const { database } = fakeDatabase();
    const app = await appWith({ database });

    const response = await app.inject({ method: 'GET', url: '/v1/admin/me' });

    expect(response.statusCode).toBe(401);
    expect(response.json()).toMatchObject({ error: 'unauthorized' });
  });

  it('rejects a malformed bearer token', async () => {
    const { database } = fakeDatabase();
    const app = await appWith({ database });

    const response = await app.inject({
      method: 'GET',
      url: '/v1/admin/me',
      headers: { authorization: 'Bearer not-a-jwt' },
    });

    expect(response.statusCode).toBe(401);
  });

  it('accepts a signed staff token', async () => {
    const { database } = fakeDatabase();
    const app = await appWith({ database });

    const response = await app.inject({
      method: 'GET',
      url: '/v1/admin/me',
      headers: { authorization: await tokenFor('admin') },
    });

    expect(response.statusCode).toBe(200);
    expect(response.json().staff).toMatchObject({ role: 'admin' });
  });
});

describe('sign-in is an allowlist, not a token check (R1)', () => {
  it('refuses a verified account that is not in staff_users', async () => {
    // The select for staff returns nothing, which is what any of the 43
    // participants presenting a perfectly valid Firebase token would produce.
    const { database, inserted } = fakeDatabase({ selects: [[]] });
    const app = await appWith({ database });

    const response = await app.inject({
      method: 'POST',
      url: '/v1/admin/auth/session',
      payload: { idToken: 'valid-firebase-token' },
    });

    expect(response.statusCode).toBe(403);
    expect(response.json()).toMatchObject({ error: 'not_staff' });
    expect(inserted).toHaveLength(1);
    expect(inserted[0]).toMatchObject({ action: 'admin.session.refused' });
  });

  it('issues a session for an active staff row', async () => {
    const { database, inserted } = fakeDatabase({
      selects: [
        [
          {
            id: '22222222-2222-4222-8222-222222222222',
            email: 'staff@example.com',
            displayName: 'A Staffer',
            role: 'researcher',
          },
        ],
      ],
    });

    const app = await appWith({ database });

    const response = await app.inject({
      method: 'POST',
      url: '/v1/admin/auth/session',
      payload: { idToken: 'valid-firebase-token' },
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({
      staff: { email: 'staff@example.com', role: 'researcher' },
    });
    expect(response.json().token).toBeTypeOf('string');
    expect(inserted.at(-1)).toMatchObject({ action: 'admin.session.created' });
  });

  it('rejects an unverifiable id token before looking anyone up', async () => {
    const { database, inserted } = fakeDatabase();
    const app = await appWith({ database, verifier: fakeVerifier('invalid') });

    const response = await app.inject({
      method: 'POST',
      url: '/v1/admin/auth/session',
      payload: { idToken: 'forged' },
    });

    expect(response.statusCode).toBe(401);
    expect(inserted).toHaveLength(0);
  });

  it('requires an idToken in the body', async () => {
    const { database } = fakeDatabase();
    const app = await appWith({ database });

    const response = await app.inject({
      method: 'POST',
      url: '/v1/admin/auth/session',
      payload: {},
    });

    expect(response.statusCode).toBe(400);
  });
});

describe('role gate', () => {
  it('keeps a viewer out of the participant detail view', async () => {
    const { database, inserted } = fakeDatabase();
    const app = await appWith({ database });

    const response = await app.inject({
      method: 'GET',
      url: '/v1/admin/participants/33333333-3333-4333-8333-333333333333',
      headers: { authorization: await tokenFor('viewer') },
    });

    expect(response.statusCode).toBe(403);
    expect(response.json()).toMatchObject({ requiredRole: 'researcher' });
    expect(inserted[0]).toMatchObject({ action: 'admin.access.denied' });
  });

  it('keeps a researcher out of the audit trail', async () => {
    const { database } = fakeDatabase();
    const app = await appWith({ database });

    const response = await app.inject({
      method: 'GET',
      url: '/v1/admin/audit',
      headers: { authorization: await tokenFor('researcher') },
    });

    expect(response.statusCode).toBe(403);
  });

  it('lets a researcher list participants', async () => {
    const { database } = fakeDatabase({ selects: [[], [{ count: '0' }]] });
    const app = await appWith({ database });

    const response = await app.inject({
      method: 'GET',
      url: '/v1/admin/participants',
      headers: { authorization: await tokenFor('researcher') },
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({ identityVisible: false });
  });

  it('tells an admin that identity is visible to them', async () => {
    const { database } = fakeDatabase({ selects: [[], [{ count: '0' }]] });
    const app = await appWith({ database });

    const response = await app.inject({
      method: 'GET',
      url: '/v1/admin/participants',
      headers: { authorization: await tokenFor('admin') },
    });

    expect(response.json()).toMatchObject({ identityVisible: true });
  });
});

describe('audit trail (§6.6)', () => {
  it('records a participant read against the participant as subject', async () => {
    const { database, inserted } = fakeDatabase({ selects: [[]] });
    const app = await appWith({ database });

    await app.inject({
      method: 'GET',
      url: '/v1/admin/participants/33333333-3333-4333-8333-333333333333',
      headers: { authorization: await tokenFor('researcher') },
    });

    expect(inserted[0]).toMatchObject({
      actorType: 'staff',
      action: 'participant.read',
      subject: '33333333-3333-4333-8333-333333333333',
    });
  });

  /**
   * The trade documented in src/audit/log.ts: for a medical study, an outage is
   * better than serving participant data we cannot account for afterwards.
   */
  it('refuses to serve a read it cannot audit', async () => {
    const { database } = fakeDatabase({ failInserts: true });
    const app = await appWith({ database });

    const response = await app.inject({
      method: 'GET',
      url: '/v1/admin/participants',
      headers: { authorization: await tokenFor('researcher') },
    });

    expect(response.statusCode).toBe(503);
    expect(response.json()).toMatchObject({ error: 'audit_unavailable' });
  });

  it('does not audit the aggregate overview the console polls', async () => {
    const { database, inserted } = fakeDatabase({
      selects: [[], [], [{ count: '0' }], [], [], [], [], [], [], []],
    });
    const app = await appWith({ database });

    const response = await app.inject({
      method: 'GET',
      url: '/v1/admin/overview',
      headers: { authorization: await tokenFor('admin') },
    });

    expect(response.statusCode).toBe(200);
    expect(inserted).toHaveLength(0);
  });
});
