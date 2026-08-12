/**
 * What is actually in a database, without a psql client and without write access.
 *
 *   npm run db:inspect                 the local dev database (DATABASE_URL)
 *   npm run db:inspect -- --remote     RAILWAY_DATABASE_URL, read-only
 *
 * The remote path is the answer to "can we look at production?": the connection
 * is opened with default_transaction_read_only, so every statement it can issue
 * is refused by PostgreSQL if it tries to write. R5 says production migrates
 * itself and nobody connects by hand to change it — looking is fine, and this is
 * the shape of "looking" that cannot turn into "changing" by accident.
 *
 * On Railway, use DATABASE_PUBLIC_URL (the *.proxy.rlwy.net TCP proxy).
 * postgres.railway.internal resolves only inside Railway's private network.
 */
import 'dotenv/config';
import postgres from 'postgres';
import { env } from '../src/config/env.js';
import { describeMigrationTarget } from '../src/db/migration-target.js';

const remote = process.argv.includes('--remote');
const config = env();

const url = remote ? config.RAILWAY_DATABASE_URL : config.DATABASE_URL;

if (!url) {
  console.error(
    [
      'RAILWAY_DATABASE_URL is not set.',
      '',
      'In Railway: Postgres service → Variables → DATABASE_PUBLIC_URL. Copy that',
      'value into backend/.env as RAILWAY_DATABASE_URL. The internal',
      'postgres.railway.internal host will not resolve from this machine.',
    ].join('\n'),
  );
  process.exit(2);
}

/**
 * Fixed list rather than a catalogue sweep, so the output is a stable report of
 * the tables the migration cares about and a table appearing or vanishing is
 * visible instead of silently changing the shape of the output.
 */
const TABLES = [
  'participants',
  'auth_identities',
  'participant_profiles',
  'consents',
  'participant_id_conflicts',
  'devices',
  'uploads',
  'upload_files',
  'drive_manifest_exceptions',
  'events',
  'test_sessions',
  'test_metrics',
  'questionnaire_responses',
  'medication_logs',
  'daily_summaries',
  'reconciliation_runs',
  'migration_steps',
  'staff_users',
  'audit_log',
] as const;

const target = describeMigrationTarget(url);
console.log(`inspecting ${target.host}${remote ? ' (remote, read-only)' : ' (local)'}\n`);

const sql = postgres(url, {
  max: 1,
  connect_timeout: 15,
  onnotice: () => {},
  // Enforced by PostgreSQL itself rather than by this script's good intentions.
  connection: { default_transaction_read_only: true },
});

let exitCode = 1;

try {
  const present = await sql<{ table_name: string }[]>`
    select table_name from information_schema.tables where table_schema = 'public'
  `;
  const existing = new Set(present.map((row) => row.table_name));

  const width = Math.max(...TABLES.map((table) => table.length));

  for (const table of TABLES) {
    if (!existing.has(table)) {
      console.log(`${table.padEnd(width)}  —  (table does not exist)`);
      continue;
    }

    const [row] = await sql<{ count: string }[]>`
      select count(*)::text as count from ${sql(table)}
    `;
    console.log(`${table.padEnd(width)}  ${(row?.count ?? '?').padStart(9)}`);
  }

  const steps = existing.has('migration_steps')
    ? await sql<{ name: string; status: string; rows_written: number | null }[]>`
        select name, status, rows_written from migration_steps order by started_at
      `
    : [];

  if (steps.length > 0) {
    console.log('\nbootstrap steps (R5):');
    for (const step of steps) {
      console.log(`  ${step.status.padEnd(10)} ${step.name}  rows=${step.rows_written ?? '—'}`);
    }
  }

  const runs = existing.has('reconciliation_runs')
    ? await sql<
        { run_at: Date; status: string; drive_objects: number; db_uploads: number; db_parsed: number }[]
      >`
        select run_at, status, drive_objects, db_uploads, db_parsed
        from reconciliation_runs order by run_at desc limit 5
      `
    : [];

  if (runs.length > 0) {
    console.log('\nlatest reconciliation runs (R3):');
    for (const run of runs) {
      console.log(
        `  ${run.run_at.toISOString()}  ${run.status.padEnd(14)} drive=${run.drive_objects} uploads=${run.db_uploads} parsed=${run.db_parsed}`,
      );
    }
  }

  exitCode = 0;
} catch (error) {
  console.error('\ninspection failed:', error instanceof Error ? error.message : error);

  if (remote && error instanceof Error && /ENOTFOUND|ETIMEDOUT|ECONNREFUSED/.test(error.message)) {
    console.error(
      '\nThat host is not reachable from here. If it ends in .railway.internal it never\nwill be: use DATABASE_PUBLIC_URL instead.',
    );
  }
} finally {
  await sql.end({ timeout: 5 });
}

process.exit(exitCode);
