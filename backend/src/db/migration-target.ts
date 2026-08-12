/**
 * R5 — "production migrates its own data on first run, with nobody connecting
 * by hand". Nothing in the codebase enforced that: `npm run db:migrate` and
 * `npm run db:bootstrap` obey whatever `DATABASE_URL` says, so pasting a managed
 * database URL into `.env` for a moment's inspection silently turns the next
 * migration into a production schema change from a laptop.
 *
 * The guard therefore only applies where the mistake happens. A deployment runs
 * with NODE_ENV=production against a remote host by design, and is untouched.
 */

const LOCAL_HOSTS = new Set(['localhost', '127.0.0.1', '::1', '0.0.0.0', 'postgres', 'db']);

export interface MigrationTarget {
  host: string;
  isLocal: boolean;
}

export function describeMigrationTarget(url: string): MigrationTarget {
  let host: string;

  try {
    host = new URL(url).hostname;
  } catch {
    // An unparseable URL is not something to wave through as "probably local".
    return { host: '(unparseable)', isLocal: false };
  }

  // A docker-compose service name resolves only inside the compose network, and
  // a *.docker.internal host is the laptop itself.
  const isLocal = LOCAL_HOSTS.has(host) || host.endsWith('.localhost') || host.endsWith('.docker.internal');

  return { host, isLocal };
}

export class RemoteMigrationRefused extends Error {
  constructor(
    readonly host: string,
    command: string,
  ) {
    super(
      [
        `refusing to run ${command} against remote host "${host}" from a development environment.`,
        '',
        'DATABASE_URL points somewhere that is not this laptop. If that is a managed',
        'database, migrating it by hand is what R5 exists to prevent: production',
        'migrates itself through the bootstrap release task.',
        '',
        'To inspect a remote database read-only instead:  npm run db:inspect -- --remote',
        'To override deliberately:                        ALLOW_REMOTE_MIGRATION=true npm run ...',
      ].join('\n'),
    );
    this.name = 'RemoteMigrationRefused';
  }
}

export interface GuardOptions {
  nodeEnv?: string | undefined;
  allowRemote?: boolean | undefined;
  command: string;
}

export function assertMigrationTargetAllowed(url: string, options: GuardOptions): MigrationTarget {
  const target = describeMigrationTarget(url);
  const isProductionDeployment = options.nodeEnv === 'production';

  if (target.isLocal || isProductionDeployment || options.allowRemote) return target;

  throw new RemoteMigrationRefused(target.host, options.command);
}

/** Convenience wrapper for the scripts, which read process.env directly. */
export function guardMigrationTarget(url: string, command: string): MigrationTarget {
  return assertMigrationTargetAllowed(url, {
    nodeEnv: process.env.NODE_ENV,
    allowRemote: process.env.ALLOW_REMOTE_MIGRATION === 'true',
    command,
  });
}
