'use client';

import { useActionState } from 'react';
import { signInWithEmail, type SignInState } from './actions';

const initial: SignInState = {};

export function DevSignInForm() {
  const [state, action, pending] = useActionState(signInWithEmail, initial);

  return (
    <form action={action} className="space-y-3">
      <div>
        <label htmlFor="email" className="text-xs font-medium text-ink-dim">
          Staff email
        </label>
        <input
          id="email"
          name="email"
          type="email"
          autoComplete="username"
          placeholder="you@example.com"
          required
          className="mt-1.5 w-full rounded-lg border border-line bg-canvas px-3 py-2 font-mono text-sm text-ink outline-none transition placeholder:text-ink-faint focus:border-accent/60"
        />
      </div>

      <button
        type="submit"
        disabled={pending}
        className="w-full rounded-lg bg-accent/90 px-4 py-2.5 text-sm font-semibold text-canvas transition hover:bg-accent disabled:opacity-60"
      >
        {pending ? 'Signing in…' : 'Sign in'}
      </button>

      {state.error && <p className="text-xs leading-relaxed text-bad">{state.error}</p>}

      <p className="text-[11px] leading-relaxed text-ink-faint">
        Development only. The address must already be an active row in
        <code className="mx-1 font-mono">staff_users</code>; add one with
        <code className="mx-1 font-mono">npm run staff:add</code> in the backend.
      </p>
    </form>
  );
}
