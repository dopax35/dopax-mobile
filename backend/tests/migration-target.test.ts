import { describe, expect, it } from 'vitest';
import {
  assertMigrationTargetAllowed,
  describeMigrationTarget,
  RemoteMigrationRefused,
} from '../src/db/migration-target.js';

const local = 'postgres://dopax:dopax@localhost:55432/dopax';
const railway = 'postgresql://postgres:secret@postgres.railway.internal:5432/dopa-x';
const railwayPublic = 'postgresql://postgres:secret@monorail.proxy.rlwy.net:41234/railway';

describe('migration target', () => {
  it('recognises the docker-compose database as local', () => {
    expect(describeMigrationTarget(local)).toEqual({ host: 'localhost', isLocal: true });
  });

  it('recognises a compose service name as local', () => {
    expect(describeMigrationTarget('postgres://u:p@postgres:5432/db').isLocal).toBe(true);
  });

  it('does not treat a managed host as local', () => {
    expect(describeMigrationTarget(railway).isLocal).toBe(false);
    expect(describeMigrationTarget(railwayPublic).isLocal).toBe(false);
  });

  it('treats an unparseable url as remote rather than waving it through', () => {
    expect(describeMigrationTarget('not a url').isLocal).toBe(false);
  });
});

describe('R5 — a laptop must not migrate production', () => {
  it('allows a local migration in development', () => {
    expect(() =>
      assertMigrationTargetAllowed(local, { nodeEnv: 'development', command: 'db:migrate' }),
    ).not.toThrow();
  });

  /**
   * The mistake this exists for: a managed URL pasted into .env for a moment's
   * inspection turns the next `npm run db:migrate` into a production schema
   * change from a laptop.
   */
  it('refuses a remote migration from a development environment', () => {
    expect(() =>
      assertMigrationTargetAllowed(railway, { nodeEnv: 'development', command: 'db:migrate' }),
    ).toThrow(RemoteMigrationRefused);
  });

  it('names the host and the read-only alternative in the refusal', () => {
    try {
      assertMigrationTargetAllowed(railway, { nodeEnv: 'development', command: 'db:migrate' });
      expect.unreachable('should have refused');
    } catch (error) {
      expect((error as Error).message).toContain('postgres.railway.internal');
      expect((error as Error).message).toContain('db:inspect');
    }
  });

  /**
   * R5 also requires production to migrate itself on first boot, and it does that
   * against a remote host by design. The guard protects laptops, not deployments.
   */
  it('allows a deployment to migrate its own remote database', () => {
    expect(() =>
      assertMigrationTargetAllowed(railway, { nodeEnv: 'production', command: 'db:bootstrap' }),
    ).not.toThrow();
  });

  it('can be overridden deliberately', () => {
    expect(() =>
      assertMigrationTargetAllowed(railway, {
        nodeEnv: 'development',
        allowRemote: true,
        command: 'db:migrate',
      }),
    ).not.toThrow();
  });
});
