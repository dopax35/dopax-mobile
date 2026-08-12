import { redirect } from 'next/navigation';
import type { ReactNode } from 'react';
import { signOut } from '@/app/login/actions';
import { Nav } from '@/components/nav';
import { Badge } from '@/components/ui';
import { getSession } from '@/lib/session';

const ROLE_DESCRIPTION = {
  viewer: 'Aggregates only. No participant detail.',
  researcher: 'Research data, pseudonymised by participant code.',
  admin: 'Full access, including identity and the audit trail.',
};

export default async function ConsoleLayout({ children }: { children: ReactNode }) {
  const session = await getSession();
  if (!session) redirect('/login');

  const { staff } = session;

  return (
    <div className="flex min-h-screen">
      <aside className="flex w-60 shrink-0 flex-col border-r border-line bg-surface/40 px-4 py-6">
        <div className="px-3">
          <p className="text-[11px] font-medium uppercase tracking-[0.2em] text-accent">DopaX</p>
          <p className="mt-1 text-sm font-semibold text-ink">Staff console</p>
        </div>

        <div className="mt-8 flex-1">
          <Nav role={staff.role} />
        </div>

        <div className="border-t border-line px-3 pt-4">
          <p className="truncate text-xs font-medium text-ink" title={staff.email}>
            {staff.displayName ?? staff.email}
          </p>
          <p className="mt-1.5">
            <Badge tone="accent" title={ROLE_DESCRIPTION[staff.role]}>
              {staff.role}
            </Badge>
          </p>

          <form action={signOut}>
            <button
              type="submit"
              className="mt-3 text-xs text-ink-faint underline-offset-2 transition hover:text-ink hover:underline"
            >
              Sign out
            </button>
          </form>
        </div>
      </aside>

      <main className="min-w-0 flex-1 px-8 py-8">
        <div className="mx-auto max-w-6xl">{children}</div>
      </main>
    </div>
  );
}
