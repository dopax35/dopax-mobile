import { sql } from 'drizzle-orm';
import {
  bigint,
  date,
  index,
  integer,
  jsonb,
  pgTable,
  text,
  timestamp,
  unique,
  uuid,
} from 'drizzle-orm/pg-core';
import { participants } from './identity.js';

export const devices = pgTable(
  'devices',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    participantId: uuid('participant_id')
      .notNull()
      .references(() => participants.id, { onDelete: 'cascade' }),
    deviceInstallId: text('device_install_id').notNull(),
    platform: text('platform').notNull(), // android | ios
    model: text('model'),
    osVersion: text('os_version'),
    appVersion: text('app_version'),
    firstSeenAt: timestamp('first_seen_at', { withTimezone: true }).notNull().defaultNow(),
    lastSeenAt: timestamp('last_seen_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    unique('devices_participant_install_key').on(t.participantId, t.deviceInstallId),
    index('devices_last_seen_idx').on(t.lastSeenAt),
  ],
);

/**
 * One row per participant-day-platform. That uniqueness constraint is the
 * backbone of the whole pipeline: it makes every ingest retryable, and during
 * dual-run (R3) it collapses the same day arriving via both the client API and
 * the Drive drain worker into a single row instead of double-counting it.
 *
 * storageBackend='gdrive' means the raw ZIP was never copied anywhere: it is
 * stream-parsed straight from Drive and objectKey holds the Drive file id.
 * That is what makes laptop-only development viable against a corpus far
 * larger than the local disk.
 */
export const uploads = pgTable(
  'uploads',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    participantId: uuid('participant_id')
      .notNull()
      .references(() => participants.id),
    deviceId: uuid('device_id').references(() => devices.id),
    platform: text('platform').notNull(),
    collectionDate: date('collection_date').notNull(),
    filename: text('filename').notNull(),
    storageBackend: text('storage_backend').notNull().default('gdrive'),
    objectKey: text('object_key'),
    legacyDriveFileId: text('legacy_drive_file_id'),
    bytes: bigint('bytes', { mode: 'number' }),
    sha256: text('sha256'),
    // Drive reports md5, not sha256. Kept in its own column rather than
    // squeezed into sha256, because reconciliation compares it against Drive
    // and a checksum recorded under the wrong algorithm is worse than none.
    driveMd5: text('drive_md5'),
    uploadSessionId: text('upload_session_id'),
    source: text('source').notNull().default('api'), // api | drive_backfill | drive_drain
    status: text('status').notNull().default('pending'),
    // pending | uploading | stored | parsing | parsed | failed
    receivedAt: timestamp('received_at', { withTimezone: true }),
    parsedAt: timestamp('parsed_at', { withTimezone: true }),
    error: text('error'),
  },
  (t) => [
    unique('uploads_participant_date_platform_key').on(
      t.participantId,
      t.collectionDate,
      t.platform,
    ),
    index('uploads_status_idx').on(t.status),
    index('uploads_participant_date_idx').on(t.participantId, t.collectionDate),
    index('uploads_source_idx').on(t.source),
  ],
);

export const uploadFiles = pgTable(
  'upload_files',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    uploadId: uuid('upload_id')
      .notNull()
      .references(() => uploads.id, { onDelete: 'cascade' }),
    pathInZip: text('path_in_zip').notNull(),
    kind: text('kind').notNull(), // csv schema name | voice_audio | json | crash_log
    rowCount: integer('row_count'),
    bytes: bigint('bytes', { mode: 'number' }),
  },
  (t) => [
    index('upload_files_upload_idx').on(t.uploadId),
    index('upload_files_kind_idx').on(t.kind),
  ],
);

/**
 * Every Drive object the manifest import could not turn into an `uploads` row.
 *
 * This table exists so that the corpus always adds up: objects in the manifest
 * equals uploads imported plus exceptions recorded. An object nobody can
 * attribute — an unrecognised filename, a participant code that is not in the
 * study, the contested `pd_53a21c75` — becomes a row here for a human instead
 * of being skipped, which is what stops a missing participant-day from being
 * discovered months later during analysis.
 */
export const driveManifestExceptions = pgTable(
  'drive_manifest_exceptions',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    driveFileId: text('drive_file_id').notNull().unique(),
    filename: text('filename').notNull(),
    bytes: bigint('bytes', { mode: 'number' }),
    driveMd5: text('drive_md5'),
    reason: text('reason').notNull(),
    // not_an_upload | malformed_date | unknown_participant |
    // contested_participant_code | duplicate_participant_day
    detail: jsonb('detail').notNull().default(sql`'{}'::jsonb`),
    firstSeenAt: timestamp('first_seen_at', { withTimezone: true }).notNull().defaultNow(),
    lastSeenAt: timestamp('last_seen_at', { withTimezone: true }).notNull().defaultNow(),
    resolvedAt: timestamp('resolved_at', { withTimezone: true }),
    resolutionNote: text('resolution_note'),
  },
  (t) => [
    index('drive_manifest_exceptions_reason_idx').on(t.reason),
    index('drive_manifest_exceptions_unresolved_idx').on(t.resolvedAt),
  ],
);

/**
 * R3 — the nightly Drive-vs-Postgres diff. Fourteen consecutive `clean` runs is
 * the gate for flipping BOTH_ARCH to false.
 */
export const reconciliationRuns = pgTable(
  'reconciliation_runs',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    runAt: timestamp('run_at', { withTimezone: true }).notNull().defaultNow(),
    mode: text('mode').notNull(), // both_arch | backend_only
    driveObjects: integer('drive_objects').notNull(),
    driveBytes: bigint('drive_bytes', { mode: 'number' }).notNull(),
    dbUploads: integer('db_uploads').notNull(),
    dbParsed: integer('db_parsed').notNull(),
    missingInDb: jsonb('missing_in_db').notNull().default(sql`'[]'::jsonb`),
    missingInDrive: jsonb('missing_in_drive').notNull().default(sql`'[]'::jsonb`),
    mismatched: jsonb('mismatched').notNull().default(sql`'[]'::jsonb`),
    status: text('status').notNull(), // clean | discrepancies | failed
  },
  (t) => [index('reconciliation_runs_run_at_idx').on(t.runAt)],
);
