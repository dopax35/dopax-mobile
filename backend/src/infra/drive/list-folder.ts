/**
 * Read-only inventory of the legacy Google Drive folder.
 *
 * Scoped to `drive.readonly` deliberately and permanently: nothing in this
 * migration may mutate or delete anything on Drive, and the cheapest way to
 * guarantee that is a credential that cannot.
 *
 * Credential order (first match wins):
 *   1. options.client — tests
 *   2. options.keyFile / GOOGLE_APPLICATION_CREDENTIALS — service account key
 *   3. secrets/drive-user-token.json — user OAuth from `npm run drive:login`
 *   4. Application Default Credentials (e.g. impersonated SA)
 */
import { existsSync } from 'node:fs';
import { GoogleAuth, type AuthClient } from 'google-auth-library';
import type { DriveObject } from '../../domain/drive/manifest.js';
import {
  DRIVE_READONLY_SCOPE,
  authedUserOAuthClient,
  defaultUserTokenPath,
  userTokenExists,
} from './user-oauth.js';

const DRIVE_FILES_URL = 'https://www.googleapis.com/drive/v3/files';
const READONLY_SCOPE = DRIVE_READONLY_SCOPE;
const FOLDER_MIME = 'application/vnd.google-apps.folder';
const PAGE_SIZE = 1000;
const MAX_ATTEMPTS = 5;

interface DriveFile {
  id: string;
  name: string;
  size?: string;
  md5Checksum?: string;
  mimeType: string;
  createdTime?: string;
  modifiedTime?: string;
}

interface FileListResponse {
  files?: DriveFile[];
  nextPageToken?: string;
}

export interface ListFolderOptions {
  /** Path to a service account key; defaults to GOOGLE_APPLICATION_CREDENTIALS. */
  keyFile?: string;
  /** Path to the OAuth Desktop client JSON from Cloud Console. */
  oauthClientPath?: string;
  /** Path to the refresh token written by `npm run drive:login`. */
  userTokenPath?: string;
  /** Called after each page so a multi-hour inventory shows progress. */
  onPage?: (info: { objects: number; folder: string }) => void;
  sleep?: (ms: number) => Promise<void>;
  /** Test seam. Production always authenticates through GoogleAuth below. */
  client?: AuthClient;
}

/**
 * Second line of defence behind the read-only scope.
 *
 * The scope already makes a destructive call impossible — Google would refuse
 * it — but that protection lives in a credential someone could later widen
 * without touching this file. Every Drive call in the codebase goes through
 * here, so a mutating request fails in our own process, in review, and in the
 * test suite rather than depending on the token being right.
 */
function readOnly(options: {
  url: string;
  params?: Record<string, string | number | boolean>;
  method?: string;
}): { url: string; method: 'GET'; params?: Record<string, string | number | boolean> } {
  if (options.method !== undefined && options.method !== 'GET') {
    throw new Error(
      `refusing a ${options.method} request to ${options.url}: this migration never mutates ` +
        `Google Drive. Nothing on Drive is created, changed, or deleted in any mode.`,
    );
  }

  return { ...options, method: 'GET' };
}

const wait = (ms: number): Promise<void> => new Promise((done) => setTimeout(done, ms));

function isRetryable(error: unknown): boolean {
  const status = (error as { response?: { status?: number } }).response?.status;
  // 403 covers Drive's rateLimitExceeded, which is the one we actually hit on a
  // folder this size; 401 is not retryable and must surface as a credential
  // problem rather than five slow failures.
  return status === 403 || status === 429 || (status !== undefined && status >= 500);
}

async function requestPage(
  client: AuthClient,
  params: Record<string, string | number | boolean>,
  sleep: (ms: number) => Promise<void>,
): Promise<FileListResponse> {
  let lastError: unknown;

  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1) {
    try {
      const response = await client.request<FileListResponse>(
        readOnly({ url: DRIVE_FILES_URL, params }),
      );
      return response.data;
    } catch (error) {
      lastError = error;
      if (!isRetryable(error) || attempt === MAX_ATTEMPTS) break;
      await sleep(2 ** attempt * 250);
    }
  }

  throw lastError;
}

