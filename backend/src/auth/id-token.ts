import { getAuth } from 'firebase-admin/auth';
import { firebaseApp } from './firebase-app.js';

/**
 * R1 — Firebase stays the identity provider and this backend only *verifies*.
 * Behind a port because the laptop has no Firebase credential today (org policy
 * blocks service account key creation, see .env.example), so the admin console
 * has to be buildable and testable without one.
 */

export interface VerifiedIdentity {
  uid: string;
  email?: string | undefined;
  emailVerified: boolean;
  provider?: string | undefined;
}

export interface IdTokenVerifier {
  readonly kind: 'firebase' | 'dev';
  verify(idToken: string): Promise<VerifiedIdentity>;
}

export class IdTokenInvalid extends Error {
  constructor(reason: string) {
    super(`id token rejected: ${reason}`);
    this.name = 'IdTokenInvalid';
  }
}

export function createFirebaseVerifier(options: {
  projectId: string;
  credentialsPath?: string | undefined;
}): IdTokenVerifier {
  return {
    kind: 'firebase',
    async verify(idToken) {
      try {
        const decoded = await getAuth(firebaseApp(options.projectId, options.credentialsPath))
          .verifyIdToken(idToken, true);

        return {
          uid: decoded.uid,
          email: decoded.email,
          emailVerified: decoded.email_verified === true,
          provider: decoded.firebase?.sign_in_provider,
        };
      } catch (error) {
        throw new IdTokenInvalid(error instanceof Error ? error.message : 'unverifiable');
      }
    },
  };
}

const DEV_PREFIX = 'dev:';

/**
 * Development only, gated by ADMIN_DEV_LOGIN which itself requires
 * NODE_ENV=development and AUTH_DEV_BYPASS=true. Accepts `dev:<email>` and
 * trusts it, so the console can be developed against the local database with no
 * Firebase credential present. It still has to match an active `staff_users`
 * row, so this bypasses proof of identity, not authorisation.
 */
export function createDevVerifier(): IdTokenVerifier {
  return {
    kind: 'dev',
    async verify(idToken) {
      if (!idToken.startsWith(DEV_PREFIX)) {
        throw new IdTokenInvalid('dev verifier expects a "dev:<email>" token');
      }

      const email = idToken.slice(DEV_PREFIX.length).trim().toLowerCase();
      if (!email.includes('@')) throw new IdTokenInvalid('dev token carries no email');

      return { uid: `dev-${email}`, email, emailVerified: true, provider: 'dev' };
    },
  };
}
