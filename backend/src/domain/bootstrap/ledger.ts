import { and, eq, inArray, sql } from 'drizzle-orm';
import { createConnection, type Database } from '../../db/client.js';
import { migrationSteps } from '../../db/schema/bootstrap.js';
import type { StepLedger, StepRecord, StepStatus } from './runner.js';

/**
 * Fixed, arbitrary key. Any process that intends to migrate takes this lock, so
 * two application instances starting at the same moment cannot both run the
 * bootstrap. Never reuse it for another lock.
 */
const BOOTSTRAP_LOCK_KEY = 4_071_020_251;

export class BootstrapLockError extends Error {
  constructor() {
    super('another process is already running the bootstrap; refusing to run concurrently');
    this.name = 'BootstrapLockError';
  }
}

/**
 * Session-scoped rather than transaction-scoped on purpose: a Drive backfill
 * runs for hours, and holding a transaction open that long would pin the
 * database's oldest snapshot and block vacuum. The lock therefore needs its own
 * connection, because a pooled one could release it from a different session.
 */
export async function withBootstrapLock<T>(run: () => Promise<T>): Promise<T> {
  const connection = createConnection(undefined, 1);

  try {
    const [acquired] = await connection<{ locked: boolean }[]>`
      select pg_try_advisory_lock(${BOOTSTRAP_LOCK_KEY}) as locked
    `;

    if (!acquired?.locked) throw new BootstrapLockError();

    try {
      return await run();
    } finally {
      await connection`select pg_advisory_unlock(${BOOTSTRAP_LOCK_KEY})`;
    }
  } finally {
    await connection.end({ timeout: 5 });
  }
}

export function createStepLedger(database: Database): StepLedger {
  return {
    async read(name) {
      const [row] = await database
        .select({
          name: migrationSteps.name,
          status: migrationSteps.status,
          inputChecksum: migrationSteps.inputChecksum,
        })
        .from(migrationSteps)
        .where(eq(migrationSteps.name, name));

      return row ? ({ ...row, status: row.status as StepStatus } satisfies StepRecord) : undefined;
    },

    async begin({ name, runId, checksum }) {
      await database
        .insert(migrationSteps)
        .values({
          name,
          status: 'running',
          inputChecksum: checksum,
          runId,
          attempts: 1,
          startedAt: new Date(),
        })
        .onConflictDoUpdate({
          target: migrationSteps.name,
          set: {
            status: 'running',
            inputChecksum: checksum,
            runId,
            attempts: sql`${migrationSteps.attempts} + 1`,
            startedAt: new Date(),
            completedAt: null,
            durationMs: null,
            rowsWritten: null,
            error: null,
          },
        });
    },

    async succeed({ name, runId, checksum, rowsWritten, durationMs, detail }) {
      await database
        .update(migrationSteps)
        .set({
          status: 'completed',
          inputChecksum: checksum,
          runId,
          rowsWritten,
          durationMs,
          detail,
          completedAt: new Date(),
          error: null,
        })
        .where(eq(migrationSteps.name, name));
    },

    async fail({ name, runId, durationMs, error }) {
      await database
        .update(migrationSteps)
        .set({ status: 'failed', runId, durationMs, error })
        .where(eq(migrationSteps.name, name));
    },
  };
}

export interface BootstrapStatus {
  complete: boolean;
  pending: string[];
}

/**
 * R5 — what an ingest route asks before accepting data. Serving uploads into a
 * half-migrated database would attach new rows to participants that have not
 * been imported yet, which is exactly the misattribution the whole plan avoids.
 * Safe to refuse, because R3 means the legacy Drive path is still live.
 */
export async function bootstrapStatus(
  database: Database,
  requiredSteps: readonly string[],
): Promise<BootstrapStatus> {
  if (requiredSteps.length === 0) return { complete: true, pending: [] };

  const rows = await database
    .select({ name: migrationSteps.name })
    .from(migrationSteps)
    .where(
      and(inArray(migrationSteps.name, [...requiredSteps]), eq(migrationSteps.status, 'completed')),
    );

  const completed = new Set(rows.map((row) => row.name));
  const pending = requiredSteps.filter((name) => !completed.has(name));

  return { complete: pending.length === 0, pending };
}
