/**
 * Authenticate as a human Google user for read-only Drive access.
 *
 *   npm run drive:login
 *
 * Requires an OAuth Desktop client JSON at secrets/oauth-desktop-client.json
 * (see the console steps printed when the file is missing). Does not create or
 * require a service account key — this is the org-policy-safe path.
 */
import 'dotenv/config';
import { loginUserForDrive, defaultOauthClientPath, defaultUserTokenPath } from '../src/infra/drive/user-oauth.js';

async function main(): Promise<number> {
  console.log(`[drive:login] oauth client  ${defaultOauthClientPath()}`);
  console.log(`[drive:login] token file    ${defaultUserTokenPath()}`);
  console.log('[drive:login] scope         drive.readonly (no write, no delete)');

  const { tokenPath, scopes } = await loginUserForDrive({
    onAuthUrl: (url) => {
      console.log(`[drive:login] open this URL if the browser does not:\n${url}\n`);
    },
  });

  console.log(`[drive:login] saved refresh token → ${tokenPath}`);
  console.log(`[drive:login] scopes granted: ${scopes.join(', ')}`);
  console.log('[drive:login] next: npm run drive:inventory -- --check');
  return 0;
}

let exitCode = 1;
try {
  exitCode = await main();
} catch (error) {
  console.error('[drive:login] failed:', error instanceof Error ? error.message : error);
}

process.exit(exitCode);
