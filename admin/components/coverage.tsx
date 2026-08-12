import type { FlipReadiness } from '@/lib/types';

function eachDay(from: string, to: string): string[] {
  const days: string[] = [];
  const cursor = new Date(`${from}T00:00:00Z`);
  const end = new Date(`${to}T00:00:00Z`);

  while (cursor <= end && days.length < 400) {
    days.push(cursor.toISOString().slice(0, 10));
    cursor.setUTCDate(cursor.getUTCDate() + 1);
  }

  return days;
}

/**
 * One square per day: the fastest way to see that a participant stopped
 * uploading, which today is only discoverable by noticing their ZIPs stopped
 * arriving in a Drive folder.
 */
export function CoverageStrip({
  from,
  to,
  presentDays,
  firstUploadDate,
}: {
  from: string;
  to: string;
  presentDays: string[];
  firstUploadDate?: string | null;
}) {
  const present = new Set(presentDays);
  const days = eachDay(from, to);

  return (
    <div className="flex flex-wrap gap-[3px]">
      {days.map((day) => {
        // Days before a participant's first upload are not misses, so they are
        // drawn as absent-but-not-expected.
        const beforeEnrolment = firstUploadDate ? day < firstUploadDate : false;
        const has = present.has(day);

        const tone = has
          ? 'bg-good'
          : beforeEnrolment
            ? 'bg-surface-2'
            : 'bg-bad/45';

        return (
          <span
            key={day}
            title={`${day} — ${has ? 'uploaded' : beforeEnrolment ? 'before first upload' : 'no upload'}`}
            className={`h-3.5 w-3.5 rounded-[3px] ${tone}`}
          />
        );
      })}
    </div>
  );
}

export function CoverageLegend() {
  return (
    <div className="flex items-center gap-4 text-[11px] text-ink-faint">
      <span className="flex items-center gap-1.5">
        <span className="h-3 w-3 rounded-[3px] bg-good" /> uploaded
      </span>
      <span className="flex items-center gap-1.5">
        <span className="h-3 w-3 rounded-[3px] bg-bad/45" /> missing
      </span>
      <span className="flex items-center gap-1.5">
        <span className="h-3 w-3 rounded-[3px] bg-surface-2" /> before first upload
      </span>
    </div>
  );
}

/**
 * R3 — the gate that decides when the legacy Google Drive pipeline stops being
 * authoritative. Fourteen consecutive clean reconciliation runs, and the count
 * resets on any run that is not clean.
 */
export function FlipGate({ flip }: { flip: FlipReadiness }) {
  const percent = Math.min(100, Math.round((flip.consecutiveCleanRuns / flip.required) * 100));

  return (
    <div>
      <div className="flex items-baseline justify-between">
        <p className="tabular text-2xl font-semibold text-ink">
          {flip.consecutiveCleanRuns}
          <span className="text-base font-normal text-ink-faint"> / {flip.required}</span>
        </p>
        <span className={`text-xs font-medium ${flip.ready ? 'text-good' : 'text-warn'}`}>
          {flip.ready ? 'ready to flip' : 'not ready'}
        </span>
      </div>

      <div className="mt-3 h-2 overflow-hidden rounded-full bg-surface-2">
        <div
          className={`h-full rounded-full ${flip.ready ? 'bg-good' : 'bg-warn'}`}
          style={{ width: `${Math.max(percent, 2)}%` }}
        />
      </div>

      <p className="mt-3 text-xs leading-relaxed text-ink-dim">
        {flip.ready
          ? 'Fourteen consecutive clean runs recorded. BOTH_ARCH can be set to false, reversibly.'
          : `Consecutive clean runs reset on the last non-clean result: ${flip.blockedBy}.`}
      </p>
    </div>
  );
}
