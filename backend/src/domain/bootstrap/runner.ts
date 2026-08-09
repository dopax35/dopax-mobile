/**
 * R5 — ordered, resumable, idempotent first-run data migration.
 * See backend/docs/MIGRATION_PLAN.md §4.4.
 *
 * Deliberately free of database and filesystem access. The parts worth getting
 * right here are the decisions — when a step is skipped, when it is replayed,
 * and what happens to the steps behind a failure — and those should be
 * reviewable and testable without a container running.
 */

export interface StepResult {
  rowsWritten: number;
  detail?: Record<string, unknown>;
}

export interface BootstrapStep {
  name: string;
  description: string;
  /**
   * Fingerprint of everything the step reads. A completed step whose checksum
   * still matches is skipped; a changed checksum means the source export was
   * replaced, so the step runs again. Replaying is safe because every importer
   * upserts on a natural key.
   */
  checksum(): Promise<string>;
  /** Must be atomic: either the whole step lands or nothing does. */
  run(): Promise<StepResult>;
  /** Reconciles what landed against the source. Throwing fails the step. */
  verify?(result: StepResult): Promise<void>;
}

export type StepStatus = 'running' | 'completed' | 'failed';

export interface StepRecord {
  name: string;
  status: StepStatus;
  inputChecksum: string | null;
}

export interface StepLedger {
  read(name: string): Promise<StepRecord | undefined>;
  begin(entry: { name: string; runId: string; checksum: string }): Promise<void>;
  succeed(entry: {
    name: string;
    runId: string;
    checksum: string;
    rowsWritten: number;
    durationMs: number;
    detail: Record<string, unknown>;
  }): Promise<void>;
  fail(entry: {
    name: string;
    runId: string;
    durationMs: number;
    error: string;
  }): Promise<void>;
}

export type StepOutcome = 'completed' | 'skipped' | 'failed' | 'pending' | 'not_run';

export interface StepReport {
  name: string;
  outcome: StepOutcome;
  reason: string;
  rowsWritten?: number;
  durationMs?: number;
  error?: string;
}

export interface BootstrapReport {
  runId: string;
  status: 'complete' | 'failed';
  dryRun: boolean;
  durationMs: number;
  steps: StepReport[];
}

export interface BootstrapLogger {
  info(fields: Record<string, unknown>, message: string): void;
  warn(fields: Record<string, unknown>, message: string): void;
  error(fields: Record<string, unknown>, message: string): void;
}

const silentLogger: BootstrapLogger = { info: () => {}, warn: () => {}, error: () => {} };

export interface StepDecision {
  action: 'run' | 'skip';
  reason: string;
}

/**
 * A `running` record means a previous run died partway through this step.
 * Because each step is atomic and idempotent, replaying it is the correct
 * recovery — the alternative, refusing to start, would need a human on a
 * production release that is already failing.
 */
export function decideStep(record: StepRecord | undefined, checksum: string): StepDecision {
  if (!record) return { action: 'run', reason: 'never run' };

  switch (record.status) {
    case 'completed':
      return record.inputChecksum === checksum
        ? { action: 'skip', reason: 'already completed, input unchanged' }
        : { action: 'run', reason: 'input changed since last run' };
    case 'failed':
      return { action: 'run', reason: 'retrying after failure' };
    case 'running':
      return { action: 'run', reason: 'resuming after an interrupted run' };
  }
}

function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

export interface RunBootstrapOptions {
  ledger: StepLedger;
  runId: string;
  logger?: BootstrapLogger;
  /** Report the decisions without running a step or touching the ledger. */
  dryRun?: boolean;
  now?: () => number;
}

export async function runBootstrap(
  steps: readonly BootstrapStep[],
  options: RunBootstrapOptions,
): Promise<BootstrapReport> {
  const { ledger, runId, dryRun = false } = options;
  const logger = options.logger ?? silentLogger;
  const now = options.now ?? (() => Date.now());

  const startedAt = now();
  const reports: StepReport[] = [];
  let failed = false;

  for (const step of steps) {
    if (failed) {
      reports.push({
        name: step.name,
        outcome: 'not_run',
        reason: 'an earlier step failed',
      });
      continue;
    }

    const stepStartedAt = now();
    let decision: StepDecision | undefined;
    let began = false;

    try {
      // Reading the input is inside the try because a missing or unreadable
      // export is a step failure like any other, and must abort the run with a
      // report rather than an unhandled rejection.
      const checksum = await step.checksum();
      decision = decideStep(await ledger.read(step.name), checksum);

      if (decision.action === 'skip') {
        logger.info({ step: step.name, reason: decision.reason }, 'step skipped');
        reports.push({ name: step.name, outcome: 'skipped', reason: decision.reason });
        continue;
      }

      if (dryRun) {
        reports.push({ name: step.name, outcome: 'pending', reason: decision.reason });
        continue;
      }

      logger.info({ step: step.name, reason: decision.reason }, 'step starting');
      await ledger.begin({ name: step.name, runId, checksum });
      began = true;

      const result = await step.run();
      await step.verify?.(result);

      const durationMs = now() - stepStartedAt;
      await ledger.succeed({
        name: step.name,
        runId,
        checksum,
        rowsWritten: result.rowsWritten,
        durationMs,
        detail: result.detail ?? {},
      });

      logger.info(
        { step: step.name, rowsWritten: result.rowsWritten, durationMs },
        'step completed',
      );
      reports.push({
        name: step.name,
        outcome: 'completed',
        reason: decision.reason,
        rowsWritten: result.rowsWritten,
        durationMs,
      });
    } catch (error) {
      const durationMs = now() - stepStartedAt;
      const message = messageOf(error);

      // Only a step that actually started may be marked failed. Otherwise a
      // misconfigured source path — which changed nothing — would flip an
      // already-completed step to failed, and the backend would then report
      // itself as unmigrated and refuse ingest for no reason.
      //
      // Recording is best-effort beyond that: if the database is what broke,
      // the report still has to reach the deployment log.
      if (began) {
        await ledger
          .fail({ name: step.name, runId, durationMs, error: message })
          .catch((ledgerError: unknown) => {
            logger.error(
              { step: step.name, err: messageOf(ledgerError) },
              'could not record step failure',
            );
          });
      }

      logger.error({ step: step.name, err: message, durationMs }, 'step failed, aborting run');
      reports.push({
        name: step.name,
        outcome: 'failed',
        reason: decision?.reason ?? 'could not read the step input',
        durationMs,
        error: message,
      });
      failed = true;
    }
  }

  return {
    runId,
    status: failed ? 'failed' : 'complete',
    dryRun,
    durationMs: now() - startedAt,
    steps: reports,
  };
}

export function formatReport(report: BootstrapReport): string {
  const lines = report.steps.map((step) => {
    const suffix = [
      step.rowsWritten === undefined ? undefined : `${step.rowsWritten} rows`,
      step.durationMs === undefined ? undefined : `${step.durationMs} ms`,
      step.error,
    ]
      .filter(Boolean)
      .join(', ');

    return `  ${step.outcome.padEnd(9)} ${step.name.padEnd(24)} ${step.reason}${
      suffix ? ` (${suffix})` : ''
    }`;
  });

  return [
    `bootstrap ${report.status}${report.dryRun ? ' (dry run)' : ''} in ${report.durationMs} ms`,
    `run id ${report.runId}`,
    ...lines,
  ].join('\n');
}
