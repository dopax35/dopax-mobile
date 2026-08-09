import type { FastifyInstance } from 'fastify';

/**
 * R3 — the runtime override for the clients' build-time BOTH_ARCH flag.
 *
 * Clients cache this response so they behave correctly offline. While
 * `bothArch` is true they upload to the legacy Apps Script pipeline *and* to
 * this backend, with independent success markers, so a failure here can never
 * block or delay a legacy upload.
 */
export async function configRoutes(app: FastifyInstance): Promise<void> {
  app.get('/config', async () => {
    const { BOTH_ARCH } = app.config;

    return {
      bothArch: BOTH_ARCH,
      dualWriteLegacy: BOTH_ARCH,
      sourceOfTruth: BOTH_ARCH ? 'legacy_drive' : 'backend',
      upload: {
        strategy: 'multipart_presigned',
        maxPartBytes: 16 * 1024 * 1024,
      },
      events: {
        enabled: true,
        maxBatchSize: 500,
        flushIntervalSeconds: 60,
      },
      serverTime: new Date().toISOString(),
    };
  });
}
