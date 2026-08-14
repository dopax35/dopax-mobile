import { describe, expect, it } from 'vitest';
import { loadEnv } from '../src/config/env.js';

const base = {
  DATABASE_URL: 'postgres://dopax:dopax@localhost:55432/dopax',
  FIREBASE_PROJECT_ID: 'dopa-x-app',
  JWT_SECRET: 'x'.repeat(48),
  LEGACY_DRIVE_FOLDER_ID: '1QLsYUTmXIha7rn7wNIJDXVTtrcWoXdly',
};

describe('environment configuration', () => {
  it('defaults BOTH_ARCH to true so the legacy pipeline stays authoritative', () => {
    expect(loadEnv({ ...base }).BOTH_ARCH).toBe(true);
  });

  it('parses BOTH_ARCH=false', () => {
    expect(loadEnv({ ...base, BOTH_ARCH: 'false' }).BOTH_ARCH).toBe(false);
  });

  it('rejects a JWT secret that is too short to be meaningful', () => {
    expect(() => loadEnv({ ...base, JWT_SECRET: 'short' })).toThrow(/JWT_SECRET/);
  });

  it('refuses the auth bypass outside development', () => {
    expect(() =>
      loadEnv({ ...base, NODE_ENV: 'production', AUTH_DEV_BYPASS: 'true' }),
    ).toThrow(/AUTH_DEV_BYPASS/);
  });

  it('allows the auth bypass in development', () => {
    const env = loadEnv({ ...base, NODE_ENV: 'development', AUTH_DEV_BYPASS: 'true' });
    expect(env.AUTH_DEV_BYPASS).toBe(true);
  });

  it('requires S3 credentials when an S3 backend is selected', () => {
    expect(() => loadEnv({ ...base, STORAGE_BACKEND: 's3' })).toThrow(/S3_BUCKET/);
  });

  it('requires the legacy folder id for the Drive passthrough backend', () => {
    const { LEGACY_DRIVE_FOLDER_ID: _omitted, ...withoutFolder } = base;
    expect(() =>
      loadEnv({ ...withoutFolder, STORAGE_BACKEND: 'gdrive' }),
    ).toThrow(/LEGACY_DRIVE_FOLDER_ID/);
  });

  it('leaves email sign-in codes off by default', () => {
    expect(loadEnv({ ...base }).EMAIL_AUTH_ENABLED).toBe(false);
  });

  it('requires SMTP settings when email sign-in is enabled', () => {
    expect(() => loadEnv({ ...base, EMAIL_AUTH_ENABLED: 'true' })).toThrow(/SMTP_HOST/);
  });

  it('requires a service account key when email sign-in is enabled', () => {
    expect(() =>
      loadEnv({
        ...base,
        EMAIL_AUTH_ENABLED: 'true',
        SMTP_HOST: 'smtp.example.com',
        SMTP_FROM: 'dopa-X <no-reply@example.com>',
      }),
    ).toThrow(/GOOGLE_APPLICATION_CREDENTIALS/);
  });

  it('accepts email sign-in with no SMTP credential when the dev bypass is on', () => {
    const env = loadEnv({
      ...base,
      NODE_ENV: 'development',
      AUTH_DEV_BYPASS: 'true',
      EMAIL_AUTH_ENABLED: 'true',
    });
    expect(env.EMAIL_AUTH_ENABLED).toBe(true);
  });
});
