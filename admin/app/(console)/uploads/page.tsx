import Link from 'next/link';
import { Badge, Card, Cell, EmptyState, Table, statusTone } from '@/components/ui';
import { adminFetch } from '@/lib/api';
import { formatBytes, formatDate, formatNumber } from '@/lib/format';
import type { CoverageDay, UploadFeedItem } from '@/lib/types';

export default async function UploadsPage({
  searchParams,
}: {
  searchParams: Promise<{ since?: string; status?: string }>;
}) {
  const params = await searchParams;

  const [coverage, feed] = await Promise.all([
    adminFetch<{ days: CoverageDay[] }>('/uploads/coverage', { query: { since: params.since } }),
    adminFetch<{ uploads: UploadFeedItem[] }>('/uploads', {
      query: { since: params.since, status: params.status, limit: 100 },
    }),
  ]);

  // One row per date, with the platforms merged, because a participant-day is the
  // unit the study reasons in — not a platform-day.
  const byDate = new Map<string, { participants: number; uploads: number; bytes: number; platforms: string[] }>();

  for (const day of coverage.days) {
    const existing = byDate.get(day.collectionDate) ?? {
      participants: 0,
      uploads: 0,
      bytes: 0,
      platforms: [],
    };

    byDate.set(day.collectionDate, {
      participants: Math.max(existing.participants, day.participants),
      uploads: existing.uploads + day.uploads,
      bytes: existing.bytes + day.bytes,
      platforms: [...existing.platforms, day.platform],
    });
  }

  const dates = [...byDate.entries()].sort((a, b) => b[0].localeCompare(a[0]));
  const peak = Math.max(1, ...dates.map(([, value]) => value.participants));

  return (
    <div className="space-y-6">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-xl font-semibold text-ink">Upload health</h1>
          <p className="mt-1 text-sm text-ink-dim">
            Which collection days arrived, from which platform, and what is still waiting to be
            parsed.
          </p>
        </div>

        <form className="flex items-center gap-2 text-sm">
          <input
            name="since"
            defaultValue={params.since ?? ''}
            placeholder="since yyyy-MM-dd"
            className="w-40 rounded-lg border border-line bg-canvas px-3 py-2 font-mono text-xs text-ink outline-none placeholder:text-ink-faint focus:border-accent/60"
          />
          <select
            name="status"
            defaultValue={params.status ?? ''}
            className="rounded-lg border border-line bg-canvas px-3 py-2 text-sm text-ink outline-none focus:border-accent/60"
          >
            <option value="">any status</option>
            <option value="pending">pending</option>
            <option value="parsed">parsed</option>
            <option value="failed">failed</option>
          </select>
          <button
            type="submit"
            className="rounded-lg border border-line bg-surface-2 px-3 py-2 text-ink transition hover:border-accent/50"
          >
            Filter
          </button>
        </form>
      </header>

      <Card title="Collection days" description="Participants uploading per day, newest first">
        {dates.length === 0 ? (
          <EmptyState title="No uploads recorded" />
        ) : (
          <ul className="space-y-1.5">
            {dates.slice(0, 60).map(([date, value]) => (
              <li key={date} className="flex items-center gap-3">
                <span className="tabular w-24 shrink-0 font-mono text-xs text-ink-dim">
                  {formatDate(date)}
                </span>

                <span className="flex h-5 min-w-0 flex-1 items-center">
                  <span
                    className="h-2 rounded-full bg-accent/70"
                    style={{ width: `${Math.max(2, (value.participants / peak) * 100)}%` }}
                  />
                </span>

                <span className="tabular w-16 shrink-0 text-right text-xs text-ink-dim">
                  {formatNumber(value.participants)}
                </span>
                <span className="tabular w-20 shrink-0 text-right text-xs text-ink-faint">
                  {formatBytes(value.bytes)}
                </span>
                <span className="flex w-24 shrink-0 justify-end gap-1">
                  {[...new Set(value.platforms)].map((platform) => (
                    <Badge key={platform}>{platform}</Badge>
                  ))}
                </span>
              </li>
            ))}
          </ul>
        )}
      </Card>

      <Card title="Recent uploads" description={`${formatNumber(feed.uploads.length)} shown`}>
        <Table
          head={['Date', 'Participant', 'Platform', 'Status', 'Source', 'Size']}
          empty={
            feed.uploads.length === 0 ? (
              <div className="px-5 pt-4">
                <EmptyState title="Nothing matches that filter" />
              </div>
            ) : undefined
          }
        >
          {feed.uploads.map((upload) => (
            <tr key={upload.id} className="transition hover:bg-surface/50">
              <Cell mono>{formatDate(upload.collectionDate)}</Cell>
              <Cell mono>
                <Link
                  href={`/participants/${upload.participantId}`}
                  className="text-accent underline-offset-2 hover:underline"
                >
                  {upload.participantCode}
                </Link>
              </Cell>
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
            </tr>
          ))}
        </Table>
      </Card>
    </div>
  );
}
