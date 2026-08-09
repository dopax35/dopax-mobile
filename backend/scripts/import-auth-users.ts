/**
 * Phase 2 (R2) — loads the existing production accounts into PostgreSQL.
 *
 *   npx tsx scripts/import-auth-users.ts [--dry-run]
 *
 * This is the hands-on version, useful for reviewing the plan and producing the
 * review CSV. Production does not run it directly: `npm run db:bootstrap`
 * invokes the same importer as step 1 of the R5 first-run migration, so the two
 * paths cannot drift.
 *
 * Idempotent: re-running reconciles rather than duplicating, so it is safe to
 * run repeatedly as the source exports improve.
 */
import 'dotenv/config';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { env } from '../src/config/env.js';
import { closeDatabase, db } from '../src/db/client.js';
import {
  applyImportPlan,
  providerBreakdown,
  verifyAuthImport,
} from '../src/domain/import/auth-users-repository.js';
import { loadAuthImportSources } from '../src/domain/import/auth-users-source.js';
import { planImport } from '../src/domain/import/auth-users.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const REVIEW_CSV = resolve(HERE, '../.tmp/import-review.csv');

const dryRun = process.argv.includes('--dry-run');

const sources = loadAuthImportSources(resolve(process.cwd(), env().MIGRATION_SOURCE_DIR));
const plan = planImport(sources.users, sources.correlations);

console.log(`auth accounts:        ${sources.users.length}`);
console.log(`correlation rows:     ${sources.correlations.length}`);
console.log(`planned participants: ${plan.participants.length}`);
console.log(`test accounts:        ${plan.participants.filter((p) => p.isTestAccount).length}`);
console.log(
  `suspected test:       ${plan.participants.filter((p) => p.suspectedTestAccount).length}`,
);
console.log(`id conflicts:         ${plan.conflicts.length}`);

for (const conflict of plan.conflicts) {
  console.warn(
    `  conflict: participant code "${conflict.legacyCode}" is claimed by ${conflict.firebaseUids.length} accounts ` +
      `(${conflict.firebaseUids.join(', ')}). Kept separate; code excluded from upload routing.`,
  );
}

const reviewRows = [
  'participant_code,firebase_uid,email,display_name,provider,legacy_ids,is_test,suspected_test,status',
  ...plan.participants.map((p) =>
    [
      p.participantCode,
      p.identity.firebaseUid,
      p.identity.email ?? '',
      (p.identity.displayName ?? '').replace(/,/g, ' '),
      p.identity.provider,
      p.legacyFileUserIds.join(' '),
      p.isTestAccount,
      p.suspectedTestAccount,
      p.status,
    ].join(','),
  ),
];
mkdirSync(dirname(REVIEW_CSV), { recursive: true });
writeFileSync(REVIEW_CSV, `${reviewRows.join('\n')}\n`);
console.log(`\nreview file: ${REVIEW_CSV}`);

if (dryRun) {
  console.log('\ndry run, nothing written to the database');
  await closeDatabase();
  process.exit(0);
}

const database = db();
const counts = await applyImportPlan(database, plan);

console.log('\n--- in database ---');
console.log(counts);
console.log('providers:', await providerBreakdown(database));

try {
  await verifyAuthImport(database, sources.users.length);
} catch (error) {
  console.error(`MISMATCH: ${error instanceof Error ? error.message : String(error)}`);
  await closeDatabase();
  process.exit(1);
}

console.log('\nimport complete, all accounts reconciled');
await closeDatabase();
