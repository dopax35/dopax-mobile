import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import { env } from '../config/env.js';
import * as schema from './schema/index.js';

export type Database = ReturnType<typeof createDatabase>;

export function createConnection(url = env().DATABASE_URL, max = 10) {
  return postgres(url, {
    max,
    // Ingestion COPY batches and multi-gigabyte parses can outlast the default.
    idle_timeout: 30,
    connect_timeout: 10,
    onnotice: () => {},
  });
}

export function createDatabase(sql = createConnection()) {
  return drizzle(sql, { schema });
}

let cached: { sql: ReturnType<typeof createConnection>; db: Database } | undefined;

export function db(): Database {
  if (!cached) {
    const sql = createConnection();
    cached = { sql, db: createDatabase(sql) };
  }
  return cached.db;
}

export async function closeDatabase(): Promise<void> {
  if (cached) {
    await cached.sql.end({ timeout: 5 });
    cached = undefined;
  }
}

export { schema };
