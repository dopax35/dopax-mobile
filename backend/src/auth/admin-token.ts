import { jwtVerify, SignJWT } from 'jose';

/**
 * Staff session tokens for /v1/admin.
 *
 * Deliberately a different audience *and* a different signing secret from the
 * participant tokens in §4.1. Two separate populations authenticate against this
 * backend, and the failure to avoid is a participant token being accepted as a
 * staff token — which would hand one participant read access to all 43. An
 * audience check alone would still allow it the moment both are signed with the
 * same secret, so both halves are enforced: `ADMIN_JWT_SECRET !== JWT_SECRET` is
 * a boot-time environment rule, and `aud` is checked on every request.
 */

export const ADMIN_TOKEN_AUDIENCE = 'dopax-admin';
export const ADMIN_TOKEN_ISSUER = 'dopax-backend';

export const STAFF_ROLES = ['viewer', 'researcher', 'admin'] as const;
export type StaffRole = (typeof STAFF_ROLES)[number];

export function isStaffRole(value: string): value is StaffRole {
  return (STAFF_ROLES as readonly string[]).includes(value);
}

export interface AdminTokenClaims {
  staffId: string;
  email: string;
  role: StaffRole;
  displayName?: string | undefined;
}

export interface SignedAdminToken {
  token: string;
  expiresAt: Date;
  issuedAt: Date;
}

function key(secret: string): Uint8Array {
  return new TextEncoder().encode(secret);
}

export async function signAdminToken(
  claims: AdminTokenClaims,
  options: { secret: string; ttlSeconds: number; now?: Date | undefined },
): Promise<SignedAdminToken> {
  const issuedAt = options.now ?? new Date();
  const expiresAt = new Date(issuedAt.getTime() + options.ttlSeconds * 1000);

  const token = await new SignJWT({
    email: claims.email,
    role: claims.role,
    name: claims.displayName,
  })
    .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
    .setSubject(claims.staffId)
    .setAudience(ADMIN_TOKEN_AUDIENCE)
    .setIssuer(ADMIN_TOKEN_ISSUER)
    .setIssuedAt(Math.floor(issuedAt.getTime() / 1000))
    .setExpirationTime(Math.floor(expiresAt.getTime() / 1000))
    .sign(key(options.secret));

  return { token, expiresAt, issuedAt };
}

export class AdminTokenInvalid extends Error {
  constructor(reason: string) {
    super(`admin token rejected: ${reason}`);
    this.name = 'AdminTokenInvalid';
  }
}

export async function verifyAdminToken(
  token: string,
  options: { secret: string; now?: Date | undefined },
): Promise<AdminTokenClaims> {
  let payload;

  try {
    ({ payload } = await jwtVerify(token, key(options.secret), {
      audience: ADMIN_TOKEN_AUDIENCE,
      issuer: ADMIN_TOKEN_ISSUER,
      // Pinned: without it, a token could nominate its own algorithm.
      algorithms: ['HS256'],
      clockTolerance: 5,
      ...(options.now ? { currentDate: options.now } : {}),
    }));
  } catch (error) {
    throw new AdminTokenInvalid(error instanceof Error ? error.message : 'unverifiable');
  }

  const { sub, email, role, name } = payload as {
    sub?: string;
    email?: unknown;
    role?: unknown;
    name?: unknown;
  };

  if (!sub) throw new AdminTokenInvalid('no subject');
  if (typeof email !== 'string' || email.length === 0) throw new AdminTokenInvalid('no email');
  if (typeof role !== 'string' || !isStaffRole(role)) throw new AdminTokenInvalid('unknown role');

  return {
    staffId: sub,
    email,
    role,
    ...(typeof name === 'string' ? { displayName: name } : {}),
  };
}
