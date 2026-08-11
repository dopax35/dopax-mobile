/**
 * Opens a local ZIP (already downloaded read-only from Drive) and builds a
 * parse plan. Structured CSVs are loaded into memory one file at a time;
 * high-rate streams are catalogued without keeping their rows.
 */
import { open as yauzlOpen, type Entry, type ZipFile } from 'yauzl';
import { classifyZipEntry } from './zip-kinds.js';
import {
  catalogueEntry,
  emptyZipParsePlan,
  ingestStructuredCsv,
  type ZipParsePlan,
} from './zip-parse.js';

const STRUCTURED = new Set([
  'finger_tapping',
  'fingers_test',
  'hand_turning',
  'leg_agility',
  'spiral_tracing',
  'tmt',
  'voice_test',
  'questionnaire',
  'medication',
  'physical_activity',
  'sleep',
  'heart_rate',
  'profile',
]);

function openZip(path: string): Promise<ZipFile> {
  return new Promise((resolve, reject) => {
    yauzlOpen(path, { lazyEntries: true, autoClose: true }, (error, zip) => {
      if (error || !zip) reject(error ?? new Error('failed to open zip'));
      else resolve(zip);
    });
  });
}

function readEntry(zip: ZipFile, entry: Entry): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    zip.openReadStream(entry, (error, stream) => {
      if (error || !stream) {
        reject(error ?? new Error(`failed to read ${entry.fileName}`));
        return;
      }
      const chunks: Buffer[] = [];
      stream.on('data', (chunk: Buffer) => chunks.push(chunk));
      stream.on('error', reject);
      stream.on('end', () => resolve(Buffer.concat(chunks)));
    });
  });
}

/** Counts newline-terminated rows without holding the whole stream. */
function countLines(zip: ZipFile, entry: Entry): Promise<number> {
  return new Promise((resolve, reject) => {
    zip.openReadStream(entry, (error, stream) => {
      if (error || !stream) {
        reject(error ?? new Error(`failed to read ${entry.fileName}`));
        return;
      }
      let lines = 0;
      let leftover = '';
      stream.on('data', (chunk: Buffer) => {
        const text = leftover + chunk.toString('utf8');
        const parts = text.split('\n');
        leftover = parts.pop() ?? '';
        lines += parts.length;
      });
      stream.on('error', reject);
      stream.on('end', () => {
        if (leftover.trim().length > 0) lines += 1;
        // subtract header if present
        resolve(Math.max(0, lines - 1));
      });
    });
  });
}

export async function parseUploadZipFile(
  zipPath: string,
  collectionDate: string,
): Promise<ZipParsePlan> {
  const zip = await openZip(zipPath);
  const plan = emptyZipParsePlan();

  await new Promise<void>((resolve, reject) => {
    zip.on('error', reject);
    zip.on('end', () => resolve());
    zip.readEntry();

    zip.on('entry', (entry: Entry) => {
      void (async () => {
        try {
          if (/\/$/.test(entry.fileName)) {
            zip.readEntry();
            return;
          }

          const kind = classifyZipEntry(entry.fileName);
          const bytes = entry.uncompressedSize;

          if (STRUCTURED.has(kind)) {
            const buffer = await readEntry(zip, entry);
            ingestStructuredCsv(
              plan,
              entry.fileName,
              bytes,
              buffer.toString('utf8'),
              collectionDate,
            );
          } else if (kind === 'stream') {
            const rows = await countLines(zip, entry);
            catalogueEntry(plan, entry.fileName, bytes, rows);
          } else if (kind !== 'marker') {
            catalogueEntry(plan, entry.fileName, bytes, 0);
          }

          zip.readEntry();
        } catch (error) {
          reject(error);
        }
      })();
    });
  });

  return plan;
}
