'use client';

import { useState, useMemo } from 'react';
import { Badge, Card, Cell, EmptyState, Table } from '@/components/ui';
import { formatBytes, formatDate } from '@/lib/format';
import type { ProgressSummary } from '@/lib/types';

type SortField = 'name' | 'platform' | 'compliance' | 'activeTests' | 'uploads' | 'latestDate';
type SortOrder = 'asc' | 'desc';
type FilterTab = 'all' | 'proper' | 'improper' | 'active_tests' | 'has_uploads';

export function ProgressTableClient({ progress }: { progress: ProgressSummary }) {
  const [searchQuery, setSearchQuery] = useState('');
  const [activeTab, setActiveTab] = useState<FilterTab>('all');
  const [sortField, setSortField] = useState<SortField>('uploads');
  const [sortOrder, setSortOrder] = useState<SortOrder>('desc');

  const handleSort = (field: SortField) => {
    if (sortField === field) {
      setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc');
    } else {
      setSortField(field);
      setSortOrder('desc');
    }
  };

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
    } else if (activeTab === 'active_tests') {
      items = items.filter((p) => p.activeTestDates.length > 0);
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
        valA = a.complianceStatus === 'proper_usage' ? 1 : 0;
        valB = b.complianceStatus === 'proper_usage' ? 1 : 0;
      } else if (sortField === 'activeTests') {
        valA = a.activeTestDates.length;
        valB = b.activeTestDates.length;
      } else if (sortField === 'uploads') {
        valA = a.totalBytes;
        valB = b.totalBytes;
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

  return (
    <Card className="overflow-hidden p-0">
      {/* Header controls: Search & Quick Filter Tabs */}
      <div className="flex flex-wrap items-center justify-between gap-4 border-b border-line bg-surface/40 px-5 py-4">
        <div className="flex flex-wrap items-center gap-1.5">
          <button
            type="button"
            onClick={() => setActiveTab('all')}
            className={`rounded-lg px-3 py-1.5 text-xs font-medium transition ${
              activeTab === 'all'
                ? 'border border-accent/30 bg-accent/15 text-accent'
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
                ? 'border border-good/30 bg-good/15 text-good'
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
                ? 'border border-warn/30 bg-warn/15 text-warn'
                : 'text-ink-dim hover:bg-surface-2'
            }`}
          >
            Improper Usage ({progress.nonCompliantCount})
          </button>
          <button
            type="button"
            onClick={() => setActiveTab('active_tests')}
            className={`rounded-lg px-3 py-1.5 text-xs font-medium transition ${
              activeTab === 'active_tests'
                ? 'border border-accent/30 bg-accent/15 text-accent'
                : 'text-ink-dim hover:bg-surface-2'
            }`}
          >
            Active Tests ({progress.activeTestUserCount})
          </button>
          <button
            type="button"
            onClick={() => setActiveTab('has_uploads')}
            className={`rounded-lg px-3 py-1.5 text-xs font-medium transition ${
              activeTab === 'has_uploads'
                ? 'border border-good/30 bg-good/15 text-good'
                : 'text-ink-dim hover:bg-surface-2'
            }`}
          >
            Drive Uploaders ({progress.participants.filter((p) => p.uploadCount > 0).length})
          </button>
        </div>

        <div className="relative min-w-[240px]">
          <input
            type="text"
            placeholder="Search by name, email, or code…"
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

      {/* Main Table */}
      <Table
        head={[
          <button key="name" type="button" onClick={() => handleSort('name')} className="flex items-center hover:text-ink">
            Participant Identity {renderSortIndicator('name')}
          </button>,
          <button key="platform" type="button" onClick={() => handleSort('platform')} className="flex items-center hover:text-ink">
            Platform {renderSortIndicator('platform')}
          </button>,
          <button key="compliance" type="button" onClick={() => handleSort('compliance')} className="flex items-center hover:text-ink">
            App Usage Status {renderSortIndicator('compliance')}
          </button>,
          <button key="activeTests" type="button" onClick={() => handleSort('activeTests')} className="flex items-center hover:text-ink">
            Active Test Compliance {renderSortIndicator('activeTests')}
          </button>,
          'Data Integrity & Meds',
          <button key="uploads" type="button" onClick={() => handleSort('uploads')} className="flex items-center hover:text-ink">
            Verified Drive Uploads {renderSortIndicator('uploads')}
          </button>,
        ]}
        empty={
          filteredAndSorted.length === 0 ? (
            <div className="px-5 py-8">
              <EmptyState title="No matching participants found">
                Try adjusting your search query or switching active tab filter.
              </EmptyState>
            </div>
          ) : undefined
        }
      >
        {filteredAndSorted.map((p) => {
          const hasRealName =
            Boolean(p.displayName) &&
            p.displayName !== p.email &&
            p.displayName !== p.participantCode &&
            p.displayName !== p.firebaseUid;

          const isIphone =
            p.platform.includes('ios') ||
            p.platform.includes('iphone') ||
            p.platform.includes('apple') ||
            (p.email && p.email.endsWith('@privaterelay.appleid.com'));

          return (
            <tr key={p.participantId} className="transition hover:bg-surface/50">
              {/* Participant Identity Column */}
              <Cell mono={false}>
                {hasRealName ? (
                  <div>
                    <div className="text-sm font-semibold text-ink">{p.displayName}</div>
                    <div className="mt-0.5 font-mono text-xs text-ink-dim">{p.email ?? '—'}</div>
                    <div className="font-mono text-[10px] text-ink-faint">Code: {p.participantCode}</div>
                  </div>
                ) : (
                  <div>
                    <div className="text-sm font-semibold text-ink">{p.email || p.participantCode}</div>
                    <div className="font-mono text-[10px] text-ink-faint">UID: {p.firebaseUid || p.participantCode}</div>
                  </div>
                )}
              </Cell>

              {/* Platform Column */}
              <Cell>
                <Badge tone={isIphone ? 'accent' : 'neutral'}>
                  {isIphone ? 'iPhone (iOS)' : 'Android'}
                </Badge>
              </Cell>

              {/* App Usage Status Column */}
              <Cell>
                <Badge tone={p.complianceStatus === 'proper_usage' ? 'good' : 'bad'}>
                  {p.complianceStatus === 'proper_usage' ? 'PROPER USAGE' : 'IMPROPER USAGE'}
                </Badge>
                <div className="mt-1 text-[11px] text-ink-faint">{p.complianceReason}</div>
              </Cell>

              {/* Active Test Compliance Column */}
              <Cell>
                {p.activeTestDates.length > 0 ? (
                  <div>
                    <Badge tone="good">TEST COMPLIANT</Badge>
                    <div className="mt-1 space-y-0.5 text-xs text-ink-dim">
                      {p.activeTestDates.slice(0, 2).map((atd) => (
                        <div key={atd.date} className="tabular">
                          <span className="font-mono">{formatDate(atd.date)}: </span>
                          <span className="font-medium text-ink">{atd.testTypes.join(', ')}</span>
                        </div>
                      ))}
                    </div>
                  </div>
                ) : (
                  <div>
                    <Badge tone="warn">NO ACTIVE TESTS</Badge>
                    <div className="mt-1 text-[11px] text-ink-faint">No tests recorded</div>
                  </div>
                )}
              </Cell>

              {/* Data Integrity & Medication Column */}
              <Cell>
                <div className="space-y-1">
                  {p.integrityStatus === 'healthy' ? (
                    <Badge tone="good">Healthy (Sensors + Activities)</Badge>
                  ) : (
                    p.integrityAlerts.map((alert, idx) => (
                      <Badge key={idx} tone="warn">
                        ⚠️ {alert}
                      </Badge>
                    ))
                  )}

                  <div>
                    <Badge tone={p.medicationStatus === 'logged' ? 'good' : 'neutral'}>
                      {p.medicationStatus === 'logged' ? 'Medication Logged' : 'No Meds Logged'}
                    </Badge>
                  </div>
                </div>
              </Cell>

              {/* Verified Drive Uploads Column */}
              <Cell dim>
                {p.uploadCount > 0 ? (
                  <div>
                    <div className="tabular font-semibold text-ink">
                      {p.uploadCount} load(s) ({formatBytes(p.totalBytes)})
                    </div>
                    {p.latestUploadDate && (
                      <div className="text-[11px] text-ink-faint">
                        Latest: {formatDate(p.latestUploadDate)}
                      </div>
                    )}
                  </div>
                ) : (
                  <div>
                    <span className="text-xs font-medium text-bad">0 uploads</span>
                    <div className="text-[10px] text-ink-faint">No files in Drive</div>
                  </div>
                )}
              </Cell>
            </tr>
          );
        })}
      </Table>
    </Card>
  );
}
