'use client';

import { useState, useMemo, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { Badge, Card, Cell, EmptyState, Table, StatTile } from '@/components/ui';
import { formatBytes, formatDate, formatNumber } from '@/lib/format';
import type { ProgressSummary } from '@/lib/types';

type SortField = 'name' | 'platform' | 'compliance' | 'latestDate' | 'medication' | 'activeTests' | 'uploads';
type SortOrder = 'asc' | 'desc';
type FilterTab = 'all' | 'proper' | 'improper' | 'no_uploads' | 'meds_logged' | 'active_tests' | 'recent_yesterday' | 'has_uploads';

const RECENT_DATE = '2026-08-26'; // Study yesterday upload date

export function ProgressTableClient({
  progress,
  initialIncludeTests = false,
}: {
  progress: ProgressSummary;
  initialIncludeTests?: boolean;
}) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();

  const [searchQuery, setSearchQuery] = useState('');
  const [activeTab, setActiveTab] = useState<FilterTab>('all');
  const [sortField, setSortField] = useState<SortField>('uploads');
  const [sortOrder, setSortOrder] = useState<SortOrder>('desc');
  const [includeTests, setIncludeTests] = useState(initialIncludeTests);
  const [lastRefreshed, setLastRefreshed] = useState<string>(
    progress.lastRefreshedAt ||
      new Date().toLocaleTimeString('en-US', { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' }),
  );

  const handleRefresh = () => {
    startTransition(() => {
      router.refresh();
      setLastRefreshed(
        new Date().toLocaleTimeString('en-US', { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' }),
      );
    });
  };

  const handleToggleTests = (e: React.ChangeEvent<HTMLInputElement>) => {
    const checked = e.target.checked;
    setIncludeTests(checked);
    startTransition(() => {
      router.push(`/progress${checked ? '?tests=true' : ''}`);
    });
  };

  const handleSort = (field: SortField) => {
    if (sortField === field) {
      setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc');
    } else {
      setSortField(field);
      setSortOrder('desc');
    }
  };

  const recentYesterdayCount = useMemo(
    () => progress.participants.filter((p) => p.latestUploadDate === RECENT_DATE).length,
    [progress.participants],
  );

  const improperCount = useMemo(
    () => progress.participants.filter((p) => p.complianceStatus === 'improper_usage').length,
    [progress.participants],
  );

  const noUploadsCount = useMemo(
    () => progress.participants.filter((p) => p.complianceStatus === 'no_uploads').length,
    [progress.participants],
  );

  const medicationLoggedCount = useMemo(
    () =>
      progress.participants.filter(
        (p) =>
          p.medicationReportedOnLatestDay ||
          p.medicationStatus === 'logged' ||
          (p.medicationReports && p.medicationReports.length > 0),
      ).length,
    [progress.participants],
  );

  const filteredAndSorted = useMemo(() => {
    let items = [...progress.participants];

    // Filter by Search Query
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase().trim();
      items = items.filter(
        (p) =>
          (p.displayName && p.displayName.toLowerCase().includes(q)) ||
          (p.email && p.email.toLowerCase().includes(q)) ||
          p.participantCode.toLowerCase().includes(q) ||
          (p.firebaseUid && p.firebaseUid.toLowerCase().includes(q)),
      );
    }

    // Filter by Tab
    if (activeTab === 'proper') {
      items = items.filter((p) => p.complianceStatus === 'proper_usage');
    } else if (activeTab === 'improper') {
      items = items.filter((p) => p.complianceStatus === 'improper_usage');
    } else if (activeTab === 'no_uploads') {
      items = items.filter((p) => p.complianceStatus === 'no_uploads' || p.uploadCount === 0);
    } else if (activeTab === 'meds_logged') {
      items = items.filter(
        (p) =>
          p.medicationReportedOnLatestDay ||
          p.medicationStatus === 'logged' ||
          (p.medicationReports && p.medicationReports.length > 0),
      );
    } else if (activeTab === 'active_tests') {
      items = items.filter(
        (p) => p.activeTestInLatestFile || (p.activeTestDates && p.activeTestDates.length > 0),
      );
    } else if (activeTab === 'recent_yesterday') {
      items = items.filter((p) => p.latestUploadDate === RECENT_DATE);
    } else if (activeTab === 'has_uploads') {
      items = items.filter((p) => p.uploadCount > 0);
    }

    // Sort Items
    items.sort((a, b) => {
      let valA: string | number = '';
      let valB: string | number = '';

      if (sortField === 'name') {
        valA = (a.displayName || a.email || a.participantCode).toLowerCase();
        valB = (b.displayName || b.email || b.participantCode).toLowerCase();
      } else if (sortField === 'platform') {
        valA = a.platform;
        valB = b.platform;
      } else if (sortField === 'compliance') {
        const rankMap: Record<string, number> = { proper_usage: 2, improper_usage: 1, no_uploads: 0 };
        valA = rankMap[a.complianceStatus] ?? 0;
        valB = rankMap[b.complianceStatus] ?? 0;
      } else if (sortField === 'medication') {
        valA = a.medicationReportedOnLatestDay || a.medicationStatus === 'logged' ? 1 : 0;
        valB = b.medicationReportedOnLatestDay || b.medicationStatus === 'logged' ? 1 : 0;
      } else if (sortField === 'activeTests') {
        valA = a.activeTestInLatestFile || (a.activeTestDates && a.activeTestDates.length > 0) ? 1 : 0;
        valB = b.activeTestInLatestFile || (b.activeTestDates && b.activeTestDates.length > 0) ? 1 : 0;
      } else if (sortField === 'uploads') {
        valA = a.uploadCount;
        valB = b.uploadCount;
      } else if (sortField === 'latestDate') {
        valA = a.latestUploadDate || '';
        valB = b.latestUploadDate || '';
      }

      if (valA < valB) return sortOrder === 'asc' ? -1 : 1;
      if (valA > valB) return sortOrder === 'asc' ? 1 : -1;
      return 0;
    });

    return items;
  }, [progress.participants, searchQuery, activeTab, sortField, sortOrder]);

  const renderSortIndicator = (field: SortField) => {
    if (sortField !== field) return <span className="ml-1 text-ink-faint/40">↕</span>;
    return <span className="ml-1 font-bold text-accent">{sortOrder === 'asc' ? '↑' : '↓'}</span>;
  };

  const complianceRate =
    progress.totalRegistered > 0
      ? ((progress.compliantCount / progress.totalRegistered) * 100).toFixed(1)
      : '0';

  const activeTestRate =
    progress.totalRegistered > 0
      ? ((progress.activeTestUserCount / progress.totalRegistered) * 100).toFixed(1)
      : '0';

  const medicationRate =
    progress.totalRegistered > 0
      ? ((medicationLoggedCount / progress.totalRegistered) * 100).toFixed(1)
      : '0';

  const driveUploadersCount = useMemo(
    () => progress.participants.filter((p) => p.uploadCount > 0).length,
    [progress.participants],
  );

  return (
    <div className="space-y-6">
      {/* 1. Live Data Status Header */}
      <header className="flex flex-wrap items-center justify-between gap-4 rounded-xl border border-line bg-surface/80 px-6 py-5 backdrop-blur-md">
        <div>
          <div className="flex items-center gap-2.5">
            <span className="relative flex h-2.5 w-2.5">
              <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-good opacity-75"></span>
              <span className="relative inline-flex h-2.5 w-2.5 rounded-full bg-good"></span>
            </span>
            <h1 className="text-xl font-bold tracking-tight text-ink">Volunteer Progress Review Console</h1>
            <Badge tone="good">Live Data Status: Active</Badge>
          </div>
          <p className="mt-1 text-xs text-ink-dim">
            Real-time compliance tracking and Google Drive verification status for study participants.
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-4">
          <div className="text-right text-xs">
            <span className="text-ink-faint">Last refreshed: </span>
            <span className="font-mono font-medium text-ink">{lastRefreshed}</span>
          </div>

          <button
            type="button"
            onClick={handleRefresh}
            disabled={isPending}
            className="inline-flex items-center gap-2 rounded-lg border border-accent/40 bg-accent/15 px-3.5 py-1.5 text-xs font-semibold text-accent transition hover:border-accent hover:bg-accent/25 disabled:opacity-50"
          >
            <span className={isPending ? 'animate-spin' : ''}>🔄</span>
            {isPending ? 'Refreshing...' : 'Refresh Data'}
          </button>

          <div className="hidden h-6 w-px bg-line/60 sm:block" />

          <label className="flex cursor-pointer select-none items-center gap-2 text-xs text-ink-dim">
            <input
              type="checkbox"
              checked={includeTests}
              onChange={handleToggleTests}
              className="size-3.5 rounded accent-[oklch(0.72_0.13_215)]"
            />
            Include test accounts
          </label>
        </div>
      </header>

      {/* 2. Simplified KPI Summary Cards Grid */}
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
        <StatTile
          label="Registered Users"
          value={formatNumber(progress.totalRegistered)}
          hint={`${progress.compliantCount} proper / ${improperCount} improper / ${noUploadsCount} no uploads`}
        />
        <StatTile
          label="Proper Usage Rate"
          value={`${complianceRate}%`}
          tone={Number(complianceRate) >= 50 ? 'good' : 'warn'}
          hint={`${progress.compliantCount} proper usage (Android >10MB | iOS stream)`}
        />
        <StatTile
          label="Uploaded Yesterday"
          value={formatNumber(recentYesterdayCount)}
          tone="good"
          hint={`${recentYesterdayCount} participants uploaded files on ${RECENT_DATE}`}
        />
        <StatTile
          label="Medication Logged"
          value={formatNumber(medicationLoggedCount)}
          tone="good"
          hint={`${medicationRate}% logged meds on last active day`}
        />
        <StatTile
          label="Active Test Compliant"
          value={formatNumber(progress.activeTestUserCount)}
          tone="good"
          hint={`${activeTestRate}% completed active tests in latest file`}
        />
      </div>

      {/* 3. Filter Controls & Participant Matrix Table */}
      <Card className="overflow-hidden border border-line bg-surface/60 p-0">
        {/* Header controls: Search & Quick Filter Tabs */}
        <div className="flex flex-wrap items-center justify-between gap-4 border-b border-line bg-surface/40 px-5 py-4">
          <div className="flex flex-wrap items-center gap-1.5">
            <button
              type="button"
              onClick={() => setActiveTab('all')}
              className={`rounded-lg px-3 py-1.5 text-xs font-medium transition ${
                activeTab === 'all'
                  ? 'border border-accent/40 bg-accent/15 font-semibold text-accent'
                  : 'text-ink-dim hover:bg-surface-2'
              }`}
            >
              All Users ({progress.participants.length})
            </button>
            <button
              type="button"
              onClick={() => setActiveTab('proper')}
              className={`rounded-lg px-3 py-1.5 text-xs font-medium transition ${
                activeTab === 'proper'
                  ? 'border border-good/40 bg-good/15 font-semibold text-good'
                  : 'text-ink-dim hover:bg-surface-2'
              }`}
            >
              Proper Usage ({progress.compliantCount})
            </button>
            <button
              type="button"
              onClick={() => setActiveTab('improper')}
              className={`rounded-lg px-3 py-1.5 text-xs font-medium transition ${
                activeTab === 'improper'
                  ? 'border border-warn/40 bg-warn/15 font-semibold text-warn'
                  : 'text-ink-dim hover:bg-surface-2'
              }`}
            >
              Improper Usage ({improperCount})
            </button>
            <button
              type="button"
              onClick={() => setActiveTab('meds_logged')}
              className={`rounded-lg px-3 py-1.5 text-xs font-medium transition ${
                activeTab === 'meds_logged'
                  ? 'border border-good/40 bg-good/15 font-semibold text-good'
                  : 'text-ink-dim hover:bg-surface-2'
              }`}
            >
              Meds Logged ({medicationLoggedCount})
            </button>
            <button
              type="button"
              onClick={() => setActiveTab('active_tests')}
              className={`rounded-lg px-3 py-1.5 text-xs font-medium transition ${
                activeTab === 'active_tests'
                  ? 'border border-accent/40 bg-accent/15 font-semibold text-accent'
                  : 'text-ink-dim hover:bg-surface-2'
              }`}
            >
              Active Tests ({progress.activeTestUserCount})
            </button>
            <button
              type="button"
              onClick={() => setActiveTab('no_uploads')}
              className={`rounded-lg px-3 py-1.5 text-xs font-medium transition ${
                activeTab === 'no_uploads'
                  ? 'border border-bad/40 bg-bad/15 font-semibold text-bad'
                  : 'text-ink-dim hover:bg-surface-2'
              }`}
            >
              No Uploads ({noUploadsCount})
            </button>
          </div>

          <div className="relative min-w-[260px]">
            <input
              type="text"
              placeholder="Search by name, email, code or UID..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full rounded-lg border border-line bg-canvas px-3 py-1.5 text-xs text-ink outline-none transition placeholder:text-ink-faint focus:border-accent/60"
            />
            {searchQuery && (
              <button
                type="button"
                onClick={() => setSearchQuery('')}
                className="absolute right-2.5 top-1/2 -translate-y-1/2 text-xs text-ink-faint hover:text-ink"
              >
                ✕
              </button>
            )}
          </div>
        </div>

        {/* Main Matrix Table */}
        <Table
          head={[
            <button key="name" type="button" onClick={() => handleSort('name')} className="flex items-center hover:text-ink">
              Participant Identity {renderSortIndicator('name')}
            </button>,
            <button key="platform" type="button" onClick={() => handleSort('platform')} className="flex items-center hover:text-ink">
              Platform {renderSortIndicator('platform')}
            </button>,
            <button key="compliance" type="button" onClick={() => handleSort('compliance')} className="flex items-center hover:text-ink">
              Usage Compliance {renderSortIndicator('compliance')}
            </button>,
            <button key="latestDate" type="button" onClick={() => handleSort('latestDate')} className="flex items-center hover:text-ink">
              Latest Upload Recency {renderSortIndicator('latestDate')}
            </button>,
            <button key="medication" type="button" onClick={() => handleSort('medication')} className="flex items-center hover:text-ink">
              Medication Status {renderSortIndicator('medication')}
            </button>,
            <button key="activeTests" type="button" onClick={() => handleSort('activeTests')} className="flex items-center hover:text-ink">
              Latest File Active Tests {renderSortIndicator('activeTests')}
            </button>,
            <button key="uploads" type="button" onClick={() => handleSort('uploads')} className="flex items-center hover:text-ink">
              Actual # of Files {renderSortIndicator('uploads')}
            </button>,
          ]}
          empty={
            filteredAndSorted.length === 0 ? (
              <div className="px-5 py-8">
                <EmptyState title="No matching participants found">
                  Try adjusting your search query or switching the quick filter tab.
                </EmptyState>
              </div>
            ) : undefined
          }
        >
          {filteredAndSorted.map((p) => {
            const hasRealName =
              Boolean(p.displayName) &&
              p.displayName?.trim() !== '' &&
              p.displayName !== p.email &&
              p.displayName !== p.participantCode &&
              p.displayName !== p.firebaseUid;

            const isIphone =
              p.platform?.toLowerCase().includes('ios') ||
              p.platform?.toLowerCase().includes('iphone') ||
              p.platform?.toLowerCase().includes('apple') ||
              (p.email && p.email.endsWith('@privaterelay.appleid.com'));

            const isYesterdayUpload = p.latestUploadDate === RECENT_DATE;

            const hasMedsLogged =
              p.medicationReportedOnLatestDay ||
              p.medicationStatus === 'logged' ||
              (p.medicationReports && p.medicationReports.length > 0);
            const latestMedInfo = p.medicationReports && p.medicationReports.length > 0 ? p.medicationReports[0] : null;

            const hasActiveTests =
              p.activeTestInLatestFile || (p.activeTestDates && p.activeTestDates.length > 0);
            const latestTestInfo = p.activeTestDates && p.activeTestDates.length > 0 ? p.activeTestDates[0] : null;

            return (
              <tr key={p.participantId} className="transition hover:bg-surface/50">
                {/* 1. Clear Identity Display */}
                <Cell mono={false}>
                  {hasRealName ? (
                    <div>
                      <div className="text-sm font-bold text-ink">{p.displayName}</div>
                      {p.email && <div className="mt-0.5 font-mono text-xs text-ink-dim">{p.email}</div>}
                      <div className="font-mono text-[10px] text-ink-faint">
                        Code: {p.participantCode} {p.firebaseUid ? `| UID: ${p.firebaseUid.slice(0, 8)}...` : ''}
                      </div>
                    </div>
                  ) : (
                    <div>
                      <div className="text-sm font-bold text-ink">{p.email || p.participantCode}</div>
                      <div className="font-mono text-[10px] text-ink-faint">
                        Code: {p.participantCode} {p.firebaseUid ? `| UID: ${p.firebaseUid.slice(0, 8)}...` : ''}
                      </div>
                    </div>
                  )}
                </Cell>

                {/* 2. Platform Badge */}
                <Cell>
                  <Badge tone={isIphone ? 'accent' : 'neutral'}>
                    {isIphone ? 'iPhone (iOS)' : 'Android'}
                  </Badge>
                </Cell>

                {/* 3. Refined 3-Tier Usage Compliance Badge */}
                <Cell>
                  {p.complianceStatus === 'proper_usage' ? (
                    <div>
                      <Badge tone="good">PROPER USAGE</Badge>
                      <div className="mt-1 max-w-[180px] truncate text-[11px] font-medium text-good" title={p.complianceReason}>
                        {p.complianceReason}
                      </div>
                    </div>
                  ) : p.complianceStatus === 'improper_usage' ? (
                    <div>
                      <Badge tone="warn">IMPROPER USAGE</Badge>
                      <div className="mt-1 max-w-[180px] truncate text-[11px] font-medium text-warn" title={p.complianceReason}>
                        {p.complianceReason}
                      </div>
                    </div>
                  ) : (
                    <div>
                      <Badge tone="bad">NO UPLOADS</Badge>
                      <div className="mt-1 text-[11px] text-bad font-medium">0 files in Google Drive</div>
                    </div>
                  )}
                </Cell>

                {/* 4. Latest Upload Recency: GREEN if yesterday (2026-08-26), RED if not */}
                <Cell>
                  {isYesterdayUpload ? (
                    <div>
                      <Badge tone="good">UPLOADED YESTERDAY</Badge>
                      <div className="mt-1 font-mono text-xs font-semibold text-good">
                        {formatDate(p.latestUploadDate)}
                      </div>
                    </div>
                  ) : p.latestUploadDate ? (
                    <div>
                      <Badge tone="bad">NO UPLOAD YESTERDAY</Badge>
                      <div className="mt-1 font-mono text-xs font-medium text-bad">
                        Last: {formatDate(p.latestUploadDate)}
                      </div>
                    </div>
                  ) : (
                    <div>
                      <Badge tone="bad">NO UPLOADS</Badge>
                      <div className="mt-1 text-[11px] text-bad font-medium">Never uploaded</div>
                    </div>
                  )}
                </Cell>

                {/* 5. Medication Status Column (RESTORED!) */}
                <Cell>
                  {hasMedsLogged ? (
                    <div>
                      <Badge tone="good">MEDICATION LOGGED</Badge>
                      <div className="mt-1 text-xs text-ink-dim">
                        {latestMedInfo ? (
                          <div>
                            <span className="font-medium text-ink">
                              {latestMedInfo.medicationName || 'Reported'} {latestMedInfo.dosage ? `(${latestMedInfo.dosage})` : ''}
                            </span>
                            {latestMedInfo.date && (
                              <div className="font-mono text-[10px] text-ink-faint">
                                Date: {formatDate(latestMedInfo.date)}
                              </div>
                            )}
                          </div>
                        ) : (
                          <span className="text-[11px] text-ink-faint">Logged on last active day</span>
                        )}
                      </div>
                    </div>
                  ) : (
                    <div>
                      <Badge tone="neutral">NOT LOGGED</Badge>
                      <div className="mt-1 text-[11px] text-ink-faint">No meds on latest day</div>
                    </div>
                  )}
                </Cell>

                {/* 6. Latest Data File Active Test Status */}
                <Cell>
                  {hasActiveTests ? (
                    <div>
                      <Badge tone="good">ACTIVE TEST PERFORMED</Badge>
                      <div className="mt-1 text-xs text-ink-dim">
                        <span className="font-medium text-ink">
                          {latestTestInfo ? latestTestInfo.testTypes.join(', ') : 'Motor & Cognitive'}
                        </span>
                      </div>
                    </div>
                  ) : (
                    <div>
                      <Badge tone="warn">NO ACTIVE TESTS</Badge>
                      <div className="mt-1 text-[11px] text-ink-faint">No tests in latest file</div>
                    </div>
                  )}
                </Cell>

                {/* 7. Actual # of Files */}
                <Cell dim>
                  {p.uploadCount > 0 ? (
                    <div>
                      <div className="tabular text-sm font-bold text-ink">
                        {p.uploadCount} {p.uploadCount === 1 ? 'file' : 'files'}
                      </div>
                      <div className="text-[11px] font-mono text-ink-dim">
                        Total: {formatBytes(p.totalBytes)}
                      </div>
                    </div>
                  ) : (
                    <div>
                      <span className="text-xs font-bold text-bad">0 files</span>
                      <div className="text-[10px] text-ink-faint">No files in Drive</div>
                    </div>
                  )}
                </Cell>
              </tr>
            );
          })}
        </Table>
      </Card>
    </div>
  );
}
