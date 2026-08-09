import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import {
  loadAuthImportSources,
  parseCorrelationsCsv,
} from '../src/domain/import/auth-users-source.js';

function sourceDir(files: { users?: string; correlations?: string }): string {
  const dir = mkdtempSync(join(tmpdir(), 'dopax-import-'));
  if (files.users !== undefined) writeFileSync(join(dir, 'users.json'), files.users);
  if (files.correlations !== undefined) {
    writeFileSync(join(dir, 'master_user_correlations.csv'), files.correlations);
  }
  return dir;
}

const CORRELATIONS = 'uid,file_user_id,email\nuid-hex,9EEBCD,a@b.com\n';
const USERS = JSON.stringify({ users: [{ localId: 'uid-hex', email: 'a@b.com' }] });

describe('parseCorrelationsCsv', () => {
  it('maps columns onto rows and trims whitespace', () => {
    expect(parseCorrelationsCsv('uid, file_user_id\n abc , 9EEBCD \n')).toEqual([
      { uid: 'abc', file_user_id: '9EEBCD' },
    ]);
  });

  it('ignores blank trailing lines', () => {
    expect(parseCorrelationsCsv('uid,file_user_id\nabc,9EEBCD\n\n')).toHaveLength(1);
  });

  it('rejects a row with an unquoted comma rather than misaligning its columns', () => {
    const csv = 'uid,name,file_user_id\nabc,Doe, John,9EEBCD\n';

    expect(() => parseCorrelationsCsv(csv)).toThrow(/line 2 has 4 fields, expected 3/);
  });

  it('rejects a short row rather than padding the missing column', () => {
    expect(() => parseCorrelationsCsv('uid,name,file_user_id\nabc,Doe\n')).toThrow(
      /line 2 has 2 fields, expected 3/,
    );
  });
});

describe('loadAuthImportSources', () => {
  it('reads both exports', () => {
    const sources = loadAuthImportSources(
      sourceDir({ users: USERS, correlations: CORRELATIONS }),
    );

    expect(sources.users).toHaveLength(1);
    expect(sources.correlations).toEqual([
      { uid: 'uid-hex', file_user_id: '9EEBCD', email: 'a@b.com' },
    ]);
  });

  it('produces a stable checksum for identical inputs', () => {
    const a = loadAuthImportSources(sourceDir({ users: USERS, correlations: CORRELATIONS }));
    const b = loadAuthImportSources(sourceDir({ users: USERS, correlations: CORRELATIONS }));

    expect(a.checksum).toBe(b.checksum);
  });

  it('changes the checksum when either export changes', () => {
    const base = loadAuthImportSources(sourceDir({ users: USERS, correlations: CORRELATIONS }));
    const extraUser = loadAuthImportSources(
      sourceDir({
        users: JSON.stringify({ users: [{ localId: 'uid-hex' }, { localId: 'uid-new' }] }),
        correlations: CORRELATIONS,
      }),
    );
    const extraCorrelation = loadAuthImportSources(
      sourceDir({ users: USERS, correlations: `${CORRELATIONS}uid-new,42976F,c@d.com\n` }),
    );

    expect(extraUser.checksum).not.toBe(base.checksum);
    expect(extraCorrelation.checksum).not.toBe(base.checksum);
  });

  it('refuses to proceed when an export is missing, naming the path and the fix', () => {
    const dir = sourceDir({ correlations: CORRELATIONS });

    expect(() => loadAuthImportSources(dir)).toThrow(/users\.json/);
    expect(() => loadAuthImportSources(dir)).toThrow(/MIGRATION_SOURCE_DIR/);
  });

  it('rejects a JSON file that is not a Firebase Auth export', () => {
    const dir = sourceDir({ users: '{"accounts":[]}', correlations: CORRELATIONS });

    expect(() => loadAuthImportSources(dir)).toThrow(/no "users" array/);
  });
});
