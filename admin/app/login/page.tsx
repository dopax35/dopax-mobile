import { redirect } from 'next/navigation';
import { getSession } from '@/lib/session';
import { CredentialSignInForm } from './credential-form';

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ expired?: string }>;
}) {
  if (await getSession()) redirect('/progress');

  const params = await searchParams;

  return (
    <main className="flex min-h-screen items-center justify-center bg-canvas px-6 py-16">
      <div className="w-full max-w-md">
        <div className="mb-8 text-center">
          <p className="text-[11px] font-medium uppercase tracking-[0.25em] text-accent">DopaX</p>
          <h1 className="mt-2 text-2xl font-bold text-ink">Volunteer Progress Console</h1>
          <p className="mt-2 text-xs leading-relaxed text-ink-dim">
            Password-protected access to monitor volunteer app usage, daily file loads, active test dates, medication reports, and data integrity audits.
          </p>
        </div>

        {params.expired && (
          <div className="mb-6 rounded-lg border border-warn/40 bg-warn/5 px-4 py-3 text-xs text-warn text-center">
            Your session expired. Sign in again.
          </div>
        )}

        <div className="rounded-2xl border border-line bg-surface/80 p-6 shadow-xl backdrop-blur-md">
          <CredentialSignInForm />
        </div>

        <p className="mt-6 text-center text-[11px] text-ink-faint">
          Protected System &bull; Dopa-X Research Study
        </p>
      </div>
    </main>
  );
}
