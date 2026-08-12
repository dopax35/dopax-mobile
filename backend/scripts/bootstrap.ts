/**
 * R5 — the first-run data migration. See backend/docs/MIGRATION_PLAN.md §4.4.
 *
 *   npm run db:bootstrap              apply schema migrations, then import
 *   npm run db:bootstrap -- --dry-run report what would run, write nothing
 *
 * Runs as a deployment release task, not from the API's boot path: a Drive
 * backfill takes hours and must never sit between a container starting and its
 * health check passing.
 *
 * Safe to run on every deploy. Completed steps whose input has not changed are
 * skipped, an interrupted step resumes, and a failure aborts the run with a
 * non-zero exit rather than leaving a half-migrated database looking finished.
 */
import 'dotenv/config';
import { randomUUID } from 'node:crypto';
import { resolve } from 'node:path';
import { migrate } from 'drizzle-orm/postgres-js/migrator';
import { env } from '../src/config/env.js';
import { closeDatabase, createConnection, createDatabase, db } from '../src/db/client.js';
import { guardMigrationTarget } from '../src/db/migration-target.js';
import { BootstrapLockError, createStepLedger, withBootstrapLock } from '../src/domain/bootstrap/ledger.js';
import { formatReport, runBootstrap, type BootstrapLogger } from '../src/domain/bootstrap/runner.js';
import { bootstrapSteps } from '../src/domain/bootstrap/steps.js';

const dryRun = process.argv.includes('--dry-run');

const logger: BootstrapLogger = {
  info: (fields, message) => console.log(`[bootstrap] ${message}`, fields),
  warn: (fields, message) => console.warn(`[bootstrap] ${message}`, fields),
  error: (fields, message) => console.error(`[bootstrap] ${message}`, fields),
};

async function applySchemaMigrations(): Promise<void> {
  const connection = createConnection(undefined, 1);
  try {
    await migrate(createDatabase(connection), { migrationsFolder: './src/db/migrations' });
    console.log('[bootstrap] schema migrations applied');
  } finally {
    await connection.end({ timeout: 5 });
  }
}

async function main(): Promise<number> {
  const config = env();
  const sourceDir = resolve(process.cwd(), config.MIGRATION_SOURCE_DIR);

  // A dry run writes nothing, so it is allowed to look at a remote database.
  if (!dryRun) guardMigrationTarget(config.DATABASE_URL, 'db:bootstrap');

  console.log(`[bootstrap] sources   ${sourceDir}`);
  console.log(`[bootstrap] database  ${config.DATABASE_URL.replace(/:[^:@/]*@/, ':***@')}`);

  const database = db();
  const report = await withBootstrapLock(async () => {
    // Inside the lock, because the schema migration needs the same protection
    // as the data steps: drizzle's migrator takes no lock of its own, so two
    // instances starting together would otherwise both apply it.
    //
    // A dry run stays strictly read-only and therefore needs the schema to be
    // in place already rather than putting it there.
    if (!dryRun) await applySchemaMigrations();

    return runBootstrap(bootstrapSteps(database, sourceDir), {
      ledger: createStepLedger(database),
      runId: randomUUID(),
      logger,
      dryRun,
    });
  });

  console.log(`\n${formatReport(report)}`);

  return report.status === 'complete' ? 0 : 1;
}

let exitCode = 1;
try {
  exitCode = await main();
} catch (error) {
  if (error instanceof BootstrapLockError) {
    console.error(`[bootstrap] ${error.message}`);
  } else {
    console.error('[bootstrap] run failed:', error instanceof Error ? error.stack : error);
  }
} finally {
  await closeDatabase();
}

process.exit(exitCode);
