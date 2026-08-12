'use client';

/**
 * Keeps a failed panel legible instead of a blank screen. The three failures a
 * reader can actually act on — the backend being down, a role being too low, and
 * the backend refusing an unauditable read — say what to do about it.
 */
export default function ConsoleError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  const isUnreachable = error.name === 'BackendUnreachable' || /did not respond/.test(error.message);
  const isForbidden = error.name === 'Forbidden' || /role/.test(error.message);
  const isAudit = error.name === 'AuditUnavailable' || /audit/.test(error.message);

  return (
    <div className="max-w-2xl rounded-xl border border-bad/40 bg-surface/60 px-6 py-6">
      <h1 className="text-base font-semibold text-bad">
        {isUnreachable
          ? 'The backend is not reachable'
          : isForbidden
            ? 'Not available with your role'
            : isAudit
              ? 'This read was refused'
              : 'Something failed loading this view'}
      </h1>

      <p className="mt-2 text-sm leading-relaxed text-ink-dim">
        {isUnreachable ? (
          <>
            Start it with <code className="font-mono text-xs">npm run dev</code> in{' '}
            <code className="font-mono text-xs">backend/</code>, and check that{' '}
            <code className="font-mono text-xs">BACKEND_URL</code> points at it.
          </>
        ) : isForbidden ? (
          'Ask an admin to raise your role if you need this view.'
        ) : isAudit ? (
          'The backend could not record who was about to read this, so it declined to serve it. That is deliberate: participant data is never served unaudited.'
        ) : (
          error.message
        )}
      </p>

      <button
        type="button"
        onClick={reset}
        className="mt-5 rounded-lg border border-line bg-surface-2 px-3 py-1.5 text-xs font-medium text-ink transition hover:border-accent/50"
      >
        Try again
      </button>
    </div>
  );
}
