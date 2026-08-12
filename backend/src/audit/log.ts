import type { Database } from '../db/client.js';
import { auditLog } from '../db/schema/compliance.js';

/**
 * MIGRATION_PLAN.md §6.6 — "every staff read of participant data is audited",
 * and the study's ethics approval rests on being able to answer who looked at a
 * participant's data and when.
 *
 * Written *before* the handler runs rather than after it replies, for two
 * reasons: an attempted read is as interesting as a successful one, and if the
 * audit row cannot be written the request is refused before any participant data
 * is read. Serving data we cannot account for is the worse failure for a medical
 * study than a brief outage.
 */

export interface AuditEntry {
  actorType: 'staff' | 'participant' | 'system';
  actorId?: string | undefined;
  action: string;
  subject?: string | undefined;
  metadata?: Record<string, unknown> | undefined;
}

export class AuditWriteFailed extends Error {
  constructor(cause: unknown) {
    super('could not record the audit entry for this request');
    this.name = 'AuditWriteFailed';
    this.cause = cause;
  }
}

export async function recordAudit(database: Database, entry: AuditEntry): Promise<void> {
  try {
    await database.insert(auditLog).values({
      actorType: entry.actorType,
      actorId: entry.actorId,
      action: entry.action,
      subject: entry.subject,
      metadata: entry.metadata ?? {},
    });
  } catch (error) {
    throw new AuditWriteFailed(error);
  }
}
