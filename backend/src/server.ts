import 'dotenv/config';
import { buildApp } from './app.js';
import { env } from './config/env.js';
import { closeDatabase } from './db/client.js';

const config = env();
const app = await buildApp({ config });

// Bind to 0.0.0.0 so physical phones on the same Wi-Fi can reach the laptop
// during Phase 3 testing. See MIGRATION_PLAN.md §5.3.
await app.listen({ port: config.PORT, host: '0.0.0.0' });

app.log.info(
  { bothArch: config.BOTH_ARCH, storageBackend: config.STORAGE_BACKEND },
  config.BOTH_ARCH
    ? 'running in dual-architecture mode: legacy Drive pipeline remains authoritative'
    : 'running in backend-only mode: this service is the source of truth',
);

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.once(signal, () => {
    void (async () => {
      app.log.info({ signal }, 'shutting down');
      await app.close();
      await closeDatabase();
      process.exit(0);
    })();
  });
}
