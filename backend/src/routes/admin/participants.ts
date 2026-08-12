import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import {
  findParticipant,
  listParticipants,
  participantConsents,
  participantDailySummaries,
  participantEvents,
  participantIdentities,
  participantProfile,
  participantTestSessions,
  participantUploads,
} from '../../domain/admin/queries.js';
import {
  canSeeClinicalDetail,
  canSeeIdentity,
  redactParticipant,
  summariseAdherence,
  toDayString,
} from '../../domain/admin/view.js';
import type { AdminRouteDependencies } from './index.js';

const listQuery = z.object({
  search: z.string().trim().min(1).max(120).optional(),
  status: z.string().trim().min(1).max(40).optional(),
  includeTestAccounts: z.enum(['true', 'false']).default('false'),
  limit: z.coerce.number().int().min(1).max(200).default(50),
  offset: z.coerce.number().int().min(0).default(0),
});

const detailQuery = z.object({
  /** Days of history for the adherence window. */
  windowDays: z.coerce.number().int().min(7).max(365).default(90),
  eventLimit: z.coerce.number().int().min(1).max(1000).default(200),
});

const participantParams = z.object({ id: z.string().uuid() });

function subjectFromParams(request: FastifyRequest): string | undefined {
  const { id } = (request.params ?? {}) as { id?: string };
  return id;
}

export async function adminParticipantRoutes(
  app: FastifyInstance,
  dependencies: AdminRouteDependencies,
): Promise<void> {
  app.get(
    '/participants',
    { config: { minRole: 'viewer', auditAction: 'participants.list' } },
    async (request, reply) => {
      const parsed = listQuery.safeParse(request.query);
      if (!parsed.success) {
        return reply.code(400).send({ error: 'invalid_query', detail: parsed.error.issues });
      }

      const role = request.staff!.role;
      const { total, rows } = await listParticipants(dependencies.database, {
        search: parsed.data.search,
        status: parsed.data.status,
        includeTestAccounts: parsed.data.includeTestAccounts === 'true',
        limit: parsed.data.limit,
        offset: parsed.data.offset,
      });

      return {
        total,
        limit: parsed.data.limit,
        offset: parsed.data.offset,
        identityVisible: canSeeIdentity(role),
        participants: rows.map((row) => redactParticipant(row, role)),
      };
    },
  );

  app.get(
    '/participants/:id',
    {
      config: {
        // The detail view is the research data itself, so a viewer — who exists
        // to read aggregates — does not reach it.
        minRole: 'researcher',
        auditAction: 'participant.read',
        auditSubject: subjectFromParams,
      },
    },
    async (request, reply) => {
      const params = participantParams.safeParse(request.params);
      if (!params.success) {
        return reply.code(400).send({ error: 'invalid_participant_id' });
      }

      const query = detailQuery.safeParse(request.query);
      if (!query.success) {
        return reply.code(400).send({ error: 'invalid_query', detail: query.error.issues });
      }

      const { database } = dependencies;
      const role = request.staff!.role;

      const participant = await findParticipant(database, params.data.id);
      if (!participant) return reply.code(404).send({ error: 'not_found' });

      const [identities, profile, consents, uploads, events, sessions, summaries] =
        await Promise.all([
          participantIdentities(database, participant.id),
          participantProfile(database, participant.id),
          participantConsents(database, participant.id),
          participantUploads(database, participant.id),
          participantEvents(database, participant.id, query.data.eventLimit),
          participantTestSessions(database, participant.id, query.data.eventLimit),
          participantDailySummaries(database, participant.id),
        ]);

      const to = toDayString(new Date());
      const from = toDayString(
        new Date(Date.now() - (query.data.windowDays - 1) * 86_400_000),
      );

      return {
        participant: redactParticipant(
          {
            ...participant,
            provider: identities[0]?.provider ?? null,
            email: identities[0]?.email ?? null,
            displayName: identities[0]?.displayName ?? null,
            firebaseUid: identities[0]?.firebaseUid ?? null,
          },
          role,
        ),
        identities: canSeeIdentity(role)
          ? identities
          : identities.map(({ provider, createdAt, lastSignInAt }) => ({
              provider,
              createdAt,
              lastSignInAt,
            })),
        profile: canSeeClinicalDetail(role) ? (profile ?? null) : null,
        consents,
        adherence: summariseAdherence(uploads, { from, to }),
        uploads,
        events,
        testSessions: canSeeClinicalDetail(role) ? sessions : [],
        dailySummaries: summaries,
      };
    },
  );
}
