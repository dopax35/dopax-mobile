import type { FastifyInstance } from 'fastify';
import { afterAll, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';
import { loadEnv } from '../src/config/env.js';

const base = {
  NODE_ENV: 'test',
  DATABASE_URL: 'postgres://dopax:dopax@localhost:55432/dopax',
  FIREBASE_PROJECT_ID: 'dopa-x-app',
  JWT_SECRET: 'x'.repeat(48),
  LEGACY_DRIVE_FOLDER_ID: '1QLsYUTmXIha7rn7wNIJDXVTtrcWoXdly',
};

const apps: FastifyInstance[] = [];

async function appWith(overrides: Record<string, string>) {
  const app = await buildApp({ config: loadEnv({ ...base, ...overrides }) });
  apps.push(app);
  return app;
}

afterAll(async () => {
  await Promise.all(apps.map((app) => app.close()));
});

describe('GET /v1/config', () => {
  it('tells clients to dual-write while BOTH_ARCH is true', async () => {
    const app = await appWith({ BOTH_ARCH: 'true' });
    const response = await app.inject({ method: 'GET', url: '/v1/config' });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({
      bothArch: true,
      dualWriteLegacy: true,
      sourceOfTruth: 'legacy_drive',
    });
  });

  it('stops dual-write and takes ownership once BOTH_ARCH is false', async () => {
    const app = await appWith({ BOTH_ARCH: 'false' });
    const response = await app.inject({ method: 'GET', url: '/v1/config' });

    expect(response.json()).toMatchObject({
      bothArch: false,
      dualWriteLegacy: false,
      sourceOfTruth: 'backend',
    });
  });
});

describe('health', () => {
  it('reports ok without touching the database', async () => {
    const app = await appWith({});
    const response = await app.inject({ method: 'GET', url: '/healthz' });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ status: 'ok' });
  });
});
