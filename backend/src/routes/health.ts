import { sql } from 'drizzle-orm';
import type { FastifyInstance } from 'fastify';
import { db } from '../db/client.js';
import { bootstrapStatus } from '../domain/bootstrap/ledger.js';
import { REQUIRED_BOOTSTRAP_STEPS } from '../domain/bootstrap/steps.js';

export async function healthRoutes(app: FastifyInstance): Promise<void> {
  app.get('/healthz', async () => ({ status: 'ok' }));

  app.get('/readyz', async (_request, reply) => {
    try {
      await db().execute(sql`select 1`);
    } catch (error) {
      app.log.error({ err: error }, 'readiness check failed');
      return reply.code(503).send({ status: 'unavailable', database: 'error' });
    }

    // R5 — reported rather than enforced here, so a database that is reachable
    // but not yet migrated is still diagnosable. Ingest routes are what refuse
    // to serve until this is complete.
    let bootstrap: { state: string; pending?: string[] };
    try {
      const status = await bootstrapStatus(db(), REQUIRED_BOOTSTRAP_STEPS);
      bootstrap = status.complete
        ? { state: 'complete' }
        : { state: 'pending', pending: status.pending };
    } catch (error) {
      app.log.warn({ err: error }, 'could not read bootstrap status');
      bootstrap = { state: 'unknown' };
    }

    return { status: 'ready', database: 'ok', bootstrap };
  });
}
