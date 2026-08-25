import { eq, sql } from 'drizzle-orm';
import type { Database } from '../../db/client.js';
import { authIdentities, participantIdConflicts, participants } from '../../db/schema/index.js';
import type { ImportPlan } from './auth-users.js';

export interface AuthImportCounts {
  participants: number;
  identities: number;
  conflicts: number;
  testAccounts: number;
  needsResolution: number;
}

/**
 * Applies the plan in a single transaction, so the step is all-or-nothing: a
 * crash halfway through leaves the database exactly as it was rather than
 * half-populated, which is what lets the bootstrap safely replay it.
 *
 * Idempotent by construction — every write upserts on a natural key
 * (participant_code, firebase_uid, legacy_code).
 */
export async function applyImportPlan(
  database: Database,
  plan: ImportPlan,
): Promise<AuthImportCounts> {
  const participantIdByFirebaseUid = new Map<string, string>();

  await database.transaction(async (tx) => {
    for (const planned of plan.participants) {
      const [row] = await tx
        .insert(participants)
        .values({
          participantCode: planned.participantCode,
          legacyFileUserIds: planned.legacyFileUserIds,
          status: planned.status,
          isTestAccount: planned.isTestAccount,
          enrolledAt: planned.enrolledAt,
        })
        .onConflictDoUpdate({
          target: participants.participantCode,
          set: {
            legacyFileUserIds: planned.legacyFileUserIds,
            status: planned.status,
            isTestAccount: planned.isTestAccount,
            enrolledAt: planned.enrolledAt,
            updatedAt: new Date(),
          },
        })
        .returning({ id: participants.id });

      const participantId = row!.id;
      participantIdByFirebaseUid.set(planned.identity.firebaseUid, participantId);

      const identity = planned.identity;
      await tx
        .insert(authIdentities)
        .values({
          participantId,
          provider: identity.provider,
          providerUid: identity.providerUid,
          firebaseUid: identity.firebaseUid,
          email: identity.email,
          emailVerified: identity.emailVerified,
          displayName: identity.displayName,
          passwordHash: identity.passwordHash,
          passwordSalt: identity.passwordSalt,
          linkedProviders: identity.linkedProviders,
          createdAt: identity.createdAt,
          lastSignInAt: identity.lastSignInAt,
        })
        .onConflictDoUpdate({
          target: authIdentities.firebaseUid,
          set: {
            participantId,
            provider: identity.provider,
            providerUid: identity.providerUid,
            email: identity.email,
            emailVerified: identity.emailVerified,
            displayName: identity.displayName,
            passwordHash: identity.passwordHash,
            passwordSalt: identity.passwordSalt,
            linkedProviders: identity.linkedProviders,
            lastSignInAt: identity.lastSignInAt,
          },
        });
    }

    for (const conflict of plan.conflicts) {
      const ids = conflict.firebaseUids
        .map((uid) => participantIdByFirebaseUid.get(uid))
        .filter((id): id is string => id !== undefined);

      await tx
        .insert(participantIdConflicts)
        .values({
          legacyCode: conflict.legacyCode,
          participantIds: ids,
          firebaseUids: conflict.firebaseUids,
        })
        .onConflictDoUpdate({
          target: participantIdConflicts.legacyCode,
          set: { participantIds: ids, firebaseUids: conflict.firebaseUids },
        });
    }
  });

  return countImported(database);
}

export async function countImported(database: Database): Promise<AuthImportCounts> {
  const [counts] = await database
    .select({
      participants: sql<number>`(select count(*)::int from participants)`,
      identities: sql<number>`(select count(*)::int from identity.auth_identities)`,
      conflicts: sql<number>`(select count(*)::int from participant_id_conflicts)`,
      testAccounts: sql<number>`(select count(*)::int from participants where is_test_account)`,
      needsResolution: sql<number>`(select count(*)::int from participants where status = 'needs_id_resolution')`,
    })
    .from(sql`(select 1) as _`);

  return counts!;
}

export async function providerBreakdown(database: Database): Promise<Record<string, number>> {
  const rows = await database
    .select({ provider: authIdentities.provider, count: sql<number>`count(*)::int` })
    .from(authIdentities)
    .groupBy(authIdentities.provider);

  return Object.fromEntries(rows.map((row) => [row.provider, row.count]));
}

/**
 * The import must never lose or invent an account. Both checks below have
 * failed during development, and either one silently shipped would mean a real
 * participant cannot sign in or cannot reach their historical data.
 */
export async function verifyAuthImport(
  database: Database,
  expectedAccounts: number,
): Promise<void> {
  const counts = await countImported(database);

  if (counts.identities !== expectedAccounts) {
    throw new Error(
      `account count mismatch: ${expectedAccounts} in the export, ${counts.identities} in the database`,
    );
  }

  const orphaned = await database
    .select({ code: participants.participantCode })
    .from(participants)
    .leftJoin(authIdentities, eq(authIdentities.participantId, participants.id))
    .where(sql`${authIdentities.id} is null`);

  if (orphaned.length > 0) {
    throw new Error(
      `${orphaned.length} participants have no auth identity: ${orphaned
        .map((row) => row.code)
        .join(', ')}`,
    );
  }
}
