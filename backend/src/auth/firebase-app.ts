import { cert, getApps, initializeApp, type App } from 'firebase-admin/app';
import { readFileSync } from 'node:fs';

let app: App | undefined;

/**
 * One firebase-admin App for the whole process. Both the ID token verifier and
 * the custom token minter reach for it, and initialising twice throws.
 *
 * Verification needs only the project id plus Google's public signing
 * certificates, so an app with no credential is enough for that path and is the
 * only thing available on the dev laptop. Minting a custom token additionally
 * requires a real service account key — see createFirebaseMinter.
 */
export function firebaseApp(projectId: string, credentialsPath?: string): App {
  if (app) return app;

  const [existing] = getApps();
  if (existing) {
    app = existing;
    return app;
  }

  if (credentialsPath) {
    const serviceAccount = JSON.parse(readFileSync(credentialsPath, 'utf8'));
    app = initializeApp({ projectId, credential: cert(serviceAccount) });
  } else {
    app = initializeApp({ projectId });
  }

  return app;
}
