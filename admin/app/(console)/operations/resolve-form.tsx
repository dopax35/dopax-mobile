'use client';

import { useActionState } from 'react';
import { resolveConflict, resolveException, type ResolveState } from './actions';

const initial: ResolveState = {};

export function ResolveForm({
  id,
  kind,
  placeholder,
}: {
  id: string;
  kind: 'conflict' | 'exception';
  placeholder: string;
}) {
  const [state, action, pending] = useActionState(
    kind === 'conflict' ? resolveConflict : resolveException,
    initial,
  );

  return (
    <form action={action} className="mt-3 space-y-2">
      <input type="hidden" name="id" value={id} />

      <textarea
        name="resolutionNote"
        rows={2}
        placeholder={placeholder}
        className="w-full rounded-lg border border-line bg-canvas px-3 py-2 text-xs text-ink outline-none transition placeholder:text-ink-faint focus:border-accent/60"
      />

      <div className="flex items-center gap-3">
        <button
          type="submit"
          disabled={pending}
          className="rounded-lg border border-line bg-surface-2 px-3 py-1.5 text-xs font-medium text-ink transition hover:border-accent/50 disabled:opacity-60"
        >
          {pending ? 'Recording…' : 'Record decision'}
        </button>

        {state.error && <span className="text-xs text-bad">{state.error}</span>}
        {state.ok && <span className="text-xs text-good">{state.ok}</span>}
      </div>
    </form>
  );
}
