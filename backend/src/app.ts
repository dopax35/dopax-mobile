import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import Fastify, { type FastifyInstance } from 'fastify';
import { createDevVerifier, createFirebaseVerifier, type IdTokenVerifier } from './auth/id-token.js';
import { env, type Env } from './config/env.js';
import { db, type Database } from './db/client.js';
import { adminRoutes } from './routes/admin/index.js';
import { configRoutes } from './routes/config.js';
import { healthRoutes } from './routes/health.js';
import { participantRoutes } from './routes/participants/index.js';

export interface BuildAppOptions {
  config?: Env;
  /** Injected by tests; production resolves the shared pool. */
  database?: Database;
  idTokenVerifier?: IdTokenVerifier;
}

function resolveVerifier(config: Env, override?: IdTokenVerifier): IdTokenVerifier {
  if (override) return override;

  // ADMIN_DEV_LOGIN already cannot be true outside development (see config/env.ts),
  // so this cannot select the bypass in a deployed environment.
  if (config.ADMIN_DEV_LOGIN) return createDevVerifier();

  return createFirebaseVerifier({
    projectId: config.FIREBASE_PROJECT_ID,
    ...(config.GOOGLE_APPLICATION_CREDENTIALS
      ? { credentialsPath: config.GOOGLE_APPLICATION_CREDENTIALS }
      : {}),
  });
}

export async function buildApp(options: BuildAppOptions = {}): Promise<FastifyInstance> {
  const config = options.config ?? env();

  const prettyTransport =
    config.NODE_ENV === 'development'
      ? {
          transport: {
            target: 'pino-pretty',
            options: { translateTime: 'HH:MM:ss', ignore: 'pid,hostname' },
          },
        }
      : {};

  const app = Fastify({
    logger: {
      level: config.LOG_LEVEL,
      ...prettyTransport,
      redact: ['req.headers.authorization', 'req.headers.cookie'],
    },
    // Devices upload directly to object storage via presigned URLs, so request
    // bodies here stay small. Anything larger is a bug worth rejecting loudly.
    bodyLimit: 5 * 1024 * 1024,
    trustProxy: true,
  });

  app.decorate('config', config);

  await app.register(helmet, { contentSecurityPolicy: false });
  await app.register(cors, { origin: true });
  await app.register(rateLimit, { max: 300, timeWindow: '1 minute' });

  await app.register(healthRoutes);
  await app.register(configRoutes, { prefix: '/v1' });

  const database = options.database ?? db(config.DATABASE_URL);
  const verifier = resolveVerifier(config, options.idTokenVerifier);

  // §7.1 — participant auth + profile + consent (additive dual-write path).
  await app.register(participantRoutes, {
    prefix: '/v1',
    database,
    verifier,
    jwtSecret: config.JWT_SECRET,
    accessTtlSeconds: config.JWT_ACCESS_TTL,
  });

  // §7.1 — the staff console. Opt-in per environment because it reads
  // participant data; an environment that has not been given a secret does not
  // get the surface at all.
  if (config.ADMIN_API_ENABLED) {
    await app.register(adminRoutes, {
      prefix: '/v1/admin',
      database,
      verifier,
      devLoginEnabled: config.ADMIN_DEV_LOGIN,
      adminSecret: config.ADMIN_JWT_SECRET!,
      sessionTtlSeconds: config.ADMIN_SESSION_TTL,
    });
  }

  app.setNotFoundHandler((request, reply) => {
    reply.code(404).send({ error: 'not_found', path: request.url });
  });

  return app;
}

declare module 'fastify' {
  interface FastifyInstance {
    config: Env;
  }
}
