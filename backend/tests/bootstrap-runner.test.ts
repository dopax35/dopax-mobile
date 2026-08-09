import { describe, expect, it } from 'vitest';
import {
  decideStep,
  runBootstrap,
  type BootstrapStep,
  type StepLedger,
  type StepRecord,
  type StepResult,
} from '../src/domain/bootstrap/runner.js';

function memoryLedger(initial: StepRecord[] = []) {
  const rows = new Map(initial.map((record) => [record.name, record]));
  const calls: string[] = [];

  const ledger: StepLedger = {
    async read(name) {
      return rows.get(name);
    },
    async begin({ name, checksum }) {
      calls.push(`begin:${name}`);
      rows.set(name, { name, status: 'running', inputChecksum: checksum });
    },
    async succeed({ name, checksum }) {
      calls.push(`succeed:${name}`);
      rows.set(name, { name, status: 'completed', inputChecksum: checksum });
    },
    async fail({ name }) {
      calls.push(`fail:${name}`);
      rows.set(name, {
        name,
        status: 'failed',
        inputChecksum: rows.get(name)?.inputChecksum ?? null,
      });
    },
  };

  return { ledger, rows, calls };
}

interface TestStep extends BootstrapStep {
  runs: number;
}

function testStep(
  name: string,
  options: {
    checksum?: string;
    run?: () => Promise<StepResult>;
    verify?: () => Promise<void>;
  } = {},
): TestStep {
  const step: TestStep = {
    name,
    description: name,
    runs: 0,
    async checksum() {
      return options.checksum ?? `${name}-v1`;
    },
    async run() {
      step.runs += 1;
      return options.run ? options.run() : { rowsWritten: 1 };
    },
  };

  if (options.verify) step.verify = options.verify;

  return step;
}

const run = (steps: BootstrapStep[], ledger: StepLedger, dryRun = false) =>
  runBootstrap(steps, { ledger, runId: 'run-1', dryRun });

describe('decideStep', () => {
  it('runs a step that has never run', () => {
    expect(decideStep(undefined, 'abc').action).toBe('run');
  });

  it('skips a completed step whose input is unchanged', () => {
    const record: StepRecord = { name: 's', status: 'completed', inputChecksum: 'abc' };
    expect(decideStep(record, 'abc').action).toBe('skip');
  });

  it('replays a completed step when the source export has changed', () => {
    const record: StepRecord = { name: 's', status: 'completed', inputChecksum: 'abc' };
    expect(decideStep(record, 'def')).toEqual({
      action: 'run',
      reason: 'input changed since last run',
    });
  });

  it('retries a failed step', () => {
    const record: StepRecord = { name: 's', status: 'failed', inputChecksum: 'abc' };
    expect(decideStep(record, 'abc').action).toBe('run');
  });

  it('resumes a step left mid-flight by a crashed run', () => {
    const record: StepRecord = { name: 's', status: 'running', inputChecksum: 'abc' };
    expect(decideStep(record, 'abc')).toEqual({
      action: 'run',
      reason: 'resuming after an interrupted run',
    });
  });
});

