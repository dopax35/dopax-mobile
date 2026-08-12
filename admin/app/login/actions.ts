'use server';

import { redirect } from 'next/navigation';
import { requestStaffSession } from '@/lib/api';
import { clearSession, setSession } from '@/lib/session';

export interface SignInState {
  error?: string;
}

async function establish(idToken: string): Promise<SignInState> {
  const result = await requestStaffSession(idToken);

  if (!result.ok) return { error: result.error };

  await setSession({
    token: result.session.token,
    expiresAt: result.session.expiresAt,
    staff: result.session.staff,
  });

  return {};
}

/**
 * Development sign-in. The backend refuses it unless NODE_ENV=development,
 * AUTH_DEV_BYPASS=true and ADMIN_DEV_LOGIN=true, and the email must still be an
 * active staff_users row — so this skips proving who you are, never whether you
 * are allowed.
 */
export async function signInWithEmail(
  _previous: SignInState,
  formData: FormData,
): Promise<SignInState> {
  const email = String(formData.get('email') ?? '').trim();

  if (!email.includes('@')) return { error: 'Enter the staff email address.' };

  const state = await establish(`dev:${email}`);
  if (state.error) return state;

  redirect('/');
}

/** Called by the Firebase client component with a real Firebase ID token. */
export async function signInWithFirebaseToken(idToken: string): Promise<SignInState> {
  const state = await establish(idToken);
  if (state.error) return state;

  redirect('/');
}

export async function signOut(): Promise<void> {
  await clearSession();
  redirect('/login');
}
