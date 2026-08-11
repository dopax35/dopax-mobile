/**
 * Turns a Drive manifest into the `uploads` rows of bootstrap step 3, plus an
 * explicit exception for every object that could not be attributed.
 *
 * Pure: no database, no Drive, no filesystem. Every judgement call about who a
 * ZIP belongs to lives here so it can be reviewed and tested on its own.
 *
 * The governing rule is the accounting identity enforced by `verify`:
 *
 *     objects in the manifest  ==  uploads planned + exceptions recorded
 *
 * Nothing is ever dropped. An object we cannot attribute becomes a row someone
 * has to look at, which is the loud failure the guardrails require, rather than
 * a silent omission that reconciliation would later report as a Drive-only file
 * with no explanation.
 */
import { parseUploadFilename, type Platform } from './filename.js';
import type { DriveObject } from './manifest.js';

export interface ParticipantLookup {
  /** Participant code and every legacy file id form → participant id. */
  participantIdByLegacyId: ReadonlyMap<string, string>;
  /** Codes claimed by more than one account; these must never be routed. */
  contestedCodes: ReadonlySet<string>;
}

export interface PlannedUpload {
  participantId: string;
  legacyUserId: string;
  platform: Platform;
  collectionDate: string;
  filename: string;
  driveFileId: string;
  bytes: number | null;
  md5: string | null;
  createdTime: Date | null;
}

export type ExceptionReason =
  | 'not_an_upload'
  | 'malformed_date'
  | 'unknown_participant'
  | 'contested_participant_code'
  | 'duplicate_participant_day';

export interface PlannedException {
  driveFileId: string;
  filename: string;
  bytes: number | null;
  md5: string | null;
  reason: ExceptionReason;
  detail: Record<string, unknown>;
}

export interface DriveManifestPlan {
  uploads: PlannedUpload[];
  exceptions: PlannedException[];
  objectsSeen: number;
  bytesSeen: number;
}

function toDate(value: string | null): Date | null {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function exceptionOf(
  object: DriveObject,
  reason: ExceptionReason,
  detail: Record<string, unknown> = {},
): PlannedException {
  return {
    driveFileId: object.fileId,
    filename: object.name,
    bytes: object.bytes,
    md5: object.md5,
    reason,
    detail: object.parentPath ? { ...detail, parentPath: object.parentPath } : detail,
  };
}

/**
 * Two Drive objects for the same participant-day-platform collide on the
 * `uploads` idempotency key. It happens for real: a client that retried across
 * a rename, or a day re-zipped after a fix. Rather than let insertion order
 * decide, the largest wins — a re-upload of the same day is a superset of it —
 * with creation time and then file id breaking ties so the choice is stable
 * across runs. The losers are recorded, not discarded.
 */
function chooseCanonical(candidates: PlannedUpload[]): {
  canonical: PlannedUpload;
  superseded: PlannedUpload[];
} {
  const ordered = [...candidates].sort((a, b) => {
    const bytes = (b.bytes ?? -1) - (a.bytes ?? -1);
    if (bytes !== 0) return bytes;

    const created = (b.createdTime?.getTime() ?? 0) - (a.createdTime?.getTime() ?? 0);
    if (created !== 0) return created;

    return a.driveFileId.localeCompare(b.driveFileId);
  });

  return { canonical: ordered[0]!, superseded: ordered.slice(1) };
}

export function planDriveManifestImport(
  objects: readonly DriveObject[],
  lookup: ParticipantLookup,
): DriveManifestPlan {
  const exceptions: PlannedException[] = [];
  const byParticipantDay = new Map<string, PlannedUpload[]>();
  let bytesSeen = 0;

  for (const object of objects) {
    bytesSeen += object.bytes ?? 0;

    const parsed = parseUploadFilename(object.name);
    if (!parsed.ok) {
      exceptions.push(exceptionOf(object, parsed.reason));
      continue;
    }

    const { legacyUserId, collectionDate, platform } = parsed.value;

    // Checked before the lookup: a contested code may also exist as a
    // participant code in its own right, and routing it would hand one
    // person's research data to the other.
    if (lookup.contestedCodes.has(legacyUserId)) {
      exceptions.push(
        exceptionOf(object, 'contested_participant_code', { legacyUserId, collectionDate }),
      );
      continue;
    }

    const participantId = lookup.participantIdByLegacyId.get(legacyUserId);
    if (!participantId) {
      exceptions.push(exceptionOf(object, 'unknown_participant', { legacyUserId, collectionDate }));
      continue;
    }

    const key = `${participantId}\u0000${collectionDate}\u0000${platform}`;
    const upload: PlannedUpload = {
      participantId,
      legacyUserId,
      platform,
      collectionDate,
      filename: object.name,
      driveFileId: object.fileId,
      bytes: object.bytes,
      md5: object.md5,
      createdTime: toDate(object.createdTime),
    };

    byParticipantDay.set(key, [...(byParticipantDay.get(key) ?? []), upload]);
  }

  const uploads: PlannedUpload[] = [];

  for (const candidates of byParticipantDay.values()) {
    if (candidates.length === 1) {
      uploads.push(candidates[0]!);
      continue;
    }

    const { canonical, superseded } = chooseCanonical(candidates);
    uploads.push(canonical);

    for (const loser of superseded) {
      exceptions.push({
        driveFileId: loser.driveFileId,
        filename: loser.filename,
        bytes: loser.bytes,
        md5: loser.md5,
        reason: 'duplicate_participant_day',
        detail: {
          legacyUserId: loser.legacyUserId,
          collectionDate: loser.collectionDate,
          platform: loser.platform,
          chosenDriveFileId: canonical.driveFileId,
          chosenBytes: canonical.bytes,
        },
      });
    }
  }

  return { uploads, exceptions, objectsSeen: objects.length, bytesSeen };
}

export function summariseExceptions(
  exceptions: readonly PlannedException[],
): Record<ExceptionReason, number> {
  const counts = {
    not_an_upload: 0,
    malformed_date: 0,
    unknown_participant: 0,
    contested_participant_code: 0,
    duplicate_participant_day: 0,
  } satisfies Record<ExceptionReason, number>;

  for (const exception of exceptions) counts[exception.reason] += 1;

  return counts;
}
