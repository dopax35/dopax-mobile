'use client';

import { useState, useTransition } from 'react';
import { signInWithFirebaseToken } from '@/app/login/actions';

/**
 * R1 — staff sign in through Firebase exactly as participants do. The ID token is
 * handed straight to a server action and never stored in the browser; what comes
 * back is an httpOnly session cookie.
 *
 * Firebase is imported dynamically so the SDK is not in the bundle for a
 * deployment that has no Firebase configuration.
 */
export function FirebaseSignIn({ configured }: { configured: boolean }) {
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  if (!configured) {
    return (
      <p className="text-xs leading-relaxed text-ink-faint">
        Google sign-in is unavailable: this deployment has no{' '}
        <code className="font-mono">NEXT_PUBLIC_FIREBASE_API_KEY</code>.
      </p>
    );
  }

  async function signIn() {
    setError(null);

    try {
      const [{ initializeApp, getApps }, { getAuth, GoogleAuthProvider, signInWithPopup }] =
        await Promise.all([import('firebase/app'), import('firebase/auth')]);

      const config = {
        apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY!,
        authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN!,
        projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID!,
      };

      const app = getApps()[0] ?? initializeApp(config);
      const credential = await signInWithPopup(getAuth(app), new GoogleAuthProvider());
      const idToken = await credential.user.getIdToken();

      startTransition(async () => {
        const result = await signInWithFirebaseToken(idToken);
        if (result?.error) setError(result.error);
      });
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Google sign-in failed.');
    }
  }

  return (
    <div>
      <button
        type="button"
        onClick={signIn}
        disabled={pending}
        className="w-full rounded-lg border border-line bg-surface-2 px-4 py-2.5 text-sm font-medium text-ink transition hover:border-accent/50 hover:bg-surface disabled:opacity-60"
      >
        {pending ? 'Signing in…' : 'Continue with Google'}
      </button>

      {error && <p className="mt-3 text-xs text-bad">{error}</p>}
    </div>
  );
}