describe('runBootstrap', () => {
  it('runs steps in order and records what each wrote', async () => {
    const order: string[] = [];
    const steps = ['one', 'two', 'three'].map((name) =>
      testStep(name, {
        run: async () => {
          order.push(name);
          return { rowsWritten: 10 };
        },
      }),
    );
    const { ledger } = memoryLedger();

    const report = await run(steps, ledger);

    expect(order).toEqual(['one', 'two', 'three']);
    expect(report.status).toBe('complete');
    expect(report.steps.map((s) => s.outcome)).toEqual(['completed', 'completed', 'completed']);
    expect(report.steps[0]!.rowsWritten).toBe(10);
  });

  it('is safe to run twice: the second pass skips everything', async () => {
    const steps = [testStep('one'), testStep('two')];
    const { ledger } = memoryLedger();

    await run(steps, ledger);
    const second = await run(steps, ledger);

    expect(steps.map((s) => s.runs)).toEqual([1, 1]);
    expect(second.steps.every((s) => s.outcome === 'skipped')).toBe(true);
    expect(second.status).toBe('complete');
  });

  it('replays a step when its source export changes', async () => {
    const { ledger } = memoryLedger();
    await run([testStep('one', { checksum: 'v1' })], ledger);

    const replayed = testStep('one', { checksum: 'v2' });
    const report = await run([replayed], ledger);

    expect(replayed.runs).toBe(1);
    expect(report.steps[0]!.outcome).toBe('completed');
  });

  it('stops at the first failure and leaves later steps untouched', async () => {
    const first = testStep('one');
    const failing = testStep('two', {
      run: async () => {
        throw new Error('drive unreachable');
      },
    });
    const later = testStep('three');
    const { ledger, calls } = memoryLedger();

    const report = await run([first, failing, later], ledger);

    expect(report.status).toBe('failed');
    expect(report.steps.map((s) => s.outcome)).toEqual(['completed', 'failed', 'not_run']);
    expect(report.steps[1]!.error).toBe('drive unreachable');
    expect(later.runs).toBe(0);
    expect(calls).toEqual(['begin:one', 'succeed:one', 'begin:two', 'fail:two']);
  });

  it('fails the step when reconciliation does not add up', async () => {
    const step = testStep('one', {
      verify: async () => {
        throw new Error('account count mismatch: 43 in the export, 41 in the database');
      },
    });
    const { ledger, rows } = memoryLedger();

    const report = await run([step], ledger);

    expect(report.status).toBe('failed');
    expect(report.steps[0]!.error).toContain('account count mismatch');
    expect(rows.get('one')!.status).toBe('failed');
  });

  it('resumes at the interrupted step rather than replaying the ones before it', async () => {
    const done = testStep('one');
    const interrupted = testStep('two');
    const { ledger } = memoryLedger([
      { name: 'one', status: 'completed', inputChecksum: 'one-v1' },
      { name: 'two', status: 'running', inputChecksum: 'two-v1' },
    ]);

    const report = await run([done, interrupted], ledger);

    expect(done.runs).toBe(0);
    expect(interrupted.runs).toBe(1);
    expect(report.steps.map((s) => s.outcome)).toEqual(['skipped', 'completed']);
  });

  it('writes nothing during a dry run', async () => {
    const step = testStep('one');
    const { ledger, calls, rows } = memoryLedger();

    const report = await run([step], ledger, true);

    expect(step.runs).toBe(0);
    expect(calls).toEqual([]);
    expect(rows.size).toBe(0);
    expect(report.steps[0]!.outcome).toBe('pending');
    expect(report.dryRun).toBe(true);
  });

  it('reports an unreadable input as a failed step instead of throwing out of the run', async () => {
    const missingSource: BootstrapStep = {
      name: 'one',
      description: 'one',
      async checksum() {
        throw new Error('cannot read the Firebase Auth export at /srv/users.json');
      },
      async run() {
        return { rowsWritten: 0 };
      },
    };
    const later = testStep('two');
    const { ledger, calls } = memoryLedger();

    const report = await run([missingSource, later], ledger);

    expect(report.status).toBe('failed');
    expect(report.steps[0]!.error).toContain('cannot read the Firebase Auth export');
    expect(report.steps[1]!.outcome).toBe('not_run');
    expect(later.runs).toBe(0);
    expect(calls).toEqual([]);
  });

  it('leaves a completed step alone when a later run cannot even read its input', async () => {
    const unreadable: BootstrapStep = {
      name: 'one',
      description: 'one',
      async checksum() {
        throw new Error('MIGRATION_SOURCE_DIR points at an empty volume');
      },
      async run() {
        return { rowsWritten: 0 };
      },
    };
    const { ledger, rows } = memoryLedger([
      { name: 'one', status: 'completed', inputChecksum: 'one-v1' },
    ]);

    const report = await run([unreadable], ledger);

    expect(report.status).toBe('failed');
    // The record must survive: nothing was attempted, so nothing regressed.
    expect(rows.get('one')).toEqual({
      name: 'one',
      status: 'completed',
      inputChecksum: 'one-v1',
    });
  });

  it('still reports a failure when the ledger itself cannot record it', async () => {
    const { ledger } = memoryLedger();
    const brokenLedger: StepLedger = {
      ...ledger,
      fail: async () => {
        throw new Error('database gone');
      },
    };
    const step = testStep('one', {
      run: async () => {
        throw new Error('import blew up');
      },
    });

    const report = await run([step], brokenLedger);

    expect(report.status).toBe('failed');
    expect(report.steps[0]!.error).toBe('import blew up');
  });
});
