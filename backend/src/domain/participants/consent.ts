import { createHash } from 'node:crypto';
import { desc, eq } from 'drizzle-orm';
import { z } from 'zod';
import type { Database } from '../../db/client.js';
import { consents } from '../../db/schema/identity.js';

/** Roughly 1.5 MB of base64, comfortably above any hand-drawn signature PNG. */
const SIGNATURE_IMAGE_MAX_CHARS = 2_000_000;

export const consentWriteSchema = z.object({
  signatureName: z.string().min(1),
  // Base64 PNG of the drawn signature. Optional: clients older than the
  // drawn-signature screen still submit a typed name only, and rejecting them
  // would break consent for participants mid-upgrade.
  signatureImage: z.string().max(SIGNATURE_IMAGE_MAX_CHARS).optional(),
  documentLocale: z.string().min(2).max(16).optional(),
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
  /** Whether a drawn signature was captured, not the image itself. */
  hasSignatureImage: boolean;
  documentLocale: string | null;
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
        // Two participants who signed the same version in different languages
        // did not sign the same document, so the hash has to separate them.
        locale: input.documentLocale ?? null,
      }),
    )
    .digest('hex');
}

function toView(row: typeof consents.$inferSelect): ConsentView {
  return {
    id: row.id,
    documentVersion: row.documentVersion,
    documentHash: row.documentHash,
    signatureName: row.signatureName,
    hasSignatureImage: row.signatureImage !== null,
    documentLocale: row.documentLocale,
    grantedAt: row.grantedAt.toISOString(),
    platform: row.platform,
    appVersion: row.appVersion,
  };
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
      signatureImage: input.signatureImage,
      documentLocale: input.documentLocale,
      grantedAt,
      platform: input.platform,
      appVersion: input.appVersion,
    })
    .returning();

  if (!row) throw new Error('failed to append consent');

  return toView(row);
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

  return rows.map(toView);
}
