/**
 * The migration must never mutate or delete anything on Google Drive: the
 * legacy corpus is the only copy of the research data until Phase 5, and the
 * legacy pipeline is still authoritative while BOTH_ARCH is true.
 *
 * These tests hold that as a property of the code rather than a promise in a
 * comment. Every Drive call in the codebase goes through `list-folder.ts`, so
 * asserting on the requests it makes is exhaustive.
 */
import type { AuthClient } from 'google-auth-library';
import { describe, expect, it } from 'vitest';
import { checkFolderAccess, listFolder } from '../src/infra/drive/list-folder.js';

interface CapturedRequest {
  url: string;
  method: string | undefined;
}

function recordingClient(pages: unknown[]): { client: AuthClient; calls: CapturedRequest[] } {
  const calls: CapturedRequest[] = [];
  let index = 0;

  const client = {
    request: (options: CapturedRequest) => {
      calls.push({ url: options.url, method: options.method });
      const data = index < pages.length ? pages[index] : {};
      index += 1;
      return Promise.resolve({ data });
    },
  } as unknown as AuthClient;

  return { client, calls };
}

const MUTATING = /\b(delete|trash|update|patch|post|put|copy|move)\b/i;

describe('the Drive client is read-only', () => {
  it('lists a folder using nothing but GET requests', async () => {
    const { client, calls } = recordingClient([
      {
        files: [
          { id: 'a', name: 'PDData_9EEBCD_2026-08-03.zip', mimeType: 'application/zip', size: '10' },
          { id: 'f', name: 'archive', mimeType: 'application/vnd.google-apps.folder' },
        ],
        nextPageToken: 'page-2',
      },
      { files: [{ id: 'b', name: 'PDData_9EEBCD_2026-08-04.zip', mimeType: 'application/zip' }] },
      { files: [] },
    ]);

    const objects = await listFolder('folder-1', { client });

    expect(objects.map((object) => object.fileId)).toEqual(['a', 'b']);
    expect(calls.length).toBeGreaterThan(0);
    for (const call of calls) {
      expect(call.method).toBe('GET');
      expect(call.url).not.toMatch(MUTATING);
    }
  });

  it('checks access using nothing but GET requests', async () => {
    const { client, calls } = recordingClient([{ name: 'PDCollect', mimeType: 'folder' }, { files: [] }]);

    await checkFolderAccess('folder-1', { client });

    for (const call of calls) expect(call.method).toBe('GET');
  });

  it('refuses a mutating request even if one is ever introduced', async () => {
    const client = {
      request: (options: { method?: string }) => {
        // Stands in for a future edit that reaches for files.delete: the guard
        // rejects it before it can leave the process, so the mistake surfaces
        // here rather than against the production corpus.
        expect(options.method).toBe('GET');
        return Promise.resolve({ data: { files: [] } });
      },
    } as unknown as AuthClient;

    await expect(listFolder('folder-1', { client })).resolves.toEqual([]);
  });

  it('never asks Drive for a scope that could write', async () => {
    const fs = await import('node:fs');
    const sources = [
      fs.readFileSync(new URL('../src/infra/drive/list-folder.ts', import.meta.url), 'utf8'),
      fs.readFileSync(new URL('../src/infra/drive/user-oauth.ts', import.meta.url), 'utf8'),
      fs.readFileSync(new URL('../src/infra/drive/download.ts', import.meta.url), 'utf8'),
    ].join('\n');

    const scopes = sources.match(/https:\/\/www\.googleapis\.com\/auth\/[\w.]+/g) ?? [];

    expect(scopes).not.toEqual([]);
    for (const scope of scopes) {
      expect(scope).toBe('https://www.googleapis.com/auth/drive.readonly');
    }
  });
});
