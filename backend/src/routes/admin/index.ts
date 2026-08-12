import type { FastifyInstance, FastifyRequest } from 'fastify';
import { AdminTokenInvalid, verifyAdminToken, type StaffRole } from '../../auth/admin-token.js';
import { roleSatisfies } from '../../auth/staff.js';
import { AuditWriteFailed, recordAudit } from '../../audit/log.js';
import type { Database } from '../../db/client.js';
import type { IdTokenVerifier } from '../../auth/id-token.js';
import { adminAuthRoutes } from './auth.js';
import { adminOperationsRoutes } from './operations.js';
import { adminOverviewRoutes } from './overview.js';
import { adminParticipantRoutes } from './participants.js';

/**
 * The staff console surface, MIGRATION_PLAN.md §7.1 (`GET /v1/admin/*`).
 *
 * Strictly additive and read-only over the participant tables: nothing here can
 * change a participant, an upload, or a consent. The only writes are the audit
 * trail and the two "a human decided this" notes on the data-quality queue.
 */

export interface AdminRouteDependencies {
  database: Database;
  verifier: IdTokenVerifier;
  devLoginEnabled: boolean;
  adminSecret: string;
  sessionTtlSeconds: number;
}

export interface AdminSession {
  staffId: string;
  email: string;
  role: StaffRole;
  displayName?: string | undefined;
}

function bearerToken(request: FastifyRequest): string | undefined {
  const header = request.headers.authorization;
  if (!header?.toLowerCase().startsWith('bearer ')) return undefined;

  const token = header.slice(7).trim();
  return token.length > 0 ? token : undefined;
}

export async function adminRoutes(
  app: FastifyInstance,
  options: AdminRouteDependencies,
): Promise<void> {
  // Fastify hands the plugin its whole options object, `prefix` included, so the
  // dependencies are forwarded to the child scopes on their own. Passing options
  // straight through would apply /v1/admin a second time to every child route.
  const dependencies: AdminRouteDependencies = {
    database: options.database,
    verifier: options.verifier,
    devLoginEnabled: options.devLoginEnabled,
    adminSecret: options.adminSecret,
    sessionTtlSeconds: options.sessionTtlSeconds,
  };

  // Sign-in cannot require a session, so it lives in its own scope without the
  // hooks below rather than as an exception inside them. An authentication
  // bypass expressed as a conditional is the kind that gets widened by accident.
  await app.register(adminAuthRoutes, dependencies);

  await app.register(async (guarded) => {
    guarded.decorateRequest('staff', null);

    guarded.addHook('preHandler', async (request, reply) => {
      const token = bearerToken(request);

      if (!token) {
        return reply.code(401).send({ error: 'unauthorized', detail: 'no bearer token' });
      }

      let session: AdminSession;
      try {
        session = await verifyAdminToken(token, { secret: dependencies.adminSecret });
      } catch (error) {
        if (error instanceof AdminTokenInvalid) {
          request.log.warn({ err: error }, 'admin token rejected');
          return reply.code(401).send({ error: 'unauthorized' });
        }
        throw error;
      }

      request.staff = session;

      const { minRole } = request.routeOptions.config;
      if (minRole && !roleSatisfies(session.role, minRole)) {
        // Audited, because a staff member reaching for data above their role is
        // exactly the event an ethics review asks about.
        await recordAudit(dependencies.database, {
          actorType: 'staff',
          actorId: session.staffId,
          action: 'admin.access.denied',
          metadata: { path: request.url, role: session.role, requiredRole: minRole },
        });

        return reply.code(403).send({ error: 'forbidden', requiredRole: minRole });
      }
    });

    // §6.6 — runs before the handler, so an unauditable request is refused
    // instead of served. See src/audit/log.ts for why that trade is made.
    guarded.addHook('preHandler', async (request, reply) => {
      const config = request.routeOptions.config;
      if (config.audit === false) return;

      const session = request.staff;
      if (!session) return;

      try {
        await recordAudit(dependencies.database, {
          actorType: 'staff',
          actorId: session.staffId,
          action: config.auditAction ?? `${request.method} ${request.routeOptions.url}`,
          subject: config.auditSubject?.(request),
          metadata: {
            role: session.role,
            email: session.email,
            query: request.query,
            ip: request.ip,
          },
        });
      } catch (error) {
        if (error instanceof AuditWriteFailed) {
          request.log.error({ err: error }, 'refusing to serve an unauditable admin read');
          return reply
            .code(503)
            .send({ error: 'audit_unavailable', detail: 'the read was not served' });
        }
        throw error;
      }
    });

    await guarded.register(adminOverviewRoutes, dependencies);
    await guarded.register(adminParticipantRoutes, dependencies);
    await guarded.register(adminOperationsRoutes, dependencies);
  });
}

declare module 'fastify' {
  interface FastifyRequest {
    staff: AdminSession | null;
  }

  /** Per-route knobs read by the scope's hooks. */
  interface FastifyContextConfig {
    minRole?: StaffRole;
    /** Audit is opt-out, so a new route is audited unless someone says otherwise. */
    audit?: false;
    auditAction?: string;
    auditSubject?: (request: FastifyRequest) => string | undefined;
  }
}
