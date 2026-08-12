import 'server-only';
import { cookies } from 'next/headers';

/**
 * The staff token lives in an httpOnly cookie that only this app's server can
 * read, and every backend call is made server-side. No page ever ships the token
 * to the browser, so a cross-site script on this origin has nothing to steal and
 * no way to call /v1/admin itself.
 */

const COOKIE_NAME = 'dopax_admin_session';

export type StaffRole = 'viewer' | 'researcher' | 'admin';

export interface StaffSession {
  token: string;
  expiresAt: string;
  staff: {
    id: string;
    email: string;
    displayName: string | null;
    role: StaffRole;
  };
}

export async function getSession(): Promise<StaffSession | null> {
  const cookie = (await cookies()).get(COOKIE_NAME);
  if (!cookie) return null;

  let session: StaffSession;
  try {
    session = JSON.parse(cookie.value) as StaffSession;
  } catch {
    return null;
  }

  // Checked here as well as by the backend, so an expired session shows the login
  // page instead of a wall of failed panels.
  if (new Date(session.expiresAt).getTime() <= Date.now()) return null;

  return session;
}

export async function setSession(session: StaffSession): Promise<void> {
  const store = await cookies();

  store.set(COOKIE_NAME, JSON.stringify(session), {
    httpOnly: true,
    sameSite: 'strict',
    secure: process.env.NODE_ENV === 'production',
    path: '/',
    expires: new Date(session.expiresAt),
  });
}

export async function clearSession(): Promise<void> {
  (await cookies()).delete(COOKIE_NAME);
}

export function roleRank(role: StaffRole): number {
  return { viewer: 1, researcher: 2, admin: 3 }[role];
}

export function hasRole(session: StaffSession, required: StaffRole): boolean {
  return roleRank(session.staff.role) >= roleRank(required);
}
