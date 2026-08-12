import type { StaffRole } from '../../auth/admin-token.js';

/**
 * What each role is allowed to see, and how upload history becomes adherence.
 *
 * Pure on purpose: these are the judgement calls a reviewer and an ethics board
 * care about, so they are unit-testable without a database or an HTTP request.
 */

/**
 * A participant's email and display name are identifying; their participant code
 * is the pseudonym the study already works in. So `researcher` — the role that
 * reads the actual research data — deliberately does not get identity, and
 * `viewer` gets neither identity nor clinical detail.
 */
export function canSeeIdentity(role: StaffRole): boolean {
  return role === 'admin';
}

export function canSeeClinicalDetail(role: StaffRole): boolean {
  return role === 'admin' || role === 'researcher';
}

export interface ParticipantIdentityFields {
  email: string | null;
  displayName: string | null;
  firebaseUid: string | null;
}

export interface ParticipantRow extends Partial<ParticipantIdentityFields> {
  id: string;
  participantCode: string;
  status: string;
  isTestAccount: boolean;
  cohort: string | null;
  enrolledAt: Date | null;
  provider: string | null;
  /**
   * Kept for every role. These are the study's own pseudonyms — the codes that
   * appear in historical Drive filenames — and correlating an old filename to a
   * participant is exactly what a researcher is here to do. One of the three
   * legacy formats happens to be the Firebase UID, because early builds used it
   * as the participant code; it identifies a row, not a person.
   */
  legacyFileUserIds: string[];
}

/**
 * Redaction drops keys rather than nulling them, so a client cannot tell a
 * withheld value from an absent one and no accidental "email: null" implies the
 * participant has no email.
 */
export function redactParticipant<T extends ParticipantRow>(
  row: T,
  role: StaffRole,
): Omit<T, keyof ParticipantIdentityFields> | T {
  if (canSeeIdentity(role)) return row;

  const { email: _email, displayName: _displayName, firebaseUid: _uid, ...rest } = row;
  return rest as Omit<T, keyof ParticipantIdentityFields>;
}

export interface UploadDay {
  collectionDate: string;
  platform: string;
  status: string;
}

export interface AdherenceWindow {
  /** Inclusive, `yyyy-MM-dd`. */
  from: string;
  /** Inclusive, `yyyy-MM-dd`. */
  to: string;
}

export interface AdherenceSummary {
  window: AdherenceWindow;
  expectedDays: number;
  daysWithUpload: number;
  /** Fraction 0–1, or null when the window is empty. */
  coverage: number | null;
  lastUploadDate: string | null;
  /** Consecutive days with no upload, counted back from the window end. */
  currentGapDays: number;
  /** Every run of missing days, longest first. */
  gaps: { from: string; to: string; days: number }[];
  platforms: string[];
}

export function toDayString(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function addDays(day: string, delta: number): string {
  const date = new Date(`${day}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + delta);
  return toDayString(date);
}

function daysBetween(from: string, to: string): number {
  const ms = new Date(`${to}T00:00:00Z`).getTime() - new Date(`${from}T00:00:00Z`).getTime();
  return Math.floor(ms / 86_400_000);
}

/**
 * Adherence is measured from the participant's *first* upload, not from
 * enrolment: counting the days before anyone ever uploaded would report every
 * late joiner as non-adherent. A participant with no uploads at all therefore
 * has no coverage figure rather than a misleading 0%.
 */
export function summariseAdherence(
  uploads: readonly UploadDay[],
  window: AdherenceWindow,
): AdherenceSummary {
  const inWindow = uploads.filter(
    (upload) => upload.collectionDate >= window.from && upload.collectionDate <= window.to,
  );

  const days = [...new Set(inWindow.map((upload) => upload.collectionDate))].sort();
  const platforms = [...new Set(inWindow.map((upload) => upload.platform))].sort();
  const lastUploadDate = days.at(-1) ?? null;

  if (days.length === 0) {
    return {
      window,
      expectedDays: 0,
      daysWithUpload: 0,
      coverage: null,
      lastUploadDate: null,
      currentGapDays: 0,
      gaps: [],
      platforms,
    };
  }

  const [firstDay] = days;
  if (firstDay === undefined) throw new Error('unreachable: days is non-empty here');

  const expectedDays = daysBetween(firstDay, window.to) + 1;
  const present = new Set(days);

  const gaps: { from: string; to: string; days: number }[] = [];
  let runStart: string | undefined;

  for (let offset = 0; offset < expectedDays; offset += 1) {
    const day = addDays(firstDay, offset);

    if (present.has(day)) {
      if (runStart) {
        gaps.push({ from: runStart, to: addDays(day, -1), days: daysBetween(runStart, day) });
        runStart = undefined;
      }
      continue;
    }

    runStart ??= day;
  }

  if (runStart) {
    gaps.push({
      from: runStart,
      to: window.to,
      days: daysBetween(runStart, window.to) + 1,
    });
  }

  const trailingGap = gaps.at(-1);
  const currentGapDays = trailingGap?.to === window.to ? trailingGap.days : 0;

  return {
    window,
    expectedDays,
    daysWithUpload: days.length,
    coverage: days.length / expectedDays,
    lastUploadDate,
    currentGapDays,
    gaps: [...gaps].sort((a, b) => b.days - a.days),
    platforms,
  };
}

/**
 * R3 — the flip to BOTH_ARCH=false needs 14 consecutive clean reconciliation
 * runs. Counting is done here so the number the console shows and the number the
 * gate uses can never drift apart.
 */
export const CLEAN_RUNS_REQUIRED_FOR_FLIP = 14;

export interface ReconciliationRunSummary {
  status: string;
  runAt: Date;
}

export interface FlipReadiness {
  consecutiveCleanRuns: number;
  required: number;
  ready: boolean;
  blockedBy: string | null;
}

export function assessFlipReadiness(runs: readonly ReconciliationRunSummary[]): FlipReadiness {
  const newestFirst = [...runs].sort((a, b) => b.runAt.getTime() - a.runAt.getTime());

  let consecutive = 0;
  for (const run of newestFirst) {
    if (run.status !== 'clean') break;
    consecutive += 1;
  }

  const firstNonClean = newestFirst.find((run) => run.status !== 'clean');

  return {
    consecutiveCleanRuns: consecutive,
    required: CLEAN_RUNS_REQUIRED_FOR_FLIP,
    ready: consecutive >= CLEAN_RUNS_REQUIRED_FOR_FLIP,
    blockedBy:
      consecutive >= CLEAN_RUNS_REQUIRED_FOR_FLIP
        ? null
        : (firstNonClean?.status ?? 'no reconciliation runs recorded'),
  };
}
