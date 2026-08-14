import { getAuth } from 'firebase-admin/auth';
import { firebaseApp } from './firebase-app.js';

/**
 * R1 — Firebase stays the identity provider. The email code flow does not
 * authenticate anyone here: it proves the participant controls the address,
 * then hands back a Firebase custom token so the client completes sign-in
 * through the Firebase SDK exactly as the Google and Apple buttons do.
 *
 * Behind a port because minting (unlike verifying) needs a real service account
 * credential, which org policy blocks on the dev laptop.
 */

export interface CustomTokenMinter {
  readonly kind: 'firebase' | 'dev';
  /** Resolves the Firebase account for `email`, creating it if new. */
  mintForEmail(email: string): Promise<{ uid: string; token: string }>;
}

export class CustomTokenUnavailable extends Error {
  constructor(reason: string) {
    super(`custom token could not be minted: ${reason}`);
    this.name = 'CustomTokenUnavailable';
  }
}

export function createFirebaseMinter(options: {
  projectId: string;
  credentialsPath?: string | undefined;
}): CustomTokenMinter {
  return {
    kind: 'firebase',
    async mintForEmail(email) {
      const auth = getAuth(firebaseApp(options.projectId, options.credentialsPath));

      try {
        // Reuse the existing account whenever the address is already known, so
        // a participant who enrolled with Google and later uses an email code
        // lands on the same uid instead of a duplicate identity.
        let uid: string;
        try {
          uid = (await auth.getUserByEmail(email)).uid;
        } catch (lookupError) {
          if ((lookupError as { code?: string }).code !== 'auth/user-not-found') throw lookupError;
          uid = (await auth.createUser({ email, emailVerified: true })).uid;
        }

        return { uid, token: await auth.createCustomToken(uid) };
      } catch (error) {
        throw new CustomTokenUnavailable(error instanceof Error ? error.message : 'unknown');
      }
    },
  };
}

/**
 * Development only, gated by AUTH_DEV_BYPASS. Returns a token the dev verifier
 * accepts, so the whole email flow runs against the local database with no
 * Firebase credential present.
 */
export function createDevMinter(): CustomTokenMinter {
  return {
    kind: 'dev',
    async mintForEmail(email) {
      return { uid: `dev-${email}`, token: `dev:${email}` };
    },
  };
}
