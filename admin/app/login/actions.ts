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

/** Authenticates using username: dopax and password: dopax35 */
export async function signInWithCredentials(
  _previous: SignInState,
  formData: FormData,
): Promise<SignInState> {
  const username = String(formData.get('username') ?? '').trim();
  const password = String(formData.get('password') ?? '').trim();

  if (username === 'dopax' && password === 'dopax35') {
    const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();
    await setSession({
      token: 'static-dopax-token',
      expiresAt,
      staff: {
        id: 'dopax-staff-id',
        email: 'dopax@dopa-x.org',
        displayName: 'DopaX Admin',
        role: 'admin',
      },
    });
    redirect('/progress');
  }

  // Fallback: try email dev signin if email provided
  if (username.includes('@')) {
    const state = await establish(`dev:${username}`);
    if (!state.error) {
      redirect('/progress');
    }
  }

  return { error: 'Invalid username or password. Username is dopax and password is dopax35.' };
}

export async function signInWithEmail(
  _previous: SignInState,
  formData: FormData,
): Promise<SignInState> {
  const email = String(formData.get('email') ?? '').trim();

  if (!email.includes('@')) return { error: 'Enter the staff email address.' };

  const state = await establish(`dev:${email}`);
  if (state.error) return state;

  redirect('/progress');
}

export async function signInWithFirebaseToken(idToken: string): Promise<SignInState> {
  const state = await establish(idToken);
  if (state.error) return state;

  redirect('/progress');
}

export async function signOut(): Promise<void> {
  await clearSession();
  redirect('/login');
}
