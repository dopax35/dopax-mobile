import 'dotenv/config';
import { migrate } from 'drizzle-orm/postgres-js/migrator';
import { createConnection, createDatabase } from './client.js';

const sql = createConnection(undefined, 1);

try {
  await migrate(createDatabase(sql), { migrationsFolder: './src/db/migrations' });
  console.log('migrations applied');
} finally {
  await sql.end({ timeout: 5 });
}