async function connect(
  options: ListFolderOptions,
): Promise<{ client: AuthClient; auth?: GoogleAuth; identity: string }> {
  if (options.client) {
    return { client: options.client, identity: '(injected test client)' };
  }

  const keyFile = options.keyFile ?? process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (keyFile && existsSync(keyFile)) {
    const auth = new GoogleAuth({
      scopes: [READONLY_SCOPE],
      keyFile,
    });
    const client = await auth.getClient();
    const email = (await auth.getCredentials()).client_email ?? '(service account)';
    return { client, auth, identity: email };
  }

  const tokenPath = options.userTokenPath ?? defaultUserTokenPath();
  if (userTokenExists(tokenPath)) {
    const client = authedUserOAuthClient({
      userTokenPath: tokenPath,
      ...(options.oauthClientPath ? { oauthClientPath: options.oauthClientPath } : {}),
    });
    return { client, identity: '(signed-in Google user via drive:login)' };
  }

  const auth = new GoogleAuth({ scopes: [READONLY_SCOPE] });
  const client = await auth.getClient();
  const email = (await auth.getCredentials()).client_email ?? '(application default credentials)';
  return { client, auth, identity: email };
}

export interface AccessCheck {
  /** The service account this credential belongs to, when it is one. */
  identity: string;
  folderName: string;
  sampleNames: string[];
}

/**
 * Confirms the credential can actually see the folder, before a listing that
 * may run for a long time. The two failures worth naming are the two that
 * happen: the Drive API is not enabled on the project, and the folder was
 * never shared with the service account. Drive reports the second as a 404,
 * which reads like a wrong folder id and sends you looking in the wrong place.
 */
export async function checkFolderAccess(
  folderId: string,
  options: ListFolderOptions = {},
): Promise<AccessCheck> {
  const { client, identity } = await connect(options);

  let folderName: string;
  try {
    const response = await client.request<{ name: string; mimeType: string }>(
      readOnly({
        url: `${DRIVE_FILES_URL}/${folderId}`,
        params: { fields: 'name, mimeType', supportsAllDrives: true },
      }),
    );
    folderName = response.data.name;
  } catch (error) {
    const status = (error as { response?: { status?: number } }).response?.status;

    if (status === 404) {
      throw new Error(
        `Drive folder ${folderId} is not visible to ${identity}. Open the folder in Drive as that ` +
          `user, or share it as Viewer. Drive reports an inaccessible folder as "not found".`,
      );
    }
    if (status === 403) {
      throw new Error(
        `Drive refused the request for folder ${folderId} as ${identity}. Enable the Google ` +
          `Drive API on project dopa-x-app, then retry.`,
      );
    }
    throw error;
  }

  const page = await requestPage(
    client,
    {
      q: `'${folderId}' in parents and trashed = false`,
      fields: 'files(name)',
      pageSize: 5,
      supportsAllDrives: true,
      includeItemsFromAllDrives: true,
    },
    options.sleep ?? wait,
  );

  return { identity, folderName, sampleNames: (page.files ?? []).map((file) => file.name) };
}

/**
 * Breadth-first so the traversal order is deterministic and a subfolder cannot
 * recurse the process into a stack overflow. The corpus is documented as one
 * flat folder, but an un-inventoried folder is exactly the place where an
 * assumption like that turns out to be wrong.
 */
export async function listFolder(
  folderId: string,
  options: ListFolderOptions = {},
): Promise<DriveObject[]> {
  const { client } = await connect(options);
  const sleep = options.sleep ?? wait;

  const objects: DriveObject[] = [];
  const queue: { id: string; path: string }[] = [{ id: folderId, path: '' }];
  const visited = new Set<string>([folderId]);

  while (queue.length > 0) {
    const folder = queue.shift()!;
    let pageToken: string | undefined;

    do {
      const page = await requestPage(
        client,
        {
          q: `'${folder.id}' in parents and trashed = false`,
          fields:
            'nextPageToken, files(id, name, size, md5Checksum, mimeType, createdTime, modifiedTime)',
          pageSize: PAGE_SIZE,
          orderBy: 'createdTime',
          // Without these two a folder that lives on a shared drive returns an
          // empty list rather than an error, which would look like an empty
          // corpus instead of a misconfiguration.
          supportsAllDrives: true,
          includeItemsFromAllDrives: true,
          ...(pageToken ? { pageToken } : {}),
        },
        sleep,
      );

      for (const file of page.files ?? []) {
        if (file.mimeType === FOLDER_MIME) {
          if (!visited.has(file.id)) {
            visited.add(file.id);
            queue.push({
              id: file.id,
              path: folder.path ? `${folder.path}/${file.name}` : file.name,
            });
          }
          continue;
        }

        objects.push({
          fileId: file.id,
          name: file.name,
          bytes: file.size === undefined ? null : Number(file.size),
          md5: file.md5Checksum ?? null,
          mimeType: file.mimeType,
          createdTime: file.createdTime ?? null,
          modifiedTime: file.modifiedTime ?? null,
          parentPath: folder.path,
        });
      }

      pageToken = page.nextPageToken;
      options.onPage?.({ objects: objects.length, folder: folder.path || '/' });
    } while (pageToken);
  }

  return objects;
}
