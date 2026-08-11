/**
 * Phase 0 — inventory the legacy Google Drive folder.
 *
 *   npm run drive:inventory              walk the folder, write the manifest
 *   npm run drive:inventory -- --check   prove the credential can see it, then stop
 *
 * Read-only against Drive and against the database, which it never opens. The
 * output is `<MIGRATION_SOURCE_DIR>/drive/manifest.jsonl`, the input to
 * bootstrap step 3.
 *
 * This is the number the whole of Phase 2 is estimated against: until it runs,
 * nobody knows how large the research corpus is, or whether `gdrive`
 * passthrough (§5.3) is a convenience or a hard requirement.
 *
 * Credential (first available):
 *   - service account JSON key (if org policy allows), or
 *   - user OAuth from `npm run drive:login` (preferred when keys are blocked), or
 *   - application default credentials (e.g. SA impersonation)
 */
import 'dotenv/config';
import { existsSync, mkdirSync, renameSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { env } from '../src/config/env.js';
import { parseUploadFilename } from '../src/domain/drive/filename.js';
import {
  MANIFEST_FILE,
  serialiseManifestLine,
  type DriveObject,
} from '../src/domain/drive/manifest.js';
import { checkFolderAccess, listFolder } from '../src/infra/drive/list-folder.js';
import {
  defaultOauthClientPath,
  defaultUserTokenPath,
  userTokenExists,
} from '../src/infra/drive/user-oauth.js';

const checkOnly = process.argv.includes('--check');

function describeCredential(keyPath: string | undefined): string {
  if (keyPath && existsSync(keyPath)) return `service account key (${keyPath})`;
  if (userTokenExists()) {
    return `user OAuth (${defaultUserTokenPath()}; client ${defaultOauthClientPath()})`;
  }
  return 'application default credentials';
}

function formatBytes(bytes: number): string {
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  let value = bytes;
  let unit = 0;

  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }

  return `${value.toFixed(unit === 0 ? 0 : 1)} ${units[unit]}`;
}

function summarise(objects: readonly DriveObject[]): void {
  const totalBytes = objects.reduce((sum, object) => sum + (object.bytes ?? 0), 0);
  const participants = new Set<string>();
  const platforms = { android: 0, ios: 0 };
  const dates: string[] = [];
  const unrecognised: string[] = [];
  let largest: DriveObject | undefined;

  for (const object of objects) {
    if ((object.bytes ?? 0) > (largest?.bytes ?? -1)) largest = object;

    const parsed = parseUploadFilename(object.name);
    if (!parsed.ok) {
      unrecognised.push(`${object.name} (${parsed.reason})`);
      continue;
    }

    participants.add(parsed.value.legacyUserId);
    platforms[parsed.value.platform] += 1;
    dates.push(parsed.value.collectionDate);
  }

  dates.sort();

  console.log('');
  console.log(`objects            ${objects.length}`);
  console.log(`total size         ${formatBytes(totalBytes)}`);
  console.log(`largest object     ${largest ? `${formatBytes(largest.bytes ?? 0)}  ${largest.name}` : '—'}`);
  console.log(`recognised uploads ${platforms.android + platforms.ios} (${platforms.android} android, ${platforms.ios} ios)`);
  console.log(`participant codes  ${participants.size}`);
  console.log(`date range         ${dates.length > 0 ? `${dates[0]} → ${dates.at(-1)}` : '—'}`);
  console.log(`unrecognised names ${unrecognised.length}`);

  // Listed in full rather than counted: every one of these is a Drive object
  // that will land in drive_manifest_exceptions and need a human, and seeing
  // them here is what tells you whether the parser or the corpus is wrong.
  for (const name of unrecognised.slice(0, 25)) console.log(`  · ${name}`);
  if (unrecognised.length > 25) console.log(`  · … ${unrecognised.length - 25} more`);
}

async function main(): Promise<number> {
  const config = env();
  const folderId = config.LEGACY_DRIVE_FOLDER_ID;

  if (!folderId) {
    console.error('LEGACY_DRIVE_FOLDER_ID is not set; nothing to inventory.');
    return 1;
  }

  const target = resolve(process.cwd(), config.MIGRATION_SOURCE_DIR, MANIFEST_FILE);

  console.log(`[inventory] folder    ${folderId}`);
  console.log(`[inventory] manifest  ${target}`);
  console.log(`[inventory] auth      ${describeCredential(config.GOOGLE_APPLICATION_CREDENTIALS)}`);

  const access = await checkFolderAccess(folderId);
  console.log(`[inventory] identity  ${access.identity}`);
  console.log(`[inventory] folder    "${access.folderName}" is readable`);
  for (const name of access.sampleNames) console.log(`[inventory]   · ${name}`);

  if (checkOnly) {
    console.log('[inventory] --check passed; no manifest written');
    return 0;
  }

  const startedAt = Date.now();
  const objects = await listFolder(folderId, {
    onPage: ({ objects: seen, folder }) =>
      console.log(`[inventory] ${seen} objects listed (in ${folder})`),
  });

  // Written whole and then renamed: a half-written manifest that still parses
  // is an under-count, and an under-count is what a clean reconciliation run
  // would then certify as complete.
  mkdirSync(dirname(target), { recursive: true });
  const temporary = `${target}.tmp`;
  writeFileSync(temporary, objects.map(serialiseManifestLine).join('\n') + '\n', 'utf8');
  renameSync(temporary, target);

  console.log(`[inventory] wrote ${objects.length} records in ${Date.now() - startedAt} ms`);
  summarise(objects);

  return 0;
}

let exitCode = 1;
try {
  exitCode = await main();
} catch (error) {
  console.error('[inventory] failed:', error instanceof Error ? error.stack : error);
}

process.exit(exitCode);
