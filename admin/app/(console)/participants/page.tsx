import Link from 'next/link';
import { Badge, Card, Cell, EmptyState, Table, statusTone } from '@/components/ui';
import { adminFetch } from '@/lib/api';
import { daysAgo, formatDate, formatNumber } from '@/lib/format';
import { getSession, hasRole } from '@/lib/session';
import type { ParticipantList } from '@/lib/types';

const PAGE_SIZE = 50;

export default async function ParticipantsPage({
  searchParams,
}: {
  searchParams: Promise<{ search?: string; status?: string; tests?: string; page?: string }>;
}) {
  const params = await searchParams;
  const session = await getSession();
  const canOpenDetail = session ? hasRole(session, 'researcher') : false;

  const page = Math.max(1, Number(params.page ?? '1') || 1);

  const list = await adminFetch<ParticipantList>('/participants', {
    query: {
      search: params.search,
      status: params.status,
      includeTestAccounts: params.tests === 'true' ? 'true' : 'false',
      limit: PAGE_SIZE,
      offset: (page - 1) * PAGE_SIZE,
    },
  });

  const lastPage = Math.max(1, Math.ceil(list.total / PAGE_SIZE));

  return (
    <div className="space-y-6">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-xl font-semibold text-ink">Participants</h1>
          <p className="mt-1 text-sm text-ink-dim">
            {formatNumber(list.total)} matching, ordered by most recent upload.
            {!list.identityVisible && ' Identified by participant code only.'}
          </p>
        </div>

        <form className="flex flex-wrap items-center gap-2">
          <input
            name="search"
            defaultValue={params.search ?? ''}
            placeholder="code, legacy id, email…"
            className="w-56 rounded-lg border border-line bg-canvas px-3 py-2 text-sm text-ink outline-none transition placeholder:text-ink-faint focus:border-accent/60"
          />
          <select
            name="status"
            defaultValue={params.status ?? ''}
            className="rounded-lg border border-line bg-canvas px-3 py-2 text-sm text-ink outline-none focus:border-accent/60"
          >
            <option value="">any status</option>
            <option value="active">active</option>
            <option value="needs_id_resolution">needs id resolution</option>
            <option value="withdrawn">withdrawn</option>
          </select>
          <label className="flex items-center gap-2 text-xs text-ink-dim">
            <input
              type="checkbox"
              name="tests"
              value="true"
              defaultChecked={params.tests === 'true'}
              className="size-3.5 accent-[oklch(0.72_0.13_215)]"
            />
            test accounts
          </label>
          <button
            type="submit"
            className="rounded-lg border border-line bg-surface-2 px-3 py-2 text-sm text-ink transition hover:border-accent/50"
          >
            Filter
          </button>
        </form>
      </header>

      <Card>
        <Table
          head={[
            'Participant',
            list.identityVisible ? 'Account' : 'Provider',
            'Status',
            'Uploads',
            'Last upload',
            '',
          ]}
          empty={
            list.participants.length === 0 ? (
              <div className="px-5 pt-4">
                <EmptyState title="No participants match that filter">
                  Test accounts are hidden unless you tick the box; 19 of the 43 imported accounts
                  are flagged as test data.
                </EmptyState>
              </div>
            ) : undefined
          }
        >
          {list.participants.map((participant) => (
            <tr key={participant.id} className="transition hover:bg-surface/50">
              <Cell mono>
                <span className="text-ink">{participant.participantCode}</span>
                {participant.isTestAccount && (
                  <span className="ml-2">
                    <Badge>test</Badge>
                  </span>
                )}
                {participant.legacyFileUserIds.length > 1 && (
                  <span
                    className="ml-2 text-ink-faint"
                    title={participant.legacyFileUserIds.join(', ')}
                  >
                    +{participant.legacyFileUserIds.length - 1} legacy
                  </span>
                )}
              </Cell>

              <Cell dim>
                {list.identityVisible ? (
                  <span className="font-mono text-xs">{participant.email ?? '—'}</span>
                ) : (
                  <Badge>{participant.provider ?? 'unknown'}</Badge>
                )}
              </Cell>

              <Cell>
                <Badge tone={statusTone(participant.status)}>
                  {participant.status.replace(/_/g, ' ')}
                </Badge>
              </Cell>

              <Cell dim>
                <span className="tabular">{formatNumber(participant.uploadCount)}</span>
              </Cell>

              <Cell dim>
                {participant.lastUploadDate ? (
                  <span title={daysAgo(participant.lastUploadDate)}>
                    {formatDate(participant.lastUploadDate)}
                  </span>
                ) : (
                  <span className="text-ink-faint">never</span>
                )}
              </Cell>

              <Cell className="text-right">
                {canOpenDetail ? (
                  <Link
                    href={`/participants/${participant.id}`}
                    className="text-xs text-accent underline-offset-2 hover:underline"
                  >
                    Open
                  </Link>
                ) : (
                  <span className="text-xs text-ink-faint" title="Needs the researcher role">
                    —
                  </span>
                )}
              </Cell>
            </tr>
          ))}
        </Table>
      </Card>

      {lastPage > 1 && (
        <nav className="flex items-center justify-between text-xs text-ink-dim">
          <span className="tabular">
            Page {page} of {lastPage}
          </span>
          <span className="flex gap-3">
            {page > 1 && (
              <Link
                href={{ query: { ...params, page: page - 1 } }}
                className="text-accent hover:underline"
              >
                Previous
              </Link>
            )}
            {page < lastPage && (
              <Link
                href={{ query: { ...params, page: page + 1 } }}
                className="text-accent hover:underline"
              >
                Next
              </Link>
            )}
          </span>
        </nav>
      )}
    </div>
  );
}
