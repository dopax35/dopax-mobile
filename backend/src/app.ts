import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import Fastify, { type FastifyInstance } from 'fastify';
import { env, type Env } from './config/env.js';
import { configRoutes } from './routes/config.js';
import { healthRoutes } from './routes/health.js';

export interface BuildAppOptions {
  config?: Env;
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
  await app.register(cors, { origin: config.NODE_ENV === 'development' });
  await app.register(rateLimit, { max: 300, timeWindow: '1 minute' });

  await app.register(healthRoutes);
  await app.register(configRoutes, { prefix: '/v1' });

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
