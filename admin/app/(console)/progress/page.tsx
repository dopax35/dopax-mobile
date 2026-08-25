import Link from 'next/link';
import { Badge, Card, Cell, EmptyState, StatTile, Table } from '@/components/ui';
import { adminFetch } from '@/lib/api';
import { formatBytes, formatDate, formatNumber } from '@/lib/format';
import type { ProgressSummary } from '@/lib/types';

export default async function ProgressPage({
  searchParams,
}: {
  searchParams: Promise<{ tests?: string }>;
}) {
  const params = await searchParams;
  const includeTests = params.tests === 'true';

  const progress = await adminFetch<ProgressSummary>('/progress', {
    query: { includeTestAccounts: includeTests ? 'true' : 'false' },
  });

  return (
    <div className="space-y-6">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-xl font-semibold text-ink">Active User Progress Review</h1>
          <p className="mt-1 text-sm text-ink-dim">
            Firebase registered users correlated with Google Drive file loads, active tests, medication logs, and data integrity audits.
          </p>
        </div>

        <form className="flex items-center gap-2">
          <label className="flex items-center gap-2 text-xs text-ink-dim">
            <input
              type="checkbox"
              name="tests"
              value="true"
              defaultChecked={includeTests}
              className="size-3.5 accent-[oklch(0.72_0.13_215)]"
            />
            Include test accounts
          </label>
          <button
            type="submit"
            className="rounded-lg border border-line bg-surface-2 px-3 py-1.5 text-xs text-ink transition hover:border-accent/50"
          >
            Apply
          </button>
        </form>
      </header>

      {/* KPI Tiles */}
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-6">
        <StatTile
          label="Registered Users"
          value={formatNumber(progress.totalRegistered)}
          hint="Firebase Auth accounts"
        />
        <StatTile
          label="Proper Usage"
          value={formatNumber(progress.compliantCount)}
          tone="good"
          hint="Android >10MB | iPhone file"
        />
        <StatTile
          label="Improper Usage"
          value={formatNumber(progress.nonCompliantCount)}
          tone={progress.nonCompliantCount > 0 ? 'warn' : 'good'}
          hint="Under 10MB or missing"
        />
        <StatTile
          label="Active Test Users"
          value={formatNumber(progress.activeTestUserCount)}
          tone="good"
          hint="Completed motor/cognitive tests"
        />
        <StatTile
          label="Integrity Alerts"
          value={formatNumber(progress.integrityAlertCount)}
          tone={progress.integrityAlertCount > 0 ? 'bad' : 'good'}
          hint="Missing sensor/activity files"
        />
        <StatTile
          label="Medication Reports"
          value={formatNumber(progress.medicationReportCount)}
          tone="good"
          hint="Users logging medication"
        />
      </div>

      {/* User Progress & Compliance Table */}
      <Card
        title="Participant Compliance & Progress Matrix"
        description="Platform usage rules: Android requires >10MB daily file loads. iPhone requires presence of uploaded file. Active test dates and medication reports are audited."
      >
        <Table
          head={[
            'User Code / Name',
            progress.identityVisible ? 'Email / Firebase UID' : 'Identity',
            'Platform',
            'Usage Status',
            'Data Integrity Audit',
            'Medication Status',
            'Active Test Dates',
            'Daily Loads',
          ]}
          empty={
            progress.participants.length === 0 ? (
              <div className="px-5 pt-4">
                <EmptyState title="No registered users found">
                  Check if users were imported into PostgreSQL or tick &quot;Include test accounts&quot;.
                </EmptyState>
              </div>
            ) : undefined
          }
        >
          {progress.participants.map((p) => (
            <tr key={p.participantId} className="transition hover:bg-surface/50">
              <Cell mono>
                <div className="font-semibold text-ink">{p.participantCode}</div>
                {p.displayName && (
                  <div className="text-xs font-sans text-ink-dim">{p.displayName}</div>
                )}
                {p.isTestAccount && <Badge tone="neutral">test</Badge>}
              </Cell>

              <Cell dim>
                {progress.identityVisible ? (
                  <div>
                    <div className="font-mono text-xs text-ink">{p.email ?? '—'}</div>
                    <div className="font-mono text-[10px] text-ink-faint">{p.firebaseUid ?? ''}</div>
                  </div>
                ) : (
                  <Badge tone="accent">Protected</Badge>
                )}
              </Cell>

              <Cell>
                <Badge tone="accent">{p.platform.toUpperCase()}</Badge>
              </Cell>

              <Cell>
                <Badge tone={p.complianceStatus === 'proper_usage' ? 'good' : 'bad'}>
                  {p.complianceStatus === 'proper_usage' ? 'PROPER USAGE' : 'IMPROPER USAGE'}
                </Badge>
                <div className="mt-1 text-[11px] text-ink-faint">{p.complianceReason}</div>
              </Cell>

              <Cell>
                {p.integrityStatus === 'healthy' ? (
                  <Badge tone="good">Healthy (Sensors + Activities)</Badge>
                ) : (
                  <div className="space-y-1">
                    {p.integrityAlerts.map((alert, idx) => (
                      <Badge key={idx} tone="warn">
                        ⚠️ {alert}
                      </Badge>
                    ))}
                  </div>
                )}
              </Cell>

              <Cell>
                <Badge tone={p.medicationStatus === 'logged' ? 'good' : 'neutral'}>
                  {p.medicationStatus === 'logged' ? 'MEDICATION LOGGED' : 'None Reported'}
                </Badge>
                {p.medicationReports.length > 0 && (
                  <div className="mt-1 text-[11px] text-ink-faint">
                    {p.medicationReports.length} log entry(ies)
                  </div>
                )}
              </Cell>

              <Cell dim>
                {p.activeTestDates.length > 0 ? (
                  <div className="space-y-1 text-xs">
                    {p.activeTestDates.slice(0, 3).map((atd) => (
                      <div key={atd.date} className="tabular">
                        <span className="font-mono">{formatDate(atd.date)}: </span>
                        <span className="text-ink font-medium">{atd.testTypes.join(', ')}</span>
                      </div>
                    ))}
                    {p.activeTestDates.length > 3 && (
                      <div className="text-[10px] text-ink-faint">
                        +{p.activeTestDates.length - 3} more dates
                      </div>
                    )}
                  </div>
                ) : (
                  <span className="text-ink-faint">No active tests</span>
                )}
              </Cell>

              <Cell dim>
                <div className="tabular font-medium text-ink">
                  {p.uploadCount} load(s) ({formatBytes(p.totalBytes)})
                </div>
                {p.latestUploadDate && (
                  <div className="text-[11px] text-ink-faint">
                    Latest: {formatDate(p.latestUploadDate)}
                  </div>
                )}
              </Cell>
            </tr>
          ))}
        </Table>
      </Card>
    </div>
  );
}
