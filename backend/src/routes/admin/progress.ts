import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { getActiveUserProgressSummary } from '../../domain/admin/progress.js';
import { canSeeIdentity, redactParticipant } from '../../domain/admin/view.js';
import type { AdminRouteDependencies } from './index.js';

const progressQuery = z.object({
  includeTestAccounts: z.enum(['true', 'false']).default('false'),
});

export async function adminProgressRoutes(
  app: FastifyInstance,
  dependencies: AdminRouteDependencies,
): Promise<void> {
  app.get(
    '/progress',
    { config: { minRole: 'viewer', auditAction: 'progress.summary' } },
    async (request, reply) => {
      const parsed = progressQuery.safeParse(request.query);
      if (!parsed.success) {
        return reply.code(400).send({ error: 'invalid_query', detail: parsed.error.issues });
      }

      const role = request.staff!.role;
      const summary = await getActiveUserProgressSummary(
        dependencies.database,
        parsed.data.includeTestAccounts === 'true',
      );

      return {
        ...summary,
        identityVisible: canSeeIdentity(role),
        participants: summary.participants.map((p) => {
          if (canSeeIdentity(role)) return p;
          const { email, displayName, firebaseUid, ...rest } = p;
          return rest;
        }),
      };
    },
  );
}
