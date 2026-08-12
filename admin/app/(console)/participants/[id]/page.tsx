import Link from 'next/link';
import { CoverageLegend, CoverageStrip } from '@/components/coverage';
import { Badge, Card, Cell, EmptyState, Meter, Notice, Table, statusTone } from '@/components/ui';
import { adminFetch } from '@/lib/api';
import {
  daysAgo,
  formatBytes,
  formatDate,
  formatDateTime,
  formatDuration,
  formatNumber,
  formatPercent,
} from '@/lib/format';
import type { ParticipantDetail } from '@/lib/types';

export default async function ParticipantPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ windowDays?: string }>;
}) {
  const [{ id }, query] = await Promise.all([params, searchParams]);
  const windowDays = Math.min(365, Math.max(7, Number(query.windowDays ?? '90') || 90));

  const detail = await adminFetch<ParticipantDetail>(`/participants/${id}`, {
    query: { windowDays },
  });

  const { participant, adherence, uploads, events, testSessions, consents, profile, identities } =
    detail;

  const uploadDays = [...new Set(uploads.map((upload) => upload.collectionDate))];
  const activeConsent = consents.find((consent) => !consent.revokedAt);

  return (
    <div className="space-y-6">
      <header className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <Link
            href="/participants"
            className="text-xs text-ink-faint underline-offset-2 hover:text-ink hover:underline"
          >
            ← All participants
          </Link>
          <h1 className="mt-2 font-mono text-xl font-semibold text-ink">
            {participant.participantCode}
          </h1>
          <div className="mt-2 flex flex-wrap items-center gap-2">
            <Badge tone={statusTone(participant.status)}>
              {participant.status.replace(/_/g, ' ')}
            </Badge>
            {participant.isTestAccount && <Badge>test account</Badge>}
            {adherence.platforms.map((platform) => (
              <Badge key={platform} tone="accent">
                {platform}
              </Badge>
            ))}
            {participant.email && (
              <span className="font-mono text-xs text-ink-faint">{participant.email}</span>
            )}
          </div>
        </div>

        <form className="flex items-center gap-2 text-xs text-ink-dim">
          <label htmlFor="windowDays">Window</label>
          <select
            id="windowDays"
            name="windowDays"
            defaultValue={String(windowDays)}
            className="rounded-lg border border-line bg-canvas px-2.5 py-1.5 text-ink outline-none focus:border-accent/60"
          >
            {[30, 60, 90, 180, 365].map((days) => (
              <option key={days} value={days}>
                {days} days
              </option>
            ))}
          </select>
          <button
            type="submit"
            className="rounded-lg border border-line bg-surface-2 px-2.5 py-1.5 text-ink transition hover:border-accent/50"
          >
            Apply
          </button>
        </form>
      </header>

      {participant.status === 'needs_id_resolution' && (
        <Notice tone="bad" title="This participant shares a legacy participant code">
          Their historical Drive uploads cannot be attributed automatically, so the contested code
          is deliberately excluded from upload routing and nothing is guessed. A human has to split
          the affected days between the two accounts; record the decision in the{' '}
          <Link href="/operations" className="text-accent hover:underline">
            data-quality queue
          </Link>
          .
        </Notice>
      )}

      <div className="grid gap-6 lg:grid-cols-3">
        <Card
          title="Adherence"
          description={`${formatDate(adherence.window.from)} → ${formatDate(adherence.window.to)}`}
          className="lg:col-span-2"
        >
          <div className="grid gap-5 sm:grid-cols-3">
            <div>
              <p className="text-[11px] uppercase tracking-widest text-ink-faint">Coverage</p>
              <p className="tabular mt-1.5 text-2xl font-semibold text-ink">
                {formatPercent(adherence.coverage)}
              </p>
              <div className="mt-2">
                <Meter
                  fraction={adherence.coverage}
                  label={`${formatNumber(adherence.daysWithUpload)} of ${formatNumber(
                    adherence.expectedDays,
                  )} days`}
                />
              </div>
            </div>

            <div>
              <p className="text-[11px] uppercase tracking-widest text-ink-faint">Last upload</p>
              <p className="mt-1.5 text-2xl font-semibold text-ink">
                {adherence.lastUploadDate ? formatDate(adherence.lastUploadDate) : '—'}
              </p>
              <p className="mt-2 text-xs text-ink-dim">{daysAgo(adherence.lastUploadDate)}</p>
            </div>

            <div>
              <p className="text-[11px] uppercase tracking-widest text-ink-faint">Current gap</p>
              <p
                className={`tabular mt-1.5 text-2xl font-semibold ${
                  adherence.currentGapDays > 7
                    ? 'text-bad'
                    : adherence.currentGapDays > 0
                      ? 'text-warn'
                      : 'text-good'
                }`}
              >
                {adherence.currentGapDays === 0 ? 'none' : `${adherence.currentGapDays}d`}
              </p>
              <p className="mt-2 text-xs text-ink-dim">
                {adherence.currentGapDays > 0
                  ? 'consecutive days with no upload'
                  : 'uploaded on the most recent day'}
              </p>
            </div>
          </div>

          <div className="mt-6 space-y-3 border-t border-line pt-4">
            <CoverageStrip
              from={adherence.window.from}
              to={adherence.window.to}
              presentDays={uploadDays}
              firstUploadDate={participant.firstUploadDate}
            />
            <CoverageLegend />
          </div>

          {adherence.gaps.length > 0 && (
            <div className="mt-5 border-t border-line pt-4">
              <p className="text-[11px] uppercase tracking-widest text-ink-faint">
                Longest gaps in the window
              </p>
              <ul className="mt-2 space-y-1 text-xs text-ink-dim">
                {adherence.gaps.slice(0, 5).map((gap) => (
                  <li key={gap.from} className="tabular">
                    {formatDate(gap.from)} → {formatDate(gap.to)}
                    <span className="ml-2 text-ink-faint">{gap.days} days</span>
                  </li>
                ))}
              </ul>
            </div>
          )}
        </Card>

        <div className="space-y-6">
          <Card title="Profile">
            {profile ? (
              <dl className="space-y-2 text-sm">
                {[
                  ['Age', profile.age ?? '—'],
                  ['Gender', profile.gender ?? '—'],
                  ['Dominant hand', profile.dominantHand ?? '—'],
                  ['Affected side', profile.affectedSide ?? '—'],
                  ['Revision', profile.revision],
                ].map(([label, value]) => (
                  <div key={String(label)} className="flex justify-between gap-3">
                    <dt className="text-ink-faint">{label}</dt>
                    <dd className="text-ink-dim">{String(value)}</dd>
                  </div>
                ))}
              </dl>
            ) : (
              <EmptyState title="No profile imported">
                Either the participant never completed onboarding, or their Firestore document was
                not part of the import.
              </EmptyState>
            )}
          </Card>

          <Card title="Consent">
            {activeConsent ? (
              <div className="space-y-2 text-sm">
                <div className="flex justify-between gap-3">
                  <span className="text-ink-faint">Version</span>
                  <span className="font-mono text-xs text-ink-dim">
                    {activeConsent.documentVersion}
                  </span>
                </div>
                <div className="flex justify-between gap-3">
                  <span className="text-ink-faint">Granted</span>
                  <span className="tabular text-xs text-ink-dim">
                    {formatDateTime(activeConsent.grantedAt)}
                  </span>
                </div>
                <div className="flex justify-between gap-3">
                  <span className="text-ink-faint">Signed</span>
                  <span className="text-xs text-ink-dim">{activeConsent.signatureName}</span>
                </div>
                {consents.length > 1 && (
                  <p className="border-t border-line pt-2 text-xs text-ink-faint">
                    {consents.length} consent records in total; the trail is append-only.
                  </p>
                )}
              </div>
            ) : (
              <EmptyState title="No consent record" />
            )}
          </Card>

          <Card title="Accounts">
            <ul className="space-y-3 text-xs">
              {identities.map((identity, index) => (
                <li key={index} className="space-y-1">
                  <Badge tone="accent">{identity.provider}</Badge>
                  {identity.email && (
                    <p className="font-mono text-ink-dim">{identity.email}</p>
                  )}
                  <p className="text-ink-faint">
                    last sign-in {formatDateTime(identity.lastSignInAt)}
                  </p>
                </li>
              ))}
            </ul>
          </Card>
        </div>
      </div>

      <Card
        title="Uploads"
        description={`${formatNumber(uploads.length)} participant-days recorded`}
      >
        <Table
          head={['Date', 'Platform', 'Status', 'Source', 'Size', 'File']}
          empty={
            uploads.length === 0 ? (
              <div className="px-5 pt-4">
                <EmptyState title="No uploads recorded for this participant" />
              </div>
            ) : undefined
          }
        >
          {uploads.slice(0, 60).map((upload) => (
            <tr key={upload.id}>
              <Cell mono>{formatDate(upload.collectionDate)}</Cell>
              <Cell>
                <Badge>{upload.platform}</Badge>
              </Cell>
              <Cell>
                <Badge tone={statusTone(upload.status)} title={upload.error ?? undefined}>
                  {upload.status}
                </Badge>
              </Cell>
              <Cell dim>{upload.source}</Cell>
              <Cell dim>
                <span className="tabular">{formatBytes(upload.bytes)}</span>
              </Cell>
              <Cell mono dim className="max-w-xs truncate">
                {upload.filename}
              </Cell>
            </tr>
          ))}
        </Table>
      </Card>

      <div className="grid gap-6 lg:grid-cols-2">
        <Card title="Test sessions" description="Motor and cognitive tests actually performed">
          {testSessions.length === 0 ? (
            <EmptyState title="No test sessions">
              These are produced by stream-parsing the uploaded ZIPs. Until that runs, the raw CSVs
              remain inside the archives and nothing is queryable here.
            </EmptyState>
          ) : (
            <Table head={['Test', 'Started', 'Duration', 'Completed']}>
              {testSessions.slice(0, 30).map((session, index) => (
                <tr key={index}>
                  <Cell>{session.testType.replace(/_/g, ' ')}</Cell>
                  <Cell mono dim>
                    {formatDateTime(session.startedAt)}
                  </Cell>
                  <Cell dim>{formatDuration(session.durationMs)}</Cell>
                  <Cell>
                    <Badge tone={session.completed ? 'good' : 'warn'}>
                      {session.completed ? 'yes' : 'no'}
                    </Badge>
                  </Cell>
                </tr>
              ))}
            </Table>
          )}
        </Card>

        <Card title="Recent activity" description="App events, newest first">
          {events.length === 0 ? (
            <EmptyState title="No events recorded">
              Event telemetry starts arriving once the mobile clients dual-write to this backend.
              Until then, upload history is the only signal of whether someone is still
              participating.
            </EmptyState>
          ) : (
            <Table head={['When', 'Event', 'App version']}>
              {events.slice(0, 30).map((event, index) => (
                <tr key={index}>
                  <Cell mono dim>
                    {formatDateTime(event.occurredAt)}
                  </Cell>
                  <Cell>{event.eventType.replace(/_/g, ' ')}</Cell>
                  <Cell dim>{event.appVersion ?? '—'}</Cell>
                </tr>
              ))}
            </Table>
          )}
        </Card>
      </div>
    </div>
  );
}
