import { FlipGate } from '@/components/coverage';
import { Badge, Card, Cell, EmptyState, Notice, Table, statusTone } from '@/components/ui';
import { adminFetch, Forbidden } from '@/lib/api';
import { formatBytes, formatDateTime, formatDuration, formatNumber } from '@/lib/format';
import { getSession, hasRole } from '@/lib/session';
import type { BootstrapStep, DataQuality, FlipReadiness, ReconciliationRun } from '@/lib/types';
import { ResolveForm } from './resolve-form';

export default async function OperationsPage() {
  const session = await getSession();
  const canResolve = session ? hasRole(session, 'admin') : false;
  const canSeeQueue = session ? hasRole(session, 'researcher') : false;

  const [reconciliation, bootstrap, dataQuality] = await Promise.all([
    adminFetch<{ runs: ReconciliationRun[]; flip: FlipReadiness }>('/reconciliation'),
    adminFetch<{ steps: BootstrapStep[] }>('/bootstrap'),
    canSeeQueue
      ? adminFetch<DataQuality>('/data-quality').catch((error) => {
          if (error instanceof Forbidden) return null;
          throw error;
        })
      : Promise.resolve(null),
  ]);

  return (
    <div className="space-y-6">
      <header>
        <h1 className="text-xl font-semibold text-ink">Operations</h1>
        <p className="mt-1 text-sm text-ink-dim">
          Migration state, reconciliation against the legacy Google Drive corpus, and everything
          waiting on a human decision.
        </p>
      </header>

      <div className="grid gap-6 lg:grid-cols-3">
        <Card title="Flip readiness" description="R3 — the gate to backend-only">
          <FlipGate flip={reconciliation.flip} />
        </Card>

        <Card
          title="First-run migration"
          description="R5 — the step ledger production resumes from"
          className="lg:col-span-2"
        >
          {bootstrap.steps.length === 0 ? (
            <EmptyState title="No bootstrap steps recorded">
              This database has never run the bootstrap release task.
            </EmptyState>
          ) : (
            <Table head={['Step', 'Status', 'Rows', 'Attempts', 'Duration', 'Finished']}>
              {bootstrap.steps.map((step) => (
                <tr key={step.name}>
                  <Cell mono>{step.name}</Cell>
                  <Cell>
                    <Badge tone={statusTone(step.status)} title={step.error ?? undefined}>
                      {step.status}
                    </Badge>
                  </Cell>
                  <Cell dim>
                    <span className="tabular">{formatNumber(step.rowsWritten)}</span>
                  </Cell>
                  <Cell dim>
                    <span className="tabular">{step.attempts}</span>
                  </Cell>
                  <Cell dim>{formatDuration(step.durationMs)}</Cell>
                  <Cell dim>
                    <span className="tabular text-xs">{formatDateTime(step.completedAt)}</span>
                  </Cell>
                </tr>
              ))}
            </Table>
          )}
        </Card>
      </div>

      <Card
        title="Reconciliation runs"
        description="Drive objects against database uploads, newest first"
      >
        {reconciliation.runs.length === 0 ? (
          <EmptyState title="Nothing has reconciled yet">
            Until a run is recorded there is no evidence that this backend holds the same corpus as
            the Drive folder, so the legacy pipeline stays authoritative.
          </EmptyState>
        ) : (
          <Table head={['Run', 'Mode', 'Result', 'Drive objects', 'Uploads', 'Parsed', 'Volume']}>
            {reconciliation.runs.map((run) => {
              const missing = run.driveObjects - run.dbUploads;

              return (
                <tr key={run.id}>
                  <Cell mono dim>
                    {formatDateTime(run.runAt)}
                  </Cell>
                  <Cell dim>{run.mode}</Cell>
                  <Cell>
                    <Badge tone={statusTone(run.status)}>{run.status}</Badge>
                  </Cell>
                  <Cell dim>
                    <span className="tabular">{formatNumber(run.driveObjects)}</span>
                  </Cell>
                  <Cell>
                    <span className="tabular text-ink-dim">{formatNumber(run.dbUploads)}</span>
                    {missing !== 0 && (
                      <span
                        className="ml-2 text-xs text-warn"
                        title="Drive objects with no upload row — recorded as exceptions, never dropped"
                      >
                        {missing > 0 ? `${missing} unaccounted` : `${-missing} extra`}
                      </span>
                    )}
                  </Cell>
                  <Cell dim>
                    <span className="tabular">{formatNumber(run.dbParsed)}</span>
                  </Cell>
                  <Cell dim>
                    <span className="tabular">{formatBytes(run.driveBytes)}</span>
                  </Cell>
                </tr>
              );
            })}
          </Table>
        )}
      </Card>

      {!canSeeQueue && (
        <Notice tone="accent" title="The data-quality queue needs the researcher role">
          It lists participant codes and Drive filenames, which are participant data.
        </Notice>
      )}

      {dataQuality?.schemaOutOfDate && (
        <Notice tone="bad" title={`Missing table: ${dataQuality.schemaOutOfDate.missing}`}>
          {dataQuality.schemaOutOfDate.detail} Apply migration{' '}
          <code className="font-mono">{dataQuality.schemaOutOfDate.migration}</code> to this
          database.
        </Notice>
      )}

      {dataQuality && (
        <>
          <Card
            title="Contested participant codes"
            description="One legacy code matching more than one account"
          >
            {dataQuality.conflicts.length === 0 ? (
              <EmptyState title="No contested codes" />
            ) : (
              <ul className="space-y-4">
                {dataQuality.conflicts.map((conflict) => (
                  <li key={conflict.id} className="rounded-lg border border-line px-4 py-3">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="font-mono text-sm text-ink">{conflict.legacyCode}</span>
                      <Badge tone={conflict.resolvedAt ? 'good' : 'bad'}>
                        {conflict.resolvedAt ? 'resolved' : 'open'}
                      </Badge>
                      <span className="text-xs text-ink-faint">
                        detected {formatDateTime(conflict.detectedAt)}
                      </span>
                    </div>

                    <p className="mt-2 text-xs leading-relaxed text-ink-dim">
                      Claimed by {conflict.participantCodes.length} participants:{' '}
                      <span className="font-mono">{conflict.participantCodes.join(', ')}</span>.
                      Uploads matching this code fail to resolve rather than being attributed to
                      the wrong person.
                    </p>

                    {conflict.resolutionNote && (
                      <p className="mt-2 whitespace-pre-line rounded-md bg-surface-2 px-3 py-2 text-xs text-ink-dim">
                        {conflict.resolutionNote}
                      </p>
                    )}

                    {!conflict.resolvedAt && canResolve && (
                      <ResolveForm
                        id={conflict.id}
                        kind="conflict"
                        placeholder="How the affected days split between the accounts, and on what evidence (upload dates, platform)…"
                      />
                    )}
                  </li>
                ))}
              </ul>
            )}
          </Card>

          <Card
            title="Unattributable Drive objects"
            description="Every object the import could not turn into an upload row"
          >
            {dataQuality.exceptions.length === 0 ? (
              <EmptyState title="Every Drive object is accounted for">
                The import enforces that objects in the manifest equal uploads plus exceptions, so
                an empty list here means nothing was silently skipped.
              </EmptyState>
            ) : (
              <ul className="space-y-3">
                {dataQuality.exceptions.map((exception) => (
                  <li key={exception.id} className="rounded-lg border border-line px-4 py-3">
                    <div className="flex flex-wrap items-center gap-2">
                      <Badge tone="warn">{exception.reason.replace(/_/g, ' ')}</Badge>
                      <span className="font-mono text-xs text-ink-dim">{exception.filename}</span>
                      <span className="text-xs text-ink-faint">
                        {formatBytes(exception.bytes)}
                      </span>
                    </div>

                    {exception.resolutionNote && (
                      <p className="mt-2 whitespace-pre-line rounded-md bg-surface-2 px-3 py-2 text-xs text-ink-dim">
                        {exception.resolutionNote}
                      </p>
                    )}

                    {!exception.resolvedAt && canResolve && (
                      <ResolveForm
                        id={exception.id}
                        kind="exception"
                        placeholder="What this object is and what should happen to it…"
                      />
                    )}
                  </li>
                ))}
              </ul>
            )}
          </Card>
        </>
      )}
    </div>
  );
}
