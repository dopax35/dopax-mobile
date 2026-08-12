import { Badge, Card, Cell, EmptyState, Table } from '@/components/ui';
import { adminFetch } from '@/lib/api';
import { formatDateTime, formatNumber } from '@/lib/format';
import type { AuditEntry } from '@/lib/types';

function actorTone(actorType: string): string {
  return actorType === 'staff' ? 'accent' : actorType === 'system' ? 'warn' : 'neutral';
}

export default async function AuditPage({
  searchParams,
}: {
  searchParams: Promise<{ subject?: string }>;
}) {
  const params = await searchParams;

  const { entries } = await adminFetch<{ entries: AuditEntry[] }>('/audit', {
    query: { subject: params.subject, limit: 200 },
  });

  return (
    <div className="space-y-6">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-xl font-semibold text-ink">Audit trail</h1>
          <p className="mt-1 text-sm text-ink-dim">
            Who read which participant&apos;s data, and when. Required by the study&apos;s ethics
            approval, and append-only.
          </p>
        </div>

        <form className="flex items-center gap-2">
          <input
            name="subject"
            defaultValue={params.subject ?? ''}
            placeholder="filter by participant id"
            className="w-64 rounded-lg border border-line bg-canvas px-3 py-2 font-mono text-xs text-ink outline-none placeholder:text-ink-faint focus:border-accent/60"
          />
          <button
            type="submit"
            className="rounded-lg border border-line bg-surface-2 px-3 py-2 text-sm text-ink transition hover:border-accent/50"
          >
            Filter
          </button>
        </form>
      </header>

      <Card description={`${formatNumber(entries.length)} most recent entries`}>
        <Table
          head={['When', 'Actor', 'Action', 'Subject', 'Detail']}
          empty={
            entries.length === 0 ? (
              <div className="px-5 pt-4">
                <EmptyState title="Nothing recorded yet" />
              </div>
            ) : undefined
          }
        >
          {entries.map((entry) => {
            const email = (entry.metadata?.email as string | undefined) ?? null;
            const role = (entry.metadata?.role as string | undefined) ?? null;

            return (
              <tr key={entry.id}>
                <Cell mono dim>
                  {formatDateTime(entry.occurredAt)}
                </Cell>
                <Cell>
                  <Badge tone={actorTone(entry.actorType)}>{entry.actorType}</Badge>
                  {email && <span className="ml-2 font-mono text-xs text-ink-dim">{email}</span>}
                </Cell>
                <Cell>{entry.action}</Cell>
                <Cell mono dim className="max-w-[16rem] truncate">
                  {entry.subject ?? '—'}
                </Cell>
                <Cell dim>{role ?? '—'}</Cell>
              </tr>
            );
          })}
        </Table>
      </Card>
    </div>
  );
}
