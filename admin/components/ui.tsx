import type { ReactNode } from 'react';

export function Card({
  title,
  description,
  action,
  children,
  className = '',
}: {
  title?: string;
  description?: ReactNode;
  action?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section
      className={`rounded-xl border border-line bg-surface/60 backdrop-blur-sm ${className}`}
    >
      {(title || action) && (
        <header className="flex items-start justify-between gap-4 border-b border-line px-5 py-3.5">
          <div>
            {title && <h2 className="text-sm font-semibold tracking-wide text-ink">{title}</h2>}
            {description && <p className="mt-1 text-xs text-ink-faint">{description}</p>}
          </div>
          {action}
        </header>
      )}
      <div className="px-5 py-4">{children}</div>
    </section>
  );
}

export function StatTile({
  label,
  value,
  hint,
  tone = 'neutral',
}: {
  label: string;
  value: ReactNode;
  hint?: ReactNode;
  tone?: 'neutral' | 'good' | 'warn' | 'bad';
}) {
  const toneClass = {
    neutral: 'text-ink',
    good: 'text-good',
    warn: 'text-warn',
    bad: 'text-bad',
  }[tone];

  return (
    <div className="rounded-xl border border-line bg-surface/60 px-5 py-4">
      <p className="text-[11px] font-medium uppercase tracking-widest text-ink-faint">{label}</p>
      <p className={`tabular mt-2 text-3xl font-semibold leading-none ${toneClass}`}>{value}</p>
      {hint && <p className="mt-2 text-xs leading-relaxed text-ink-dim">{hint}</p>}
    </div>
  );
}

const BADGE_TONES: Record<string, string> = {
  neutral: 'border-line bg-surface-2 text-ink-dim',
  good: 'border-good/30 bg-good/10 text-good',
  warn: 'border-warn/30 bg-warn/10 text-warn',
  bad: 'border-bad/30 bg-bad/10 text-bad',
  accent: 'border-accent/30 bg-accent/10 text-accent',
};

export function Badge({
  children,
  tone = 'neutral',
  title,
}: {
  children: ReactNode;
  tone?: keyof typeof BADGE_TONES | string;
  title?: string;
}) {
  return (
    <span
      title={title}
      className={`inline-flex items-center rounded-md border px-1.5 py-0.5 text-[11px] font-medium ${
        BADGE_TONES[tone] ?? BADGE_TONES.neutral
      }`}
    >
      {children}
    </span>
  );
}

/** Shared vocabulary for the status strings the backend stores as free text. */
export function statusTone(status: string): string {
  switch (status) {
    case 'active':
    case 'parsed':
    case 'clean':
    case 'completed':
    case 'stored':
      return 'good';
    case 'pending':
    case 'parsing':
    case 'uploading':
    case 'running':
    case 'discrepancies':
      return 'warn';
    case 'failed':
    case 'needs_id_resolution':
    case 'withdrawn':
      return 'bad';
    default:
      return 'neutral';
  }
}

export function Table({
  head,
  children,
  empty,
}: {
  head: ReactNode[];
  children: ReactNode;
  empty?: ReactNode;
}) {
  return (
    <div className="-mx-5 overflow-x-auto">
      <table className="w-full min-w-full border-collapse text-sm">
        <thead>
          <tr className="border-b border-line">
            {head.map((cell, index) => (
              <th
                key={index}
                className="px-5 py-2 text-left text-[11px] font-medium uppercase tracking-widest text-ink-faint"
              >
                {cell}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-line/60">{children}</tbody>
      </table>
      {empty}
    </div>
  );
}

export function Cell({
  children,
  mono = false,
  dim = false,
  className = '',
}: {
  children: ReactNode;
  mono?: boolean;
  dim?: boolean;
  className?: string;
}) {
  return (
    <td
      className={`px-5 py-2.5 align-middle ${mono ? 'font-mono text-xs' : ''} ${
        dim ? 'text-ink-dim' : ''
      } ${className}`}
    >
      {children}
    </td>
  );
}

export function EmptyState({ title, children }: { title: string; children?: ReactNode }) {
  return (
    <div className="rounded-lg border border-dashed border-line px-5 py-8 text-center">
      <p className="text-sm font-medium text-ink-dim">{title}</p>
      {children && (
        <p className="mx-auto mt-2 max-w-xl text-xs leading-relaxed text-ink-faint">{children}</p>
      )}
    </div>
  );
}

/**
 * A horizontal bar for a 0–1 fraction. `null` renders as "no data" rather than an
 * empty bar, because an empty bar reads as zero adherence.
 */
export function Meter({ fraction, label }: { fraction: number | null; label?: string }) {
  if (fraction === null) {
    return <span className="text-xs text-ink-faint">no uploads yet</span>;
  }

  const percent = Math.round(fraction * 100);
  const tone = percent >= 80 ? 'bg-good' : percent >= 50 ? 'bg-warn' : 'bg-bad';

  return (
    <div className="flex items-center gap-2">
      <div className="h-1.5 w-24 overflow-hidden rounded-full bg-surface-2">
        <div className={`h-full rounded-full ${tone}`} style={{ width: `${percent}%` }} />
      </div>
      <span className="tabular text-xs text-ink-dim">{label ?? `${percent}%`}</span>
    </div>
  );
}

export function Notice({
  tone = 'warn',
  title,
  children,
}: {
  tone?: 'warn' | 'bad' | 'accent';
  title: string;
  children?: ReactNode;
}) {
  const border = { warn: 'border-warn/40', bad: 'border-bad/40', accent: 'border-accent/40' }[tone];
  const text = { warn: 'text-warn', bad: 'text-bad', accent: 'text-accent' }[tone];

  return (
    <div className={`rounded-xl border ${border} bg-surface/50 px-5 py-4`}>
      <p className={`text-sm font-semibold ${text}`}>{title}</p>
      {children && (
        <div className="mt-1.5 text-xs leading-relaxed text-ink-dim">{children}</div>
      )}
    </div>
  );
}
