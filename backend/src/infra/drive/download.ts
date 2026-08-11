/**
 * Read-only download of a Drive file's bytes.
 *
 * Uses GET + alt=media only. The file is written to a local temp path for
 * parsing and must be deleted by the caller afterwards — nothing is written
 * back to Drive.
 */
import { createWriteStream } from 'node:fs';
import { pipeline } from 'node:stream/promises';
import type { AuthClient } from 'google-auth-library';
import { GoogleAuth } from 'google-auth-library';
import {
  DRIVE_READONLY_SCOPE,
  authedUserOAuthClient,
  defaultUserTokenPath,
  userTokenExists,
} from './user-oauth.js';
import { existsSync } from 'node:fs';

const DRIVE_FILES_URL = 'https://www.googleapis.com/drive/v3/files';

function assertGet(method: string | undefined, url: string): void {
  if (method !== undefined && method !== 'GET') {
    throw new Error(
      `refusing a ${method} request to ${url}: this migration never mutates Google Drive.`,
    );
  }
}

async function driveClient(options?: {
  keyFile?: string;
  client?: AuthClient;
}): Promise<AuthClient> {
  if (options?.client) return options.client;

  const keyFile = options?.keyFile ?? process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (keyFile && existsSync(keyFile)) {
    return new GoogleAuth({ scopes: [DRIVE_READONLY_SCOPE], keyFile }).getClient();
  }

  if (userTokenExists(defaultUserTokenPath())) {
    return authedUserOAuthClient();
  }

  return new GoogleAuth({ scopes: [DRIVE_READONLY_SCOPE] }).getClient();
}

/** Streams a Drive file to `destinationPath`. Read-only. */
export async function downloadDriveFile(
  fileId: string,
  destinationPath: string,
  options?: { keyFile?: string; client?: AuthClient },
): Promise<{ bytesWritten: number }> {
  const client = await driveClient(options);
  const url = `${DRIVE_FILES_URL}/${fileId}?alt=media`;
  assertGet('GET', url);

  const response = await client.request({
    url,
    method: 'GET',
    responseType: 'stream',
  });

  let bytesWritten = 0;
  const source = response.data as NodeJS.ReadableStream;
  source.on('data', (chunk: Buffer | string) => {
    bytesWritten += typeof chunk === 'string' ? Buffer.byteLength(chunk) : chunk.length;
  });

  await pipeline(source, createWriteStream(destinationPath));
  return { bytesWritten };
}
