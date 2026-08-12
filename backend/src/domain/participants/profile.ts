import { eq } from 'drizzle-orm';
import { z } from 'zod';
import type { Database } from '../../db/client.js';
import {
  participantProfileHistory,
  participantProfiles,
} from '../../db/schema/identity.js';

const medicationSchema = z.object({
  name: z.string().min(1),
  dosage: z.string().optional().default(''),
  dose: z.string().optional(), // Android legacy key
});

const sessionWindowsSchema = z
  .object({
    morning: z.string().optional(),
    noon: z.string().optional(),
    evening: z.string().optional(),
    custom: z.string().optional(),
    random: z.string().optional(),
  })
  .passthrough();

/**
 * Additive profile write body. Unknown keys land in `settings` so Android/iOS
 * can diverge without a migration per field.
 */
export const profileWriteSchema = z.object({
  revision: z.number().int().positive(),
  age: z.union([z.number().int().min(0).max(130), z.string()]).optional().nullable(),
  gender: z.string().optional().nullable(),
  dominantHand: z.string().optional().nullable(),
  affectedSide: z.string().optional().nullable(),
  signatureName: z.string().optional().nullable(),
  medications: z.union([z.array(medicationSchema), z.string()]).optional(),
  settings: z.record(z.string(), z.unknown()).optional(),
  // Convenience top-level mirrors that fold into settings
  sessionWindows: sessionWindowsSchema.optional(),
  healthConnections: z.record(z.string(), z.unknown()).optional(),
  permissions: z.record(z.string(), z.unknown()).optional(),
  profileComplete: z.boolean().optional(),
  onboardingVersion: z.number().int().optional(),
  displayName: z.string().optional().nullable(),
  yearOfBirth: z.number().int().min(1900).max(2100).optional().nullable(),
});

export type ProfileWriteInput = z.infer<typeof profileWriteSchema>;

export interface ProfileView {
  revision: number;
  age: number | null;
  gender: string | null;
  dominantHand: string | null;
  affectedSide: string | null;
  signatureName: string | null;
  medications: unknown;
  settings: Record<string, unknown>;
  updatedAt: string;
}

export class ProfileRevisionConflict extends Error {
  readonly server: ProfileView;

  constructor(server: ProfileView) {
    super('profile revision conflict');
    this.name = 'ProfileRevisionConflict';
    this.server = server;
  }
}

function normalizeAge(value: number | string | null | undefined): number | null {
  if (value === null || value === undefined || value === '') return null;
  const n = typeof value === 'number' ? value : Number.parseInt(String(value), 10);
  if (!Number.isFinite(n)) return null;
  return Math.max(0, Math.min(130, Math.trunc(n)));
}

function normalizeMedications(value: ProfileWriteInput['medications']): unknown[] {
  if (value === undefined) return [];
  if (typeof value === 'string') {
    try {
      const parsed = JSON.parse(value) as unknown;
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  }
  return value.map((m) => ({
    name: m.name,
    dosage: m.dosage || m.dose || '',
  }));
}

function toView(row: typeof participantProfiles.$inferSelect): ProfileView {
  return {
    revision: row.revision,
    age: row.age,
    gender: row.gender,
    dominantHand: row.dominantHand,
    affectedSide: row.affectedSide,
    signatureName: row.signatureName,
    medications: row.medications,
    settings: (row.settings ?? {}) as Record<string, unknown>,
    updatedAt: row.updatedAt.toISOString(),
  };
}

export async function getProfile(
  database: Database,
  participantId: string,
): Promise<ProfileView | null> {
  const rows = await database
    .select()
    .from(participantProfiles)
    .where(eq(participantProfiles.participantId, participantId))
    .limit(1);

  return rows[0] ? toView(rows[0]) : null;
}

export async function putProfile(
  database: Database,
  participantId: string,
  input: ProfileWriteInput,
  options?: { updatedByDevice?: string | undefined },
): Promise<ProfileView> {
  const existing = await getProfile(database, participantId);

  if (existing && existing.revision !== input.revision) {
    throw new ProfileRevisionConflict(existing);
  }

  const nextSettings: Record<string, unknown> = {
    ...(existing?.settings ?? {}),
    ...(input.settings ?? {}),
  };

  if (input.sessionWindows) nextSettings.sessionWindows = input.sessionWindows;
  if (input.healthConnections) nextSettings.healthConnections = input.healthConnections;
  if (input.permissions) nextSettings.permissions = input.permissions;
  if (input.profileComplete !== undefined) nextSettings.profileComplete = input.profileComplete;
  if (input.onboardingVersion !== undefined) nextSettings.onboardingVersion = input.onboardingVersion;
  if (input.displayName !== undefined) nextSettings.displayName = input.displayName;
  if (input.yearOfBirth !== undefined) {
    nextSettings.yearOfBirth = input.yearOfBirth;
    // Derive age when only YoB is supplied and age is absent.
    if (input.age === undefined && typeof input.yearOfBirth === 'number') {
      nextSettings.rawAge = String(new Date().getFullYear() - input.yearOfBirth);
    }
  }
  if (input.age !== undefined && input.age !== null) {
    nextSettings.rawAge = String(input.age);
  }

  const age = normalizeAge(
    input.age ??
      (typeof input.yearOfBirth === 'number'
        ? new Date().getFullYear() - input.yearOfBirth
        : existing?.age),
  );

  const medications =
    input.medications !== undefined
      ? normalizeMedications(input.medications)
      : ((existing?.medications as unknown[]) ?? []);

  const nextRevision = (existing?.revision ?? 0) + 1;

  if (existing) {
    await database.insert(participantProfileHistory).values({
      participantId,
      revision: existing.revision,
      snapshot: existing as unknown as Record<string, unknown>,
    });
  }

  const [row] = await database
    .insert(participantProfiles)
    .values({
      participantId,
      revision: nextRevision,
      age,
      gender: input.gender ?? existing?.gender ?? null,
      dominantHand: input.dominantHand ?? existing?.dominantHand ?? null,
      affectedSide: input.affectedSide ?? existing?.affectedSide ?? null,
      signatureName: input.signatureName ?? existing?.signatureName ?? null,
      medications,
      settings: nextSettings,
      updatedAt: new Date(),
      updatedByDevice: options?.updatedByDevice,
    })
    .onConflictDoUpdate({
      target: participantProfiles.participantId,
      set: {
        revision: nextRevision,
        age,
        gender: input.gender ?? existing?.gender ?? null,
        dominantHand: input.dominantHand ?? existing?.dominantHand ?? null,
        affectedSide: input.affectedSide ?? existing?.affectedSide ?? null,
        signatureName: input.signatureName ?? existing?.signatureName ?? null,
        medications,
        settings: nextSettings,
        updatedAt: new Date(),
        updatedByDevice: options?.updatedByDevice,
      },
    })
    .returning();

  if (!row) throw new Error('failed to upsert profile');
  return toView(row);
}
