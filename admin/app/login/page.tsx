import { redirect } from 'next/navigation';
import { FirebaseSignIn } from '@/components/firebase-sign-in';
import { fetchAuthMethods } from '@/lib/api';
import { getSession } from '@/lib/session';
import { DevSignInForm } from './dev-form';

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ expired?: string }>;
}) {
  if (await getSession()) redirect('/');

  const [methods, params] = await Promise.all([fetchAuthMethods(), searchParams]);
  const firebaseConfigured = Boolean(process.env.NEXT_PUBLIC_FIREBASE_API_KEY);

  return (
    <main className="flex min-h-screen items-center justify-center px-6 py-16">
      <div className="w-full max-w-sm">
        <div className="mb-8">
          <p className="text-[11px] font-medium uppercase tracking-[0.2em] text-accent">DopaX</p>
          <h1 className="mt-2 text-2xl font-semibold text-ink">Staff console</h1>
          <p className="mt-2 text-sm leading-relaxed text-ink-dim">
            Participant activity and study monitoring. Access is granted per account and every
            read of participant data is recorded.
          </p>
        </div>

        {params.expired && (
          <div className="mb-6 rounded-lg border border-warn/40 bg-warn/5 px-4 py-3 text-xs text-warn">
            Your session expired. Sign in again.
          </div>
        )}

        <div className="space-y-5 rounded-xl border border-line bg-surface/60 px-5 py-5">
          <FirebaseSignIn configured={firebaseConfigured} />

          {methods.devLogin && (
            <>
              <div className="flex items-center gap-3">
                <span className="h-px flex-1 bg-line" />
                <span className="text-[10px] uppercase tracking-widest text-ink-faint">
                  development
                </span>
                <span className="h-px flex-1 bg-line" />
              </div>

              <DevSignInForm />
            </>
          )}
        </div>

        {!methods.devLogin && !firebaseConfigured && (
          <p className="mt-5 text-xs leading-relaxed text-ink-faint">
            No sign-in method is available. Either configure Firebase for this app, or enable
            <code className="mx-1 font-mono">ADMIN_DEV_LOGIN</code> on a development backend.
          </p>
        )}
      </div>
    </main>
  );
}
