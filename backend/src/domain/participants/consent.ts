import { createHash } from 'node:crypto';
import { desc, eq } from 'drizzle-orm';
import { z } from 'zod';
import type { Database } from '../../db/client.js';
import { consents } from '../../db/schema/identity.js';

export const consentWriteSchema = z.object({
  signatureName: z.string().min(1),
  documentVersion: z.string().min(1).optional().default('onboarding-v2'),
  documentHash: z.string().optional(),
  grantedAt: z.string().datetime().optional(),
  platform: z.string().optional(),
  appVersion: z.string().optional(),
});

export type ConsentWriteInput = z.infer<typeof consentWriteSchema>;

export interface ConsentView {
  id: string;
  documentVersion: string;
  documentHash: string;
  signatureName: string;
  grantedAt: string;
  platform: string | null;
  appVersion: string | null;
}

function defaultHash(input: ConsentWriteInput): string {
  return createHash('sha256')
    .update(
      JSON.stringify({
        version: input.documentVersion,
        signature: input.signatureName,
        platform: input.platform ?? null,
      }),
    )
    .digest('hex');
}

export async function appendConsent(
  database: Database,
  participantId: string,
  input: ConsentWriteInput,
): Promise<ConsentView> {
  const documentVersion = input.documentVersion ?? 'onboarding-v2';
  const grantedAt = input.grantedAt ? new Date(input.grantedAt) : new Date();
  const documentHash =
    input.documentHash ??
    defaultHash({ ...input, documentVersion, signatureName: input.signatureName });

  const [row] = await database
    .insert(consents)
    .values({
      participantId,
      documentVersion,
      documentHash,
      signatureName: input.signatureName,
      grantedAt,
      platform: input.platform,
      appVersion: input.appVersion,
    })
    .returning();

  if (!row) throw new Error('failed to append consent');

  return {
    id: row.id,
    documentVersion: row.documentVersion,
    documentHash: row.documentHash,
    signatureName: row.signatureName,
    grantedAt: row.grantedAt.toISOString(),
    platform: row.platform,
    appVersion: row.appVersion,
  };
}

export async function listConsents(
  database: Database,
  participantId: string,
): Promise<ConsentView[]> {
  const rows = await database
    .select()
    .from(consents)
    .where(eq(consents.participantId, participantId))
    .orderBy(desc(consents.grantedAt));

  return rows.map((row) => ({
    id: row.id,
    documentVersion: row.documentVersion,
    documentHash: row.documentHash,
    signatureName: row.signatureName,
    grantedAt: row.grantedAt.toISOString(),
    platform: row.platform,
    appVersion: row.appVersion,
  }));
}
