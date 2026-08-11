import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { describe, expect, it } from 'vitest';
import {
  MANIFEST_FILE,
  loadDriveManifest,
  parseManifest,
  serialiseManifestLine,
  type DriveObject,
} from '../src/domain/drive/manifest.js';

const record: DriveObject = {
  fileId: '1abc',
  name: 'PDData_9EEBCD_2026-08-03.zip',
  bytes: 1_073_741_824,
  md5: 'd41d8cd98f00b204e9800998ecf8427e',
  mimeType: 'application/zip',
  createdTime: '2026-08-04T01:02:03.000Z',
  modifiedTime: '2026-08-04T01:02:03.000Z',
  parentPath: '',
};

function sourceDir(contents: string): string {
  const dir = mkdtempSync(join(tmpdir(), 'dopax-drive-'));
  const path = join(dir, MANIFEST_FILE);
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, contents);
  return dir;
}

describe('parseManifest', () => {
  it('round-trips a serialised record', () => {
    expect(parseManifest(serialiseManifestLine(record))).toEqual([record]);
  });

  it('ignores blank lines, including the trailing newline', () => {
    expect(parseManifest(`${serialiseManifestLine(record)}\n\n`)).toHaveLength(1);
  });

  it('rejects a truncated line rather than importing a short corpus', () => {
    const truncated = serialiseManifestLine(record).slice(0, 40);

    expect(() => parseManifest(`${serialiseManifestLine(record)}\n${truncated}`)).toThrow(
      /line 2 is not valid JSON/,
    );
  });

  it('rejects a record missing a field the importer relies on', () => {
    expect(() => parseManifest(JSON.stringify({ ...record, fileId: undefined }))).toThrow(
      /line 1 is not a Drive object/,
    );
  });

  it('rejects a repeated file id, which would be counted twice', () => {
    const line = serialiseManifestLine(record);

    expect(() => parseManifest(`${line}\n${line}`)).toThrow(/repeats Drive file id 1abc/);
  });
});

describe('loadDriveManifest', () => {
  it('reads the manifest and fingerprints it', () => {
    const manifest = loadDriveManifest(sourceDir(`${serialiseManifestLine(record)}\n`));

    expect(manifest.objects).toEqual([record]);
    expect(manifest.checksum).toMatch(/^[0-9a-f]{64}$/);
  });

  it('tells you how to produce a missing manifest instead of importing nothing', () => {
    const empty = mkdtempSync(join(tmpdir(), 'dopax-drive-'));

    expect(() => loadDriveManifest(empty)).toThrow(/npm run drive:inventory/);
  });
});
