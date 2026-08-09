import { sql } from 'drizzle-orm';
import { index, integer, jsonb, pgTable, text, timestamp, uuid } from 'drizzle-orm/pg-core';

/**
 * R5 — the ledger the first-run production migration resumes from.
 *
 * One row per step, keyed by name rather than by run, so the question the
 * runner actually asks ("has this step already finished?") is a primary-key
 * lookup and cannot be answered ambiguously by two historical runs.
 *
 * `inputChecksum` is what makes a re-run meaningful: an unchanged checksum on a
 * completed step means skip, a changed one means the source export was replaced
 * and the step runs again. Every importer is idempotent, so replaying is safe.
 */
export const migrationSteps = pgTable(
  'migration_steps',
  {
    name: text('name').primaryKey(),
    status: text('status').notNull(), // running | completed | failed
    inputChecksum: text('input_checksum'),
    rowsWritten: integer('rows_written'),
    attempts: integer('attempts').notNull().default(0),
    // Which bootstrap invocation last touched the step, for correlating a
    // deployment log against the database after the fact.
    runId: uuid('run_id'),
    startedAt: timestamp('started_at', { withTimezone: true }).notNull().defaultNow(),
    completedAt: timestamp('completed_at', { withTimezone: true }),
    durationMs: integer('duration_ms'),
    error: text('error'),
    detail: jsonb('detail').notNull().default(sql`'{}'::jsonb`),
  },
  (t) => [index('migration_steps_status_idx').on(t.status)],
);
