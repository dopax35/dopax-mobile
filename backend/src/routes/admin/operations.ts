import { eq } from 'drizzle-orm';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { isUndefinedTable } from '../../db/errors.js';
import { participantIdConflicts } from '../../db/schema/identity.js';
import { driveManifestExceptions } from '../../db/schema/uploads.js';
import {
  auditEntries,
  bootstrapLedger,
  driveExceptions,
  openParticipantIdConflicts,
  recentReconciliationRuns,
  uploadCoverageByDay,
  uploadFeed,
} from '../../domain/admin/queries.js';
import { assessFlipReadiness } from '../../domain/admin/view.js';
import type { AdminRouteDependencies } from './index.js';

const feedQuery = z.object({
  status: z.string().trim().min(1).max(40).optional(),
  since: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/, 'since must be yyyy-MM-dd')
    .optional(),
  limit: z.coerce.number().int().min(1).max(500).default(100),
  offset: z.coerce.number().int().min(0).default(0),
});

const resolution = z.object({
  resolutionNote: z.string().trim().min(3).max(2000),
});

const idParams = z.object({ id: z.string().uuid() });

export async function adminOperationsRoutes(
  app: FastifyInstance,
  dependencies: AdminRouteDependencies,
): Promise<void> {
  const { database } = dependencies;

  app.get(
    '/uploads',
    { config: { minRole: 'viewer', auditAction: 'uploads.list' } },
    async (request, reply) => {
      const parsed = feedQuery.safeParse(request.query);
      if (!parsed.success) {
        return reply.code(400).send({ error: 'invalid_query', detail: parsed.error.issues });
      }

      return { uploads: await uploadFeed(database, parsed.data) };
    },
  );

  app.get(
    '/uploads/coverage',
    { config: { minRole: 'viewer', audit: false } },
    async (request, reply) => {
      const parsed = feedQuery.safeParse(request.query);
      if (!parsed.success) {
        return reply.code(400).send({ error: 'invalid_query', detail: parsed.error.issues });
      }

      const rows = await uploadCoverageByDay(database, parsed.data.since);

      return {
        days: rows.map((row) => ({
          ...row,
          participants: Number(row.participants),
          bytes: Number(row.bytes),
        })),
      };
    },
  );

  /** R3 — the 14-clean-run gate, read straight from the recorded runs. */
  app.get('/reconciliation', { config: { minRole: 'viewer', audit: false } }, async () => {
    const runs = await recentReconciliationRuns(database, 60);
    return { runs, flip: assessFlipReadiness(runs) };
  });

  /** R5 — whether production actually migrated itself, per the step ledger. */
  app.get('/bootstrap', { config: { minRole: 'viewer', audit: false } }, async () => ({
    steps: await bootstrapLedger(database),
  }));

  app.get(
    '/data-quality',
    { config: { minRole: 'researcher', auditAction: 'data_quality.list' } },
    async (request) => {
      const includeResolved = (request.query as { includeResolved?: string }).includeResolved === 'true';

      const conflicts = await openParticipantIdConflicts(database);

      // A database that predates `drive_manifest_exceptions` would otherwise turn
      // this into a 500 that reads like a bug in the console. Naming the missing
      // migration is more useful than either a stack trace or an empty list that
      // implies the corpus is fully accounted for.
      try {
        return { conflicts, exceptions: await driveExceptions(database, includeResolved) };
      } catch (error) {
        if (!isUndefinedTable(error)) throw error;

        request.log.error({ err: error }, 'drive_manifest_exceptions is missing');

        return {
          conflicts,
          exceptions: [],
          schemaOutOfDate: {
            missing: 'drive_manifest_exceptions',
            migration: '0003_drive_manifest_exceptions',
            detail:
              'Unattributable Drive objects cannot be listed until this migration is applied.',
          },
        };
      }
    },
  );

  /**
   * Records the human decision §3.2 has been waiting for. Deliberately does not
   * reassign any upload: splitting the contested `pd_53a21c75` days between two
   * participants is an ingestion change that belongs in the importer, where it is
   * idempotent and reviewable, not in a dashboard button. Writing the note here
   * is what unblocks that work without guessing.
   */
  app.patch(
    '/data-quality/conflicts/:id',
    {
      config: {
        minRole: 'admin',
        auditAction: 'data_quality.conflict.resolved',
        auditSubject: (request) => (request.params as { id?: string }).id,
      },
    },
    async (request, reply) => {
      const params = idParams.safeParse(request.params);
      if (!params.success) return reply.code(400).send({ error: 'invalid_id' });

      const body = resolution.safeParse(request.body);
      if (!body.success) {
        return reply.code(400).send({ error: 'invalid_request', detail: body.error.issues });
      }

      const [updated] = await database
        .update(participantIdConflicts)
        .set({
          resolvedAt: new Date(),
          resolutionNote: `${body.data.resolutionNote}\n— ${request.staff!.email}`,
        })
        .where(eq(participantIdConflicts.id, params.data.id))
        .returning({ id: participantIdConflicts.id, legacyCode: participantIdConflicts.legacyCode });

      if (!updated) return reply.code(404).send({ error: 'not_found' });

      return { resolved: updated };
    },
  );

  app.patch(
    '/data-quality/exceptions/:id',
    {
      config: {
        minRole: 'admin',
        auditAction: 'data_quality.exception.resolved',
        auditSubject: (request) => (request.params as { id?: string }).id,
      },
    },
    async (request, reply) => {
      const params = idParams.safeParse(request.params);
      if (!params.success) return reply.code(400).send({ error: 'invalid_id' });

      const body = resolution.safeParse(request.body);
      if (!body.success) {
        return reply.code(400).send({ error: 'invalid_request', detail: body.error.issues });
      }

      const [updated] = await database
        .update(driveManifestExceptions)
        .set({
          resolvedAt: new Date(),
          resolutionNote: `${body.data.resolutionNote}\n— ${request.staff!.email}`,
        })
        .where(eq(driveManifestExceptions.id, params.data.id))
        .returning({
          id: driveManifestExceptions.id,
          filename: driveManifestExceptions.filename,
        });

      if (!updated) return reply.code(404).send({ error: 'not_found' });

      return { resolved: updated };
    },
  );

  /** Who looked at what. Only an admin can read the trail. */
  app.get(
    '/audit',
    { config: { minRole: 'admin', auditAction: 'audit.read' } },
    async (request, reply) => {
      const parsed = z
        .object({
          subject: z.string().trim().min(1).max(200).optional(),
          actorId: z.string().uuid().optional(),
          limit: z.coerce.number().int().min(1).max(500).default(100),
          offset: z.coerce.number().int().min(0).default(0),
        })
        .safeParse(request.query);

      if (!parsed.success) {
        return reply.code(400).send({ error: 'invalid_query', detail: parsed.error.issues });
      }

      const entries = await auditEntries(database, parsed.data);
      return { entries: entries.map((entry) => ({ ...entry, id: String(entry.id) })) };
    },
  );
}
