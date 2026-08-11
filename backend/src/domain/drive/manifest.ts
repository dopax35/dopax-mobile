/**
 * The Drive manifest — Phase 0's inventory of the legacy folder, and the input
 * to bootstrap step 3 (MIGRATION_PLAN.md §4.4).
 *
 * JSON Lines rather than a single JSON document: the corpus size is unknown,
 * and a partially written array is unreadable while a partially written JSONL
 * file loses only its last line. Every record is one Drive object exactly as
 * the API reported it, with no interpretation applied yet.
 */
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { z } from 'zod';

export const MANIFEST_FILE = 'drive/manifest.jsonl';

const driveObjectSchema = z.object({
  fileId: z.string().min(1),
  name: z.string().min(1),
  /** Google reports size as a string, and omits it for folders. */
  bytes: z.number().int().nonnegative().nullable(),
  md5: z.string().nullable(),
  mimeType: z.string(),
  createdTime: z.string().nullable(),
  modifiedTime: z.string().nullable(),
  /** Folder path below the legacy root, empty for objects at the top level. */
  parentPath: z.string(),
});

export type DriveObject = z.infer<typeof driveObjectSchema>;

export interface DriveManifest {
  objects: DriveObject[];
  /** Fingerprint of the file; a change is what makes the step run again. */
  checksum: string;
  path: string;
}

export function serialiseManifestLine(object: DriveObject): string {
  return JSON.stringify(object);
}

export function parseManifest(contents: string): DriveObject[] {
  const objects: DriveObject[] = [];
  const seen = new Set<string>();

  const lines = contents.split('\n');

  for (const [index, line] of lines.entries()) {
    if (line.trim().length === 0) continue;

    const lineNumber = index + 1;
    let raw: unknown;

    try {
      raw = JSON.parse(line);
    } catch (error) {
      throw new Error(
        `manifest line ${lineNumber} is not valid JSON. Re-run the inventory rather than ` +
          `hand-editing it. (${error instanceof Error ? error.message : String(error)})`,
      );
    }

    const parsed = driveObjectSchema.safeParse(raw);
    if (!parsed.success) {
      throw new Error(
        `manifest line ${lineNumber} is not a Drive object: ${parsed.error.issues
          .map((issue) => `${issue.path.join('.') || '(root)'} ${issue.message}`)
          .join('; ')}`,
      );
    }

    // A repeated file id would be counted twice by reconciliation and could
    // resolve to two different participant-days, so it is a broken inventory
    // rather than something to deduplicate quietly.
    if (seen.has(parsed.data.fileId)) {
      throw new Error(
        `manifest line ${lineNumber} repeats Drive file id ${parsed.data.fileId}; ` +
          `the inventory is inconsistent and must be regenerated`,
      );
    }

    seen.add(parsed.data.fileId);
    objects.push(parsed.data);
  }

  return objects;
}

export function loadDriveManifest(sourceDir: string): DriveManifest {
  const path = resolve(sourceDir, MANIFEST_FILE);

  let contents: string;
  try {
    contents = readFileSync(path, 'utf8');
  } catch (error) {
    // Continuing without it would record a completed migration over an empty
    // corpus, which reconciliation would then bless. Aborting is the only safe
    // failure.
    throw new Error(
      `cannot read the Drive manifest at ${path}. Generate it with ` +
        `\`npm run drive:inventory\` (needs a service account with read access to the ` +
        `legacy folder), or set MIGRATION_SOURCE_DIR to where it is mounted. ` +
        `(${error instanceof Error ? error.message : String(error)})`,
    );
  }

  return {
    objects: parseManifest(contents),
    checksum: createHash('sha256').update(contents).digest('hex'),
    path,
  };
}
