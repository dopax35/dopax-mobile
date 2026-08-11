/**
 * User OAuth for local Drive access — Google's recommended alternative when a
 * service account key is unavailable or blocked by org policy.
 *
 * See: https://cloud.google.com/blog/products/identity-security/how-to-authenticate-service-accounts-to-help-keep-applications-secure
 *
 * The human operator already has access to the folder; we ask their consent for
 * `drive.readonly` only, store a refresh token under secrets/, and never create
 * a service account key.
 */
import { createServer } from 'node:http';
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname } from 'node:path';
import { OAuth2Client, type Credentials } from 'google-auth-library';
import { execFile } from 'node:child_process';

export const DRIVE_READONLY_SCOPE = 'https://www.googleapis.com/auth/drive.readonly';

const DEFAULT_OAUTH_CLIENT = './secrets/oauth-desktop-client.json';
const DEFAULT_USER_TOKEN = './secrets/drive-user-token.json';

interface InstalledClient {
  client_id: string;
  client_secret: string;
  redirect_uris?: string[];
}

interface OAuthClientFile {
  installed?: InstalledClient;
  web?: InstalledClient;
}

export interface StoredUserToken {
  tokens: Credentials;
  obtainedAt: string;
  scopes: string[];
}

export function defaultOauthClientPath(): string {
  return process.env.DRIVE_OAUTH_CLIENT_PATH ?? DEFAULT_OAUTH_CLIENT;
}

export function defaultUserTokenPath(): string {
  return process.env.DRIVE_USER_TOKEN_PATH ?? DEFAULT_USER_TOKEN;
}

export function loadOauthClientConfig(path = defaultOauthClientPath()): InstalledClient {
  let raw: string;
  try {
    raw = readFileSync(path, 'utf8');
  } catch (error) {
    throw new Error(
      `cannot read the OAuth Desktop client at ${path}. Create one in Cloud Console → ` +
        `APIs & Services → Credentials → Create credentials → OAuth client ID → Desktop app, ` +
        `download the JSON, and save it there. ` +
        `(${error instanceof Error ? error.message : String(error)})`,
    );
  }

  const parsed = JSON.parse(raw) as OAuthClientFile;
  const client = parsed.installed ?? parsed.web;
  if (!client?.client_id || !client.client_secret) {
    throw new Error(
      `${path} is not a Google OAuth client JSON (expected an "installed" or "web" block with ` +
        `client_id and client_secret). Re-download it from the Credentials page.`,
    );
  }

  return client;
}

export function loadStoredUserToken(path = defaultUserTokenPath()): StoredUserToken {
  try {
    return JSON.parse(readFileSync(path, 'utf8')) as StoredUserToken;
  } catch (error) {
    throw new Error(
      `cannot read the Drive user token at ${path}. Run \`npm run drive:login\` first. ` +
        `(${error instanceof Error ? error.message : String(error)})`,
    );
  }
}

export function userTokenExists(path = defaultUserTokenPath()): boolean {
  return existsSync(path);
}

export function createUserOAuthClient(
  clientConfig: InstalledClient = loadOauthClientConfig(),
  redirectUri = 'http://127.0.0.1',
): OAuth2Client {
  return new OAuth2Client(clientConfig.client_id, clientConfig.client_secret, redirectUri);
}

export function authedUserOAuthClient(options?: {
  oauthClientPath?: string;
  userTokenPath?: string;
}): OAuth2Client {
  const clientConfig = loadOauthClientConfig(options?.oauthClientPath ?? defaultOauthClientPath());
  const stored = loadStoredUserToken(options?.userTokenPath ?? defaultUserTokenPath());
  const client = createUserOAuthClient(clientConfig);
  client.setCredentials(stored.tokens);
  return client;
}

function openBrowser(url: string): void {
  const cmd = process.platform === 'darwin' ? 'open' : process.platform === 'win32' ? 'start' : 'xdg-open';
  execFile(cmd, [url], () => {
    // The console still prints the URL if the browser fails to open.
  });
}

/**
 * Loopback OAuth for a Desktop client. Listens on 127.0.0.1, opens the browser,
 * exchanges the code, and persists the refresh token under secrets/.
 */
export async function loginUserForDrive(options?: {
  oauthClientPath?: string;
  userTokenPath?: string;
  open?: (url: string) => void;
  /** Called with the consent URL so the CLI can print it. */
  onAuthUrl?: (url: string) => void;
}): Promise<{ tokenPath: string; scopes: string[] }> {
  const clientPath = options?.oauthClientPath ?? defaultOauthClientPath();
  const tokenPath = options?.userTokenPath ?? defaultUserTokenPath();
  const clientConfig = loadOauthClientConfig(clientPath);

  const { code, redirectUri } = await captureAuthCode((redirectUri) => {
    const bootstrap = createUserOAuthClient(clientConfig, redirectUri);
    const authUrl = bootstrap.generateAuthUrl({
      access_type: 'offline',
      prompt: 'consent',
      scope: [DRIVE_READONLY_SCOPE],
    });
    options?.onAuthUrl?.(authUrl);
    (options?.open ?? openBrowser)(authUrl);
  });

  const client = createUserOAuthClient(clientConfig, redirectUri);
  const { tokens } = await client.getToken(code);

  if (!tokens.refresh_token) {
    throw new Error(
      'Google did not return a refresh_token. Revoke the app under ' +
        'https://myaccount.google.com/permissions and run `npm run drive:login` again with prompt=consent.',
    );
  }

  const stored: StoredUserToken = {
    tokens,
    obtainedAt: new Date().toISOString(),
    scopes: [DRIVE_READONLY_SCOPE],
  };

  mkdirSync(dirname(tokenPath), { recursive: true });
  writeFileSync(tokenPath, `${JSON.stringify(stored, null, 2)}\n`, { mode: 0o600 });

  return { tokenPath, scopes: stored.scopes };
}

async function captureAuthCode(
  onReady: (redirectUri: string) => void | Promise<void>,
): Promise<{ code: string; redirectUri: string }> {
  return new Promise((resolve, reject) => {
    let redirectUri = '';

    const server = createServer((req, res) => {
      const url = new URL(req.url ?? '/', 'http://127.0.0.1');
      if (url.pathname !== '/oauth2callback') {
        res.writeHead(404).end();
        return;
      }

      const error = url.searchParams.get('error');
      const code = url.searchParams.get('code');

      if (error || !code) {
        res.writeHead(400, { 'Content-Type': 'text/html' }).end(
          `<html><body><h1>Login failed</h1><p>${error ?? 'missing code'}</p></body></html>`,
        );
        server.close();
        reject(new Error(error ?? 'OAuth callback missing code'));
        return;
      }

      res
        .writeHead(200, { 'Content-Type': 'text/html' })
        .end(
          '<html><body><h1>Drive login OK</h1><p>You can close this tab and return to the terminal.</p></body></html>',
        );
      server.close();
      resolve({ code, redirectUri });
    });

    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      if (!address || typeof address === 'string') {
        reject(new Error('could not bind a loopback port for the OAuth callback'));
        return;
      }

      redirectUri = `http://127.0.0.1:${address.port}/oauth2callback`;
      Promise.resolve(onReady(redirectUri)).catch(reject);
    });

    server.on('error', reject);
  });
}
