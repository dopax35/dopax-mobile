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
 *
 * Schema-qualified since migration 0006: the identifying tables live in `identity`,
 * and printing them under their schema is a standing reminder of which side of the
 * boundary a table sits on.
 */
const TABLES = [
  ['public', 'participants'],
  ['identity', 'auth_identities'],
  ['identity', 'consents'],
  ['identity', 'email_otp_codes'],
  ['public', 'participant_profiles'],
  ['public', 'participant_id_conflicts'],
  ['public', 'devices'],
  ['public', 'uploads'],
  ['public', 'upload_files'],
  ['public', 'drive_manifest_exceptions'],
  ['public', 'events'],
  ['public', 'test_sessions'],
  ['public', 'test_metrics'],
  ['public', 'questionnaire_responses'],
  ['public', 'medication_logs'],
  ['public', 'daily_summaries'],
  ['public', 'reconciliation_runs'],
  ['public', 'migration_steps'],
  ['public', 'staff_users'],
  ['public', 'audit_log'],
] as const satisfies readonly (readonly [string, string])[];

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
  const present = await sql<{ table_schema: string; table_name: string }[]>`
    select table_schema, table_name from information_schema.tables
    where table_schema in ('public', 'identity')
  `;
  const existing = new Set(present.map((row) => `${row.table_schema}.${row.table_name}`));

  const labels = TABLES.map(([schema, table]) => `${schema}.${table}`);
  const width = Math.max(...labels.map((label) => label.length));

  for (const [schema, table] of TABLES) {
    const label = `${schema}.${table}`;

    if (!existing.has(label)) {
      console.log(`${label.padEnd(width)}  —  (table does not exist)`);
      continue;
    }

    const [row] = await sql<{ count: string }[]>`
      select count(*)::text as count from ${sql(schema)}.${sql(table)}
    `;
    console.log(`${label.padEnd(width)}  ${(row?.count ?? '?').padStart(9)}`);
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
