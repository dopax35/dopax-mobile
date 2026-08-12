import 'server-only';
import { redirect } from 'next/navigation';
import { getSession } from './session';

const BACKEND_URL = process.env.BACKEND_URL ?? 'http://localhost:8080';

export class BackendUnreachable extends Error {
  constructor(cause: unknown) {
    super(`the backend at ${BACKEND_URL} did not respond`);
    this.name = 'BackendUnreachable';
    this.cause = cause;
  }
}

export class Forbidden extends Error {
  constructor(readonly requiredRole?: string) {
    super(
      requiredRole
        ? `this view needs the ${requiredRole} role`
        : 'your role does not allow this view',
    );
    this.name = 'Forbidden';
  }
}

export class AuditUnavailable extends Error {
  constructor() {
    super(
      'the backend refused to serve this read because it could not record an audit entry',
    );
    this.name = 'AuditUnavailable';
  }
}

export interface AdminFetchOptions {
  method?: 'GET' | 'POST' | 'PATCH';
  body?: unknown;
  /** Query parameters; undefined values are dropped rather than sent empty. */
  query?: Record<string, string | number | boolean | undefined>;
}

function url(path: string, query?: AdminFetchOptions['query']): string {
  const target = new URL(`/v1/admin${path}`, BACKEND_URL);

  for (const [key, value] of Object.entries(query ?? {})) {
    if (value !== undefined && value !== '') target.searchParams.set(key, String(value));
  }

  return target.toString();
}

/**
 * Every backend call goes through here, authenticated with the session cookie's
 * token. A 401 means the session died mid-visit, which is a redirect rather than
 * an error page: the reader has nothing to fix.
 */
export async function adminFetch<T>(path: string, options: AdminFetchOptions = {}): Promise<T> {
  const session = await getSession();
  if (!session) redirect('/login');

  let response: Response;

  try {
    response = await fetch(url(path, options.query), {
      method: options.method ?? 'GET',
      headers: {
        authorization: `Bearer ${session.token}`,
        ...(options.body ? { 'content-type': 'application/json' } : {}),
      },
      ...(options.body ? { body: JSON.stringify(options.body) } : {}),
      cache: 'no-store',
    });
  } catch (error) {
    throw new BackendUnreachable(error);
  }

  if (response.status === 401) redirect('/login?expired=1');

  if (response.status === 403) {
    const detail = (await response.json().catch(() => ({}))) as { requiredRole?: string };
    throw new Forbidden(detail.requiredRole);
  }

  if (response.status === 503) {
    const detail = (await response.json().catch(() => ({}))) as { error?: string };
    if (detail.error === 'audit_unavailable') throw new AuditUnavailable();
  }

  if (!response.ok) {
    const body = await response.text().catch(() => '');
    throw new Error(`GET ${path} failed with ${response.status}${body ? `: ${body}` : ''}`);
  }

  return (await response.json()) as T;
}

/** Sign-in, the one call made without a session. */
export async function requestStaffSession(idToken: string): Promise<{
  ok: true;
  session: { token: string; expiresAt: string; staff: SessionStaff };
} | { ok: false; error: string }> {
  let response: Response;

  try {
    response = await fetch(new URL('/v1/admin/auth/session', BACKEND_URL).toString(), {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ idToken }),
      cache: 'no-store',
    });
  } catch {
    return { ok: false, error: `The backend at ${BACKEND_URL} is not reachable.` };
  }

  if (response.status === 403) {
    return {
      ok: false,
      error:
        'That account is not on the staff list. An operator has to grant access with `npm run staff:add` in the backend.',
    };
  }

  if (response.status === 401) {
    return { ok: false, error: 'Those credentials were not accepted.' };
  }

  if (response.status === 429) {
    return { ok: false, error: 'Too many sign-in attempts. Wait a minute and try again.' };
  }

  if (!response.ok) {
    return { ok: false, error: `Sign-in failed with status ${response.status}.` };
  }

  const body = (await response.json()) as {
    token: string;
    expiresAt: string;
    staff: SessionStaff;
  };

  return { ok: true, session: body };
}

export interface SessionStaff {
  id: string;
  email: string;
  displayName: string | null;
  role: 'viewer' | 'researcher' | 'admin';
}

export async function fetchAuthMethods(): Promise<{ firebase: boolean; devLogin: boolean }> {
  try {
    const response = await fetch(new URL('/v1/admin/auth/methods', BACKEND_URL).toString(), {
      cache: 'no-store',
    });

    if (!response.ok) return { firebase: true, devLogin: false };
    return (await response.json()) as { firebase: boolean; devLogin: boolean };
  } catch {
    // Sign-in should still render if the backend is down, with the failure
    // reported when the form is submitted rather than as a blank page.
    return { firebase: true, devLogin: false };
  }
}
