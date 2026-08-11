import { isNull, sql } from 'drizzle-orm';
import type { Database } from '../../db/client.js';
import {
  driveManifestExceptions,
  participantIdConflicts,
  participants,
  uploads,
} from '../../db/schema/index.js';
import type { DriveManifestPlan, ParticipantLookup } from '../drive/inventory.js';

/** Kept well below the parameter ceiling; the corpus size is still unknown. */
const CHUNK = 500;

function chunked<T>(items: readonly T[]): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < items.length; i += CHUNK) chunks.push(items.slice(i, i + CHUNK));
  return chunks;
}

/**
 * Every identifier a historical filename might carry, mapped to its owner.
 *
 * A code recorded in `participant_id_conflicts` and not yet resolved is
 * excluded from routing entirely — it is claimed by two accounts, so any
 * mapping would be a guess about whose medical data this is. Once a human
 * records a resolution, the code drops out of the contested set and resolves
 * through whichever participant's `legacy_file_user_ids` they added it to.
 */
export async function loadParticipantLookup(database: Database): Promise<ParticipantLookup> {
  const rows = await database
    .select({
      id: participants.id,
      code: participants.participantCode,
      legacyIds: participants.legacyFileUserIds,
    })
    .from(participants);

  const contested = await database
    .select({ code: participantIdConflicts.legacyCode })
    .from(participantIdConflicts)
    .where(isNull(participantIdConflicts.resolvedAt));

  const contestedCodes = new Set(contested.map((row) => row.code));
  const participantIdByLegacyId = new Map<string, string>();

  for (const row of rows) {
    for (const identifier of [row.code, ...row.legacyIds]) {
      if (contestedCodes.has(identifier)) continue;
      participantIdByLegacyId.set(identifier, row.id);
    }
  }

  return { participantIdByLegacyId, contestedCodes };
}

export interface DriveImportCounts {
  uploads: number;
  exceptions: number;
  unresolvedExceptions: number;
}

/**
 * One transaction, so the step is all-or-nothing and the bootstrap can replay
 * it after a crash. Idempotent: uploads upsert on the participant-day-platform
 * key and exceptions on the Drive file id.
 */
export async function applyDriveManifestPlan(
  database: Database,
  plan: DriveManifestPlan,
): Promise<DriveImportCounts> {
  await database.transaction(async (tx) => {
    for (const batch of chunked(plan.uploads)) {
      await tx
        .insert(uploads)
        .values(
          batch.map((upload) => ({
            participantId: upload.participantId,
            platform: upload.platform,
            collectionDate: upload.collectionDate,
            filename: upload.filename,
            storageBackend: 'gdrive',
            objectKey: upload.driveFileId,
            legacyDriveFileId: upload.driveFileId,
            bytes: upload.bytes,
            driveMd5: upload.md5,
            source: 'drive_backfill',
            status: 'stored',
            receivedAt: upload.createdTime,
          })),
        )
        .onConflictDoUpdate({
          target: [uploads.participantId, uploads.collectionDate, uploads.platform],
          set: {
            // Drive facts are authoritative while BOTH_ARCH is true.
            legacyDriveFileId: sql`excluded.legacy_drive_file_id`,
            driveMd5: sql`excluded.drive_md5`,
            bytes: sql`coalesce(${uploads.bytes}, excluded.bytes)`,
            objectKey: sql`coalesce(${uploads.objectKey}, excluded.object_key)`,
            receivedAt: sql`coalesce(${uploads.receivedAt}, excluded.received_at)`,
            // Everything below is deliberately conservative. The same
            // participant-day can arrive from the client API during dual-run,
            // and rediscovering it on Drive must never undo work: a row that
            // has been parsed stays parsed, and an API upload keeps its
            // provenance.
            status: sql`case when ${uploads.status} in ('parsing', 'parsed')
                        then ${uploads.status} else 'stored' end`,
            source: sql`case when ${uploads.source} = 'api'
                        then ${uploads.source} else excluded.source end`,
          },
        });
    }

    for (const batch of chunked(plan.exceptions)) {
      await tx
        .insert(driveManifestExceptions)
        .values(
          batch.map((exception) => ({
            driveFileId: exception.driveFileId,
            filename: exception.filename,
            bytes: exception.bytes,
            driveMd5: exception.md5,
            reason: exception.reason,
            detail: exception.detail,
          })),
        )
        .onConflictDoUpdate({
          target: driveManifestExceptions.driveFileId,
          set: {
            filename: sql`excluded.filename`,
            bytes: sql`excluded.bytes`,
            driveMd5: sql`excluded.drive_md5`,
            reason: sql`excluded.reason`,
            detail: sql`excluded.detail`,
            lastSeenAt: new Date(),
            // resolvedAt and resolutionNote are never touched: a human decision
            // must survive every re-run of the inventory.
          },
        });
    }
  });

  return countDriveImport(database);
}

export async function countDriveImport(database: Database): Promise<DriveImportCounts> {
  const [counts] = await database
    .select({
      uploads: sql<number>`(select count(*)::int from uploads where legacy_drive_file_id is not null)`,
      exceptions: sql<number>`(select count(*)::int from drive_manifest_exceptions)`,
      unresolvedExceptions: sql<number>`(select count(*)::int from drive_manifest_exceptions where resolved_at is null)`,
    })
    .from(sql`(select 1) as _`);

  return counts!;
}

/**
 * The accounting identity from §4.4: a source count that does not equal the
 * database count fails the run rather than warning. Objects may legitimately be
 * unattributable, but every one of them must be visible as an exception —
 * "we lost track of 12 ZIPs" is precisely the outcome this migration exists to
 * make impossible.
 */
export async function verifyDriveManifestImport(
  database: Database,
  objectsInManifest: number,
): Promise<void> {
  const counts = await countDriveImport(database);
  const accounted = counts.uploads + counts.exceptions;

  if (accounted !== objectsInManifest) {
    throw new Error(
      `Drive object count mismatch: ${objectsInManifest} in the manifest, ${accounted} ` +
        `accounted for in the database (${counts.uploads} uploads + ${counts.exceptions} exceptions)`,
    );
  }
}
