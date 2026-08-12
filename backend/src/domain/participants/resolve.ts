import { and, eq, sql } from 'drizzle-orm';
import type { Database } from '../../db/client.js';
import { authIdentities, participants } from '../../db/schema/identity.js';

export interface ResolvedParticipant {
  participantId: string;
  participantCode: string;
  firebaseUid: string;
  status: string;
  created: boolean;
}

export interface ResolveParticipantInput {
  firebaseUid: string;
  email?: string | undefined;
  emailVerified?: boolean | undefined;
  provider?: string | undefined;
  displayName?: string | undefined;
  /**
   * Local participant code from the device (pd_xxxxxxxx / 6-char hex / etc.).
   * Used only when creating a *new* participant — never renumbers an existing one.
   */
  preferredParticipantCode?: string | undefined;
}

/**
 * R1 resolution order:
 *   1. auth_identities.firebase_uid
 *   2. participants.legacy_file_user_ids contains firebase_uid
 *   3. create new participant (code = preferred or firebase uid)
 *
 * Never renumbers an existing participant_code.
 */
export async function resolveParticipant(
  database: Database,
  input: ResolveParticipantInput,
): Promise<ResolvedParticipant> {
  const byIdentity = await database
    .select({
      participantId: authIdentities.participantId,
      firebaseUid: authIdentities.firebaseUid,
      participantCode: participants.participantCode,
      status: participants.status,
    })
    .from(authIdentities)
    .innerJoin(participants, eq(participants.id, authIdentities.participantId))
    .where(eq(authIdentities.firebaseUid, input.firebaseUid))
    .limit(1);

  if (byIdentity[0]?.firebaseUid) {
    await touchIdentity(database, input);
    return {
      participantId: byIdentity[0].participantId,
      participantCode: byIdentity[0].participantCode,
      firebaseUid: input.firebaseUid,
      status: byIdentity[0].status,
      created: false,
    };
  }

  const byLegacy = await database
    .select({
      id: participants.id,
      participantCode: participants.participantCode,
      status: participants.status,
    })
    .from(participants)
    .where(sql`${input.firebaseUid} = ANY(${participants.legacyFileUserIds})`)
    .limit(1);

  if (byLegacy[0]) {
    await ensureAuthIdentity(database, {
      participantId: byLegacy[0].id,
      ...input,
    });
    return {
      participantId: byLegacy[0].id,
      participantCode: byLegacy[0].participantCode,
      firebaseUid: input.firebaseUid,
      status: byLegacy[0].status,
      created: false,
    };
  }

  // New enrolment — prefer the device's local code when it does not collide.
  const preferred = input.preferredParticipantCode?.trim();
  let participantCode = preferred && preferred.length > 0 ? preferred : input.firebaseUid;

  const codeTaken = await database
    .select({ id: participants.id })
    .from(participants)
    .where(eq(participants.participantCode, participantCode))
    .limit(1);

  if (codeTaken[0]) {
    // Never steal another participant's code. Fall back to the Firebase UID,
    // which is unique per auth account.
    participantCode = input.firebaseUid;
  }

  const [created] = await database
    .insert(participants)
    .values({
      participantCode,
      legacyFileUserIds: [input.firebaseUid, ...(preferred && preferred !== input.firebaseUid ? [preferred] : [])],
      status: 'active',
      enrolledAt: new Date(),
    })
    .returning({
      id: participants.id,
      participantCode: participants.participantCode,
      status: participants.status,
    });

  if (!created) throw new Error('failed to create participant');

  await ensureAuthIdentity(database, {
    participantId: created.id,
    ...input,
  });

  return {
    participantId: created.id,
    participantCode: created.participantCode,
    firebaseUid: input.firebaseUid,
    status: created.status,
    created: true,
  };
}

async function ensureAuthIdentity(
  database: Database,
  input: ResolveParticipantInput & { participantId: string },
): Promise<void> {
  await database
    .insert(authIdentities)
    .values({
      participantId: input.participantId,
      provider: input.provider ?? 'firebase',
      providerUid: input.firebaseUid,
      firebaseUid: input.firebaseUid,
      email: input.email,
      emailVerified: input.emailVerified ?? false,
      displayName: input.displayName,
      linkedProviders: input.provider ? [{ providerId: input.provider }] : [],
      lastSignInAt: new Date(),
      createdAt: new Date(),
    })
    .onConflictDoUpdate({
      target: authIdentities.firebaseUid,
      set: {
        email: input.email,
        emailVerified: input.emailVerified ?? false,
        displayName: input.displayName,
        lastSignInAt: new Date(),
      },
    });
}

async function touchIdentity(database: Database, input: ResolveParticipantInput): Promise<void> {
  await database
    .update(authIdentities)
    .set({
      email: input.email,
      emailVerified: input.emailVerified ?? false,
      displayName: input.displayName,
      lastSignInAt: new Date(),
    })
    .where(and(eq(authIdentities.firebaseUid, input.firebaseUid)));
}
