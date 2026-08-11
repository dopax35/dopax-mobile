import type { Database } from '../../db/client.js';
import { planDriveManifestImport, summariseExceptions } from '../drive/inventory.js';
import { loadDriveManifest, type DriveManifest } from '../drive/manifest.js';
import {
  applyImportPlan,
  providerBreakdown,
  verifyAuthImport,
} from '../import/auth-users-repository.js';
import { loadAuthImportSources, type AuthImportSources } from '../import/auth-users-source.js';
import { planImport } from '../import/auth-users.js';
import {
  applyDriveManifestPlan,
  loadParticipantLookup,
  verifyDriveManifestImport,
} from '../import/drive-manifest-repository.js';
import {
  checksumPendingUploads,
  parsePendingUploads,
  verifyZipParse,
} from '../import/zip-parse-repository.js';
import type { BootstrapStep } from './runner.js';

export const AUTH_USERS_STEP = 'auth_users';
export const DRIVE_MANIFEST_STEP = 'drive_manifest';
export const DRIVE_ZIP_PARSE_STEP = 'drive_zip_parse';


/**
 * Step 1 of §4.4 — the 43 production accounts.
 *
 * This must run before anything that resolves an upload to a person: a Drive
 * ZIP whose participant code is not yet in the database cannot be attributed,
 * and guessing is the one thing the migration must never do.
 */
export function authUsersStep(database: Database, sourceDir: string): BootstrapStep {
  let sources: AuthImportSources | undefined;
  const load = (): AuthImportSources => (sources ??= loadAuthImportSources(sourceDir));

  return {
    name: AUTH_USERS_STEP,
    description: 'Firebase Auth export → participants, auth_identities, participant_id_conflicts',

    async checksum() {
      return load().checksum;
    },

    async run() {
      const { users, correlations } = load();
      const plan = planImport(users, correlations);
      const inDatabase = await applyImportPlan(database, plan);

      return {
        // Rows this run upserted — one participant and one identity each, plus
        // the conflicts. Deliberately not the table totals, which would report
        // the whole corpus on a replay that changed nothing.
        rowsWritten: plan.participants.length * 2 + plan.conflicts.length,
        detail: {
          inDatabase,
          authAccountsInExport: users.length,
          providers: await providerBreakdown(database),
          conflictedCodes: plan.conflicts.map((conflict) => conflict.legacyCode),
        },
      };
    },

    async verify() {
      await verifyAuthImport(database, load().users.length);
    },
  };
}

/**
 * Step 3 of §4.4 — the Drive folder inventory becomes `uploads` rows.
 *
 * Only the manifest is read here; not one byte of the corpus is transferred.
 * That is what makes a 1–2 GB-per-day archive importable on a laptop, and it
 * keeps this step to seconds so a failure in step 4 does not have to replay it.
 *
 * Depends on step 1: an upload can only be attributed to a participant who is
 * already in the database.
 */
export function driveManifestStep(database: Database, sourceDir: string): BootstrapStep {
  let manifest: DriveManifest | undefined;
  const load = (): DriveManifest => (manifest ??= loadDriveManifest(sourceDir));

  return {
    name: DRIVE_MANIFEST_STEP,
    description: 'Drive folder manifest → uploads, drive_manifest_exceptions',

    async checksum() {
      return load().checksum;
    },

    async run() {
      const { objects } = load();
      const plan = planDriveManifestImport(objects, await loadParticipantLookup(database));
      const counts = await applyDriveManifestPlan(database, plan);

      return {
        rowsWritten: plan.uploads.length + plan.exceptions.length,
        detail: {
          inDatabase: counts,
          objectsInManifest: plan.objectsSeen,
          bytesInManifest: plan.bytesSeen,
          exceptionsByReason: summariseExceptions(plan.exceptions),
        },
      };
    },

    async verify() {
      await verifyDriveManifestImport(database, load().objects.length);
    },
  };
}

/**
 * Step 4 of §4.4 — stream-parse each Drive ZIP into structured Postgres rows.
 *
 * Read-only against Drive: each ZIP is downloaded with GET, parsed locally,
 * then the temp file is deleted. High-rate streams are catalogued in
 * `upload_files` without loading every IMU/touch row (see §6.5).
 *
 * Prefer `npm run drive:parse` for long corpora — this step is registered so
 * production bootstrap can resume it, but a 60 GiB corpus will not finish
 * inside a short deploy window.
 */
export function driveZipParseStep(database: Database): BootstrapStep {
  return {
    name: DRIVE_ZIP_PARSE_STEP,
    description: 'Drive ZIPs → test_sessions, self-report tables, upload_files (read-only Drive)',

    async checksum() {
      return checksumPendingUploads(database);
    },

    async run() {
      const result = await parsePendingUploads(database);
      return {
        rowsWritten: result.rowsWritten,
        detail: result,
      };
    },

    async verify() {
      await verifyZipParse(database);
    },
  };
}

/**
 * The ordered pipeline. Steps 2 and 5 of §4.4 (Firestore profiles and
 * reconciliation) register here as they are written.
 */
export function bootstrapSteps(database: Database, sourceDir: string): BootstrapStep[] {
  return [
    authUsersStep(database, sourceDir),
    driveManifestStep(database, sourceDir),
    driveZipParseStep(database),
  ];
}

/**
 * Steps that must be complete before the backend may accept research data.
 *
 * ZIP parse is intentionally omitted: a multi-hour corpus backfill must not
 * block `/readyz`. Run `npm run drive:parse` (resumable) until uploads are
 * `parsed`.
 */
export const REQUIRED_BOOTSTRAP_STEPS: readonly string[] = [
  AUTH_USERS_STEP,
  DRIVE_MANIFEST_STEP,
];
