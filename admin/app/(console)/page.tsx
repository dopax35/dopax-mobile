import Link from 'next/link';
import { FlipGate } from '@/components/coverage';
import { Badge, Card, EmptyState, Notice, StatTile, statusTone } from '@/components/ui';
import { adminFetch } from '@/lib/api';
import { formatBytes, formatDate, formatDateTime, formatNumber } from '@/lib/format';
import type { Overview } from '@/lib/types';

export default async function OverviewPage() {
  const overview = await adminFetch<Overview>('/overview');
  const { enrolment, uploads, activity, dataQuality, reconciliation, pipeline } = overview;

  const realParticipants = enrolment.total - enrolment.testAccounts;
  const openQueue =
    dataQuality.openConflicts +
    dataQuality.openExceptions +
    dataQuality.participantsNeedingIdResolution;

  return (
    <div className="space-y-6">
      <header>
        <h1 className="text-xl font-semibold text-ink">Study overview</h1>
        <p className="mt-1 text-sm text-ink-dim">
          Enrolment, upload health, and the state of the migration to this backend.
        </p>
      </header>

      {/*
        The single most important thing a reader needs to know during the
        migration: whether an empty activity panel means "nobody is active" or
        "the pipeline that fills it has not run".
      */}
      {pipeline.activityDependsOnParse && (
        <Notice tone="accent" title="Activity data has not been ingested yet">
          {formatNumber(uploads.total)} uploads are catalogued from the Google Drive corpus, but
          none have been stream-parsed, so there are no events, test sessions, or daily summaries
          to show yet. Enrolment, upload coverage and the data-quality queue below are real. Run
          the ZIP parse step in the backend to fill the rest.
        </Notice>
      )}

      {pipeline.schemaOutOfDate && (
        <Notice tone="warn" title="This database is behind the schema">
          <code className="text-ink-dim">{pipeline.schemaOutOfDate.missing}</code> is missing, so
          unattributable Drive objects are not counted in the queue below and the real figure may
          be higher than shown. Apply migration{' '}
          <code className="text-ink-dim">{pipeline.schemaOutOfDate.migration}</code> to restore it.
        </Notice>
      )}

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatTile
          label="Participants"
          value={formatNumber(realParticipants)}
          hint={`${formatNumber(enrolment.total)} accounts in total, ${formatNumber(
            enrolment.testAccounts,
          )} flagged as test`}
        />
        <StatTile
          label="With uploads"
          value={formatNumber(uploads.participantsWithUploads)}
          hint={
            uploads.earliestDate
              ? `${formatDate(uploads.earliestDate)} → ${formatDate(uploads.latestDate)}`
              : 'no uploads recorded'
          }
        />
        <StatTile
          label="Uploads"
          value={formatNumber(uploads.total)}
          hint={`${formatBytes(uploads.bytes)} catalogued`}
        />
        <StatTile
          label="Needs a decision"
          value={formatNumber(openQueue)}
          tone={openQueue > 0 ? 'warn' : 'good'}
          hint={
            openQueue > 0 ? (
              <Link href="/operations" className="text-accent underline-offset-2 hover:underline">
                Open the data-quality queue
              </Link>
            ) : (
              'Nothing waiting on a human'
            )
          }
        />
      </div>

      <div className="grid gap-6 lg:grid-cols-3">
        <Card
          title="Flip to backend-only"
          description="R3 — fourteen consecutive clean reconciliation runs"
        >
          <FlipGate flip={reconciliation.flip} />

          {reconciliation.latest && (
            <dl className="mt-5 space-y-1.5 border-t border-line pt-4 text-xs">
              <div className="flex justify-between gap-3">
                <dt className="text-ink-faint">Last run</dt>
                <dd className="tabular text-ink-dim">
                  {formatDateTime(reconciliation.latest.runAt)}
                </dd>
              </div>
              <div className="flex justify-between gap-3">
                <dt className="text-ink-faint">Result</dt>
                <dd>
                  <Badge tone={statusTone(reconciliation.latest.status)}>
                    {reconciliation.latest.status}
                  </Badge>
                </dd>
              </div>
              <div className="flex justify-between gap-3">
                <dt className="text-ink-faint">Drive vs database</dt>
                <dd className="tabular text-ink-dim">
                  {formatNumber(reconciliation.latest.driveObjects)} objects /{' '}
                  {formatNumber(reconciliation.latest.dbUploads)} uploads
                </dd>
              </div>
            </dl>
          )}
        </Card>

        <Card title="Upload pipeline" description="Where the corpus is in the ingest path">
          <dl className="space-y-2 text-sm">
            {Object.entries(uploads.byStatus).length === 0 && (
              <p className="text-xs text-ink-faint">No uploads recorded.</p>
            )}
            {Object.entries(uploads.byStatus).map(([status, count]) => (
              <div key={status} className="flex items-center justify-between gap-3">
                <dt>
                  <Badge tone={statusTone(status)}>{status}</Badge>
                </dt>
                <dd className="tabular text-ink-dim">{formatNumber(count)}</dd>
              </div>
            ))}
          </dl>

          <div className="mt-4 border-t border-line pt-3 text-xs text-ink-faint">
            By source:{' '}
            {Object.entries(uploads.bySource)
              .map(([source, count]) => `${source} ${formatNumber(count)}`)
              .join(' · ') || '—'}
          </div>
        </Card>

        <Card title="Participant activity" description="Filled by the ZIP parse and by clients">
          <dl className="space-y-2.5 text-sm">
            {[
              ['Events', activity.events],
              ['Test sessions', activity.testSessions],
              ['Daily summaries', activity.dailySummaries],
            ].map(([label, count]) => (
              <div key={String(label)} className="flex items-center justify-between gap-3">
                <dt className="text-ink-dim">{label}</dt>
                <dd className={`tabular ${count === 0 ? 'text-ink-faint' : 'text-ink'}`}>
                  {formatNumber(count as number)}
                </dd>
              </div>
            ))}
          </dl>

          {activity.events === 0 && (
            <p className="mt-4 border-t border-line pt-3 text-xs leading-relaxed text-ink-faint">
              Clients do not emit events yet — that lands with the dual-write client work. Until
              then adherence is measured from upload history alone.
            </p>
          )}
        </Card>
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        <Card title="Sign-in providers" description="How the enrolled accounts authenticate">
          <div className="flex flex-wrap gap-2">
            {Object.entries(enrolment.byProvider).map(([provider, count]) => (
              <Badge key={provider}>
                {provider} · {formatNumber(count)}
              </Badge>
            ))}
          </div>
          <p className="mt-4 text-xs leading-relaxed text-ink-faint">
            Firebase remains the identity provider. This backend only verifies tokens; no
            credential was migrated.
          </p>
        </Card>

        <Card title="Enrolment status">
          {Object.entries(enrolment.byStatus).length === 0 ? (
            <EmptyState title="No participants imported" />
          ) : (
            <dl className="space-y-2 text-sm">
              {Object.entries(enrolment.byStatus).map(([status, count]) => (
                <div key={status} className="flex items-center justify-between gap-3">
                  <dt>
                    <Badge tone={statusTone(status)}>{status.replace(/_/g, ' ')}</Badge>
                  </dt>
                  <dd className="tabular text-ink-dim">{formatNumber(count)}</dd>
                </div>
              ))}
            </dl>
          )}

          {dataQuality.participantsNeedingIdResolution > 0 && (
            <p className="mt-4 border-t border-line pt-3 text-xs leading-relaxed text-warn">
              {formatNumber(dataQuality.participantsNeedingIdResolution)} participants share a
              legacy participant code, so their uploads cannot be attributed automatically. They
              are held out of upload routing until a human splits them.
            </p>
          )}
        </Card>
      </div>
    </div>
  );
}
