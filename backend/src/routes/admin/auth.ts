import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { signAdminToken } from '../../auth/admin-token.js';
import { IdTokenInvalid } from '../../auth/id-token.js';
import { findActiveStaffByEmail, touchStaffLastSeen } from '../../auth/staff.js';
import { recordAudit } from '../../audit/log.js';
import type { AdminRouteDependencies } from './index.js';

const sessionRequest = z.object({
  idToken: z.string().min(1),
});

/**
 * R1 — staff sign in through Firebase exactly like participants do, and this
 * backend only verifies. What makes someone staff is an active `staff_users`
 * row, never anything carried on the token: every participant in the project can
 * produce a valid Firebase ID token, so the allowlist is the entire boundary.
 */
export async function adminAuthRoutes(
  app: FastifyInstance,
  dependencies: AdminRouteDependencies,
): Promise<void> {
  app.post(
    '/auth/session',
    {
      config: {
        // Sign-in is the brute-force target on this surface and the global 300/min
        // is far too generous for it.
        rateLimit: { max: 10, timeWindow: '1 minute' },
      },
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
          request.log.warn({ err: error }, 'admin sign-in rejected');
          return reply.code(401).send({ error: 'unauthorized' });
        }
        throw error;
      }

      if (!identity.email) {
        return reply
          .code(403)
          .send({ error: 'not_staff', detail: 'the account has no email address' });
      }

      const staff = await findActiveStaffByEmail(dependencies.database, identity.email);

      if (!staff) {
        // Recorded so a participant token being presented here is visible rather
        // than a silent 403. The email is the subject of the refusal, not
        // participant data.
        await recordAudit(dependencies.database, {
          actorType: 'system',
          action: 'admin.session.refused',
          metadata: { email: identity.email, provider: identity.provider, ip: request.ip },
        });

        return reply.code(403).send({ error: 'not_staff' });
      }

      const session = await signAdminToken(
        {
          staffId: staff.id,
          email: staff.email,
          role: staff.role,
          ...(staff.displayName ? { displayName: staff.displayName } : {}),
        },
        { secret: dependencies.adminSecret, ttlSeconds: dependencies.sessionTtlSeconds },
      );

      await touchStaffLastSeen(dependencies.database, staff.id);
      await recordAudit(dependencies.database, {
        actorType: 'staff',
        actorId: staff.id,
        action: 'admin.session.created',
        metadata: {
          role: staff.role,
          provider: identity.provider,
          verifier: dependencies.verifier.kind,
          ip: request.ip,
        },
      });

      return {
        token: session.token,
        expiresAt: session.expiresAt.toISOString(),
        staff: {
          id: staff.id,
          email: staff.email,
          displayName: staff.displayName,
          role: staff.role,
        },
      };
    },
  );

  /** Lets the console show whether dev login is available without probing for it. */
  app.get('/auth/methods', async () => ({
    firebase: dependencies.verifier.kind === 'firebase',
    devLogin: dependencies.devLoginEnabled,
  }));
}
