import { createHash, randomInt, timingSafeEqual } from 'node:crypto';
import { and, desc, eq, gt, isNull, sql } from 'drizzle-orm';
import { z } from 'zod';
import type { Database } from '../../db/client.js';
import { emailOtpCodes } from '../../db/schema/identity.js';

/**
 * Email sign-in codes for Figma frames 6377:2 (request) and 6377:21 (verify).
 *
 * R1 — this proves control of an address, nothing more. The caller turns a
 * successful verification into a Firebase custom token, so Firebase remains the
 * identity provider and no existing credential is read, rewritten or replaced.
 */

export const CODE_LENGTH = 6;
export const CODE_TTL_SECONDS = 600;
/** Matches the "Resend code (in 0:24)" countdown on frame 6377:21. */
export const RESEND_COOLDOWN_SECONDS = 30;
export const MAX_ATTEMPTS = 5;
/** Per address per hour, independent of the per-IP limiter on the route. */
export const MAX_SENDS_PER_HOUR = 5;

export const emailStartSchema = z.object({
  email: z.string().email().max(320),
});

export const emailVerifySchema = z.object({
  email: z.string().email().max(320),
  code: z.string().regex(/^\d{6}$/, 'code must be 6 digits'),
});

export type EmailStartInput = z.infer<typeof emailStartSchema>;
export type EmailVerifyInput = z.infer<typeof emailVerifySchema>;

export class EmailOtpRateLimited extends Error {
  constructor(public readonly retryAfterSeconds: number) {
    super('too many codes requested for this address');
    this.name = 'EmailOtpRateLimited';
  }
}

export type VerifyFailure =
  | { ok: false; reason: 'no_active_code' }
  | { ok: false; reason: 'expired' }
  | { ok: false; reason: 'too_many_attempts' }
  | { ok: false; reason: 'mismatch'; attemptsRemaining: number };

export type VerifyResult = { ok: true; email: string } | VerifyFailure;

/** Addresses are case-insensitive; store and compare one canonical form. */
export function normaliseEmail(email: string): string {
  return email.trim().toLowerCase();
}

function hashCode(email: string, code: string): string {
  // Salted with the address so an attacker cannot precompute one rainbow table
  // covering all one million six-digit codes and reuse it across every row.
  return createHash('sha256').update(`${email}:${code}`).digest('hex');
}

function generateCode(): string {
  return randomInt(0, 10 ** CODE_LENGTH)
    .toString()
    .padStart(CODE_LENGTH, '0');
}

function constantTimeEquals(a: string, b: string): boolean {
  const left = Buffer.from(a);
  const right = Buffer.from(b);
  if (left.length !== right.length) return false;
  return timingSafeEqual(left, right);
}

export interface IssuedCode {
  email: string;
  code: string;
  expiresAt: Date;
  resendAvailableAt: Date;
}

/**
 * Issues a code and returns the plaintext for the caller to email. Only the
 * hash is persisted, so this return value is the single moment the code exists
 * in the clear on the server.
 */
export async function issueEmailCode(
  database: Database,
  input: EmailStartInput,
  options: { now?: Date; requestIp?: string | undefined } = {},
): Promise<IssuedCode> {
  const email = normaliseEmail(input.email);
  const now = options.now ?? new Date();

  const recent = await database
    .select({ createdAt: emailOtpCodes.createdAt })
    .from(emailOtpCodes)
    .where(
      and(
        eq(emailOtpCodes.email, email),
        gt(emailOtpCodes.createdAt, new Date(now.getTime() - 3_600_000)),
      ),
    )
    .orderBy(desc(emailOtpCodes.createdAt));

  if (recent.length >= MAX_SENDS_PER_HOUR) {
    const oldest = recent[recent.length - 1]!.createdAt;
    const retryAfter = Math.ceil((oldest.getTime() + 3_600_000 - now.getTime()) / 1000);
    throw new EmailOtpRateLimited(Math.max(retryAfter, 1));
  }

  const newest = recent[0]?.createdAt;
  if (newest) {
    const elapsed = (now.getTime() - newest.getTime()) / 1000;
    if (elapsed < RESEND_COOLDOWN_SECONDS) {
      throw new EmailOtpRateLimited(Math.ceil(RESEND_COOLDOWN_SECONDS - elapsed));
    }
  }

  // Supersede anything still outstanding. Two live codes for one address means
  // an old code stays usable after the participant asked for a new one.
  await database
    .update(emailOtpCodes)
    .set({ consumedAt: now })
    .where(and(eq(emailOtpCodes.email, email), isNull(emailOtpCodes.consumedAt)));

  const code = generateCode();
  const expiresAt = new Date(now.getTime() + CODE_TTL_SECONDS * 1000);

  await database.insert(emailOtpCodes).values({
    email,
    codeHash: hashCode(email, code),
    expiresAt,
    requestIp: options.requestIp,
    createdAt: now,
  });

  return {
    email,
    code,
    expiresAt,
    resendAvailableAt: new Date(now.getTime() + RESEND_COOLDOWN_SECONDS * 1000),
  };
}

/**
 * Checks a submitted code and consumes it on success. A code is single-use: the
 * row is marked consumed in the same statement that claims it, so two parallel
 * requests carrying the same code cannot both succeed.
 */
export async function verifyEmailCode(
  database: Database,
  input: EmailVerifyInput,
  options: { now?: Date } = {},
): Promise<VerifyResult> {
  const email = normaliseEmail(input.email);
  const now = options.now ?? new Date();

  const [row] = await database
    .select()
    .from(emailOtpCodes)
    .where(and(eq(emailOtpCodes.email, email), isNull(emailOtpCodes.consumedAt)))
    .orderBy(desc(emailOtpCodes.createdAt))
    .limit(1);

  if (!row) return { ok: false, reason: 'no_active_code' };

  if (row.expiresAt.getTime() <= now.getTime()) {
    await database
      .update(emailOtpCodes)
      .set({ consumedAt: now })
      .where(eq(emailOtpCodes.id, row.id));
    return { ok: false, reason: 'expired' };
  }

  if (row.attempts >= MAX_ATTEMPTS) {
    await database
      .update(emailOtpCodes)
      .set({ consumedAt: now })
      .where(eq(emailOtpCodes.id, row.id));
    return { ok: false, reason: 'too_many_attempts' };
  }

  if (!constantTimeEquals(row.codeHash, hashCode(email, input.code))) {
    const [updated] = await database
      .update(emailOtpCodes)
      .set({ attempts: sql`${emailOtpCodes.attempts} + 1` })
      .where(eq(emailOtpCodes.id, row.id))
      .returning({ attempts: emailOtpCodes.attempts });

    const used = updated?.attempts ?? row.attempts + 1;
    return { ok: false, reason: 'mismatch', attemptsRemaining: Math.max(MAX_ATTEMPTS - used, 0) };
  }

  const claimed = await database
    .update(emailOtpCodes)
    .set({ consumedAt: now })
    .where(and(eq(emailOtpCodes.id, row.id), isNull(emailOtpCodes.consumedAt)))
    .returning({ id: emailOtpCodes.id });

  if (claimed.length === 0) return { ok: false, reason: 'no_active_code' };

  return { ok: true, email };
}

/** Housekeeping for the bootstrap/maintenance path; safe to run at any time. */
export async function purgeExpiredCodes(
  database: Database,
  options: { now?: Date } = {},
): Promise<void> {
  const cutoff = new Date((options.now ?? new Date()).getTime() - 86_400_000);
  await database.delete(emailOtpCodes).where(gt(sql`${cutoff}`, emailOtpCodes.expiresAt));
}
