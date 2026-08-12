import { and, eq, sql } from 'drizzle-orm';
import type { Database } from '../db/client.js';
import { staffUsers } from '../db/schema/compliance.js';
import { isStaffRole, type StaffRole } from './admin-token.js';

/**
 * Staff authorisation is an allowlist, never a claim on a token. Anyone in the
 * Firebase project can obtain a valid ID token — all 43 participants can — so
 * possessing one grants nothing here. A session exists only if the verified
 * email is an active row in `staff_users`.
 */

export interface StaffAccount {
  id: string;
  email: string;
  displayName: string | null;
  role: StaffRole;
}

export function normaliseEmail(email: string): string {
  return email.trim().toLowerCase();
}

export async function findActiveStaffByEmail(
  database: Database,
  email: string,
): Promise<StaffAccount | undefined> {
  const [row] = await database
    .select({
      id: staffUsers.id,
      email: staffUsers.email,
      displayName: staffUsers.displayName,
      role: staffUsers.role,
    })
    .from(staffUsers)
    .where(and(eq(staffUsers.email, normaliseEmail(email)), eq(staffUsers.active, true)));

  if (!row) return undefined;

  // An unrecognised role must not silently widen into a working session. Fail
  // closed by refusing the login, which surfaces the bad row.
  if (!isStaffRole(row.role)) return undefined;

  return { ...row, role: row.role };
}

export async function touchStaffLastSeen(database: Database, staffId: string): Promise<void> {
  await database
    .update(staffUsers)
    .set({ lastSeenAt: new Date() })
    .where(eq(staffUsers.id, staffId));
}

export interface UpsertStaffInput {
  email: string;
  role: StaffRole;
  displayName?: string | undefined;
  active?: boolean | undefined;
}

/** Idempotent, so the staff:add script can be re-run to change a role. */
export async function upsertStaff(
  database: Database,
  input: UpsertStaffInput,
): Promise<StaffAccount & { created: boolean }> {
  const email = normaliseEmail(input.email);

  const [row] = await database
    .insert(staffUsers)
    .values({
      email,
      role: input.role,
      displayName: input.displayName,
      active: input.active ?? true,
    })
    .onConflictDoUpdate({
      target: staffUsers.email,
      set: {
        role: input.role,
        active: input.active ?? true,
        displayName: sql`coalesce(${input.displayName ?? null}, ${staffUsers.displayName})`,
      },
    })
    .returning({
      id: staffUsers.id,
      email: staffUsers.email,
      displayName: staffUsers.displayName,
      role: staffUsers.role,
      createdAt: staffUsers.createdAt,
      lastSeenAt: staffUsers.lastSeenAt,
    });

  if (!row) throw new Error(`staff upsert returned no row for ${email}`);

  return {
    id: row.id,
    email: row.email,
    displayName: row.displayName,
    role: input.role,
    created: row.lastSeenAt === null,
  };
}

export const ROLE_RANK: Record<StaffRole, number> = { viewer: 1, researcher: 2, admin: 3 };

export function roleSatisfies(actual: StaffRole, required: StaffRole): boolean {
  return ROLE_RANK[actual] >= ROLE_RANK[required];
}
