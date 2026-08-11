/**
 * Parse Drive ZIPs into Postgres (read-only on Drive).
 *
 *   npm run drive:parse
 *   npm run drive:parse -- --limit=20
 *   npm run drive:parse -- --max-bytes=50000000
 *
 * Downloads each ZIP with GET only, extracts structured CSVs into Postgres,
 * catalogues high-rate streams without loading their rows, then deletes the
 * local temp copy. Nothing on Drive is created, changed, or deleted.
 */
import 'dotenv/config';
import { env } from '../src/config/env.js';
import { closeDatabase, db } from '../src/db/client.js';
import { parsePendingUploads } from '../src/domain/import/zip-parse-repository.js';

function flag(name: string): string | undefined {
  const prefix = `--${name}=`;
  return process.argv.find((arg) => arg.startsWith(prefix))?.slice(prefix.length);
}

async function main(): Promise<number> {
  const config = env();
  const limit = flag('limit') ? Number(flag('limit')) : undefined;
  const maxBytes = flag('max-bytes') ? Number(flag('max-bytes')) : undefined;

  console.log(`[parse] database ${config.DATABASE_URL.replace(/:[^:@/]*@/, ':***@')}`);
  console.log(`[parse] limit=${limit ?? 'none'} maxBytes=${maxBytes ?? 'none'}`);
  console.log('[parse] Drive access: read-only GET downloads only');

  const result = await parsePendingUploads(db(), {
    ...(limit !== undefined && Number.isFinite(limit) ? { limit } : {}),
    ...(maxBytes !== undefined && Number.isFinite(maxBytes) ? { maxBytes } : {}),
    onProgress: ({ index, total, upload, rowsWritten }) => {
      console.log(
        `[parse] ${index}/${total} ${upload.filename} (${upload.bytes ?? '?'} bytes) → ${rowsWritten} rows`,
      );
    },
  });

  console.log(
    `[parse] done parsed=${result.parsed} failed=${result.failed} rowsWritten=${result.rowsWritten}`,
  );
  return result.failed > 0 ? 1 : 0;
}

let exitCode = 1;
try {
  exitCode = await main();
} catch (error) {
  console.error('[parse] failed:', error instanceof Error ? error.stack : error);
} finally {
  await closeDatabase();
}

process.exit(exitCode);
