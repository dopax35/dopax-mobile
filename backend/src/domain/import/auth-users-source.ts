import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import type { CorrelationRow, FirebaseAuthUser } from './auth-users.js';

export const AUTH_EXPORT_FILE = 'users.json';
export const CORRELATIONS_FILE = 'master_user_correlations.csv';

export interface AuthImportSources {
  users: FirebaseAuthUser[];
  correlations: CorrelationRow[];
  /** Fingerprint of both files; a change is what makes the step run again. */
  checksum: string;
  authExportPath: string;
  correlationsPath: string;
}

/**
 * Minimal CSV reader: these exports are plain, unquoted, comma-separated.
 *
 * A row whose field count does not match the header is rejected rather than
 * padded or truncated. An embedded comma — in a display name, say — shifts
 * every column after it, and a participant silently correlated to the wrong
 * file prefix is precisely the misattribution this migration must not produce.
 */
export function parseCorrelationsCsv(contents: string): CorrelationRow[] {
  const [header, ...lines] = contents.trim().split('\n');
  const columns = header!.split(',').map((column) => column.trim());

  return lines
    .map((line, i) => ({ line, lineNumber: i + 2 }))
    .filter(({ line }) => line.trim().length > 0)
    .map(({ line, lineNumber }) => {
      const values = line.split(',');

      if (values.length !== columns.length) {
        throw new Error(
          `correlation CSV line ${lineNumber} has ${values.length} fields, expected ` +
            `${columns.length}. An unquoted comma in a value would misalign every column ` +
            `after it, so this is rejected rather than guessed.`,
        );
      }

      return Object.fromEntries(
        columns.map((column, i) => [column, values[i]!.trim()]),
      ) as unknown as CorrelationRow;
    });
}

function read(path: string, what: string): string {
  try {
    return readFileSync(path, 'utf8');
  } catch (error) {
    // Skipping this step would leave production with no participants, so every
    // existing user would be treated as brand new and their historical uploads
    // would fail to resolve. Aborting the whole bootstrap is the safe failure.
    throw new Error(
      `cannot read the ${what} at ${path}. The first-run migration needs the production ` +
        `exports; mount them and set MIGRATION_SOURCE_DIR to their directory. ` +
        `(${error instanceof Error ? error.message : String(error)})`,
    );
  }
}

export function loadAuthImportSources(sourceDir: string): AuthImportSources {
  const authExportPath = resolve(sourceDir, AUTH_EXPORT_FILE);
  const correlationsPath = resolve(sourceDir, CORRELATIONS_FILE);

  const authExportRaw = read(authExportPath, 'Firebase Auth export');
  const correlationsRaw = read(correlationsPath, 'participant correlation CSV');

  const parsed = JSON.parse(authExportRaw) as { users?: FirebaseAuthUser[] };
  if (!Array.isArray(parsed.users)) {
    throw new Error(`${authExportPath} has no "users" array; is it a Firebase Auth export?`);
  }

  const checksum = createHash('sha256')
    .update(authExportRaw)
    .update('\0')
    .update(correlationsRaw)
    .digest('hex');

  return {
    users: parsed.users,
    correlations: parseCorrelationsCsv(correlationsRaw),
    checksum,
    authExportPath,
    correlationsPath,
  };
}
