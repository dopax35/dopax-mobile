import 'dotenv/config';
import { migrate } from 'drizzle-orm/postgres-js/migrator';
import { env } from '../config/env.js';
import { createConnection, createDatabase } from './client.js';
import { guardMigrationTarget } from './migration-target.js';

const target = guardMigrationTarget(env().DATABASE_URL, 'db:migrate');
console.log(`migrating ${target.host}`);

const sql = createConnection(undefined, 1);

try {
  await migrate(createDatabase(sql), { migrationsFolder: './src/db/migrations' });
  console.log('migrations applied');
} finally {
  await sql.end({ timeout: 5 });
}
