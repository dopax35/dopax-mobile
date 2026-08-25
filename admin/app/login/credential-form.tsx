'use client';

import { useActionState } from 'react';
import { signInWithCredentials, type SignInState } from './actions';

const initial: SignInState = {};

export function CredentialSignInForm() {
  const [state, action, pending] = useActionState(signInWithCredentials, initial);

  return (
    <form action={action} className="space-y-4">
      <div>
        <label htmlFor="username" className="text-xs font-medium text-ink-dim">
          Username
        </label>
        <input
          id="username"
          name="username"
          type="text"
          autoComplete="username"
          placeholder="dopax"
          defaultValue="dopax"
          required
          className="mt-1.5 w-full rounded-lg border border-line bg-canvas px-3 py-2 font-mono text-sm text-ink outline-none transition placeholder:text-ink-faint focus:border-accent/60"
        />
      </div>

      <div>
        <label htmlFor="password" className="text-xs font-medium text-ink-dim">
          Password
        </label>
        <input
          id="password"
          name="password"
          type="password"
          autoComplete="current-password"
          placeholder="••••••••"
          defaultValue="dopax35"
          required
          className="mt-1.5 w-full rounded-lg border border-line bg-canvas px-3 py-2 font-mono text-sm text-ink outline-none transition placeholder:text-ink-faint focus:border-accent/60"
        />
      </div>

      <button
        type="submit"
        disabled={pending}
        className="w-full rounded-lg bg-accent px-4 py-2.5 text-sm font-semibold text-canvas transition hover:opacity-90 disabled:opacity-60"
      >
        {pending ? 'Signing in…' : 'Sign in to Progress Review'}
      </button>

      {state.error && (
        <div className="rounded-lg border border-bad/30 bg-bad/10 px-3 py-2 text-xs text-bad">
          {state.error}
        </div>
      )}
    </form>
  );
}
