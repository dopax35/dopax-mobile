import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import {
  ParticipantTokenInvalid,
  signParticipantToken,
  verifyParticipantToken,
  type ParticipantTokenClaims,
} from '../../auth/participant-token.js';
import { IdTokenInvalid, type IdTokenVerifier } from '../../auth/id-token.js';
import type { Database } from '../../db/client.js';
import { appendConsent, consentWriteSchema, listConsents } from '../../domain/participants/consent.js';
import {
  getProfile,
  ProfileRevisionConflict,
  profileWriteSchema,
  putProfile,
} from '../../domain/participants/profile.js';
import { resolveParticipant } from '../../domain/participants/resolve.js';

export interface ParticipantRouteDependencies {
  database: Database;
  verifier: IdTokenVerifier;
  jwtSecret: string;
  accessTtlSeconds: number;
}

declare module 'fastify' {
  interface FastifyRequest {
    participant?: ParticipantTokenClaims;
  }
}

const sessionRequest = z.object({
  idToken: z.string().min(1),
  preferredParticipantCode: z.string().min(1).optional(),
  displayName: z.string().optional(),
});

async function requireParticipant(
  request: FastifyRequest,
  reply: FastifyReply,
  jwtSecret: string,
): Promise<ParticipantTokenClaims | null> {
  const header = request.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    await reply.code(401).send({ error: 'unauthorized' });
    return null;
  }

  try {
    const claims = await verifyParticipantToken(header.slice('Bearer '.length), {
      secret: jwtSecret,
    });
    request.participant = claims;
    return claims;
  } catch (error) {
    if (error instanceof ParticipantTokenInvalid) {
      await reply.code(401).send({ error: 'unauthorized' });
      return null;
    }
    throw error;
  }
}

export async function participantRoutes(
  app: FastifyInstance,
  dependencies: ParticipantRouteDependencies,
): Promise<void> {
  /**
   * POST /v1/auth/session
   * Firebase ID token → participant JWT. Resolves or creates the participant
   * without renumbering existing codes (R1).
   */
  app.post(
    '/auth/session',
    {
      config: { rateLimit: { max: 30, timeWindow: '1 minute' } },
    },
    async (request, reply) => {
      const parsed = sessionRequest.safeParse(request.body);
      if (!parsed.success) {
        return reply.code(400).send({ error: 'invalid_request', detail: 'idToken is required' });
      }

      let identity;
      try {
        identity = await dependencies.verifier.verify(parsed.data.idToken);
      } catch (error) {
        if (error instanceof IdTokenInvalid) {
          return reply.code(401).send({ error: 'unauthorized' });
        }
        throw error;
      }

      const resolved = await resolveParticipant(dependencies.database, {
        firebaseUid: identity.uid,
        email: identity.email,
        emailVerified: identity.emailVerified,
        provider: identity.provider,
        displayName: parsed.data.displayName,
        preferredParticipantCode: parsed.data.preferredParticipantCode,
      });

      const session = await signParticipantToken(
        {
          participantId: resolved.participantId,
          firebaseUid: resolved.firebaseUid,
          participantCode: resolved.participantCode,
        },
        {
          secret: dependencies.jwtSecret,
          ttlSeconds: dependencies.accessTtlSeconds,
        },
      );

      const profile = await getProfile(dependencies.database, resolved.participantId);

      return {
        token: session.token,
        expiresAt: session.expiresAt.toISOString(),
        participant: {
          id: resolved.participantId,
          code: resolved.participantCode,
          status: resolved.status,
          created: resolved.created,
        },
        profile,
      };
    },
  );

  app.get('/participants/me', async (request, reply) => {
    const claims = await requireParticipant(request, reply, dependencies.jwtSecret);
    if (!claims) return;

    const profile = await getProfile(dependencies.database, claims.participantId);
    const consentRows = await listConsents(dependencies.database, claims.participantId);

    return {
      participant: {
        id: claims.participantId,
        code: claims.participantCode,
        firebaseUid: claims.firebaseUid,
      },
      profile,
      consents: consentRows,
    };
  });

  app.put('/participants/me/profile', async (request, reply) => {
    const claims = await requireParticipant(request, reply, dependencies.jwtSecret);
    if (!claims) return;

    const parsed = profileWriteSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'invalid_request', detail: parsed.error.flatten() });
    }

    try {
      const profile = await putProfile(dependencies.database, claims.participantId, parsed.data);
      return { profile };
    } catch (error) {
      if (error instanceof ProfileRevisionConflict) {
        return reply.code(409).send({ error: 'revision_conflict', profile: error.server });
      }
      throw error;
    }
  });

  app.post('/participants/me/consent', async (request, reply) => {
    const claims = await requireParticipant(request, reply, dependencies.jwtSecret);
    if (!claims) return;

    const parsed = consentWriteSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'invalid_request', detail: parsed.error.flatten() });
    }

    const consent = await appendConsent(dependencies.database, claims.participantId, parsed.data);
    return { consent };
  });
}
