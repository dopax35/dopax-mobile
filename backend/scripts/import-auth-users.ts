/**
 * Phase 2 (R2) — loads the existing production accounts into PostgreSQL.
 *
 *   npx tsx scripts/import-auth-users.ts [--dry-run]
 *
 * Reads the Firebase Auth export and the uid → participant-code correlation
 * CSV from the repository root. Idempotent: re-running reconciles rather than
 * duplicating, so it is safe to run repeatedly as the source exports improve.
 */
import 'dotenv/config';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { eq, sql } from 'drizzle-orm';
import { closeDatabase, db } from '../src/db/client.js';
import {
  authIdentities,
  participantIdConflicts,
  participants,
} from '../src/db/schema/index.js';
import {
  planImport,
  type CorrelationRow,
  type FirebaseAuthUser,
} from '../src/domain/import/auth-users.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(HERE, '../..');
const AUTH_EXPORT = resolve(REPO_ROOT, 'users.json');
const CORRELATIONS = resolve(REPO_ROOT, 'master_user_correlations.csv');
const REVIEW_CSV = resolve(HERE, '../.tmp/import-review.csv');

const dryRun = process.argv.includes('--dry-run');

/** Minimal CSV reader: these exports are plain, unquoted, comma-separated. */
function readCsv(path: string): CorrelationRow[] {
  const [header, ...lines] = readFileSync(path, 'utf8').trim().split('\n');
  const columns = header!.split(',').map((c) => c.trim());

  return lines
    .filter((line) => line.trim().length > 0)
    .map((line) => {
      const values = line.split(',');
      return Object.fromEntries(
        columns.map((column, i) => [column, values[i]?.trim() ?? '']),
      ) as unknown as CorrelationRow;
    });
}

const authUsers = (JSON.parse(readFileSync(AUTH_EXPORT, 'utf8')) as { users: FirebaseAuthUser[] })
  .users;
const correlations = readCsv(CORRELATIONS);
const plan = planImport(authUsers, correlations);

console.log(`auth accounts:      ${authUsers.length}`);
console.log(`correlation rows:   ${correlations.length}`);
console.log(`planned participants: ${plan.participants.length}`);
console.log(`test accounts:      ${plan.participants.filter((p) => p.isTestAccount).length}`);
console.log(
  `suspected test:     ${plan.participants.filter((p) => p.suspectedTestAccount).length}`,
);
console.log(`id conflicts:       ${plan.conflicts.length}`);

for (const conflict of plan.conflicts) {
  console.warn(
    `  conflict: participant code "${conflict.legacyCode}" is claimed by ${conflict.firebaseUids.length} accounts ` +
      `(${conflict.firebaseUids.join(', ')}). Kept separate; code excluded from upload routing.`,
  );
}

if (dryRun) {
  console.log('\ndry run, nothing written');
  await closeDatabase();
  process.exit(0);
}

const database = db();
const participantIdByFirebaseUid = new Map<string, string>();

await database.transaction(async (tx) => {
  for (const planned of plan.participants) {
    const [row] = await tx
      .insert(participants)
      .values({
        participantCode: planned.participantCode,
        legacyFileUserIds: planned.legacyFileUserIds,
        status: planned.status,
        isTestAccount: planned.isTestAccount,
        enrolledAt: planned.enrolledAt,
      })
      .onConflictDoUpdate({
        target: participants.participantCode,
        set: {
          legacyFileUserIds: planned.legacyFileUserIds,
          status: planned.status,
          isTestAccount: planned.isTestAccount,
          enrolledAt: planned.enrolledAt,
          updatedAt: new Date(),
        },
      })
      .returning({ id: participants.id });

    const participantId = row!.id;
    participantIdByFirebaseUid.set(planned.identity.firebaseUid, participantId);

    const identity = planned.identity;
    await tx
      .insert(authIdentities)
      .values({
        participantId,
        provider: identity.provider,
        providerUid: identity.providerUid,
        firebaseUid: identity.firebaseUid,
        email: identity.email,
        emailVerified: identity.emailVerified,
        displayName: identity.displayName,
        passwordHash: identity.passwordHash,
        passwordSalt: identity.passwordSalt,
        linkedProviders: identity.linkedProviders,
        createdAt: identity.createdAt,
        lastSignInAt: identity.lastSignInAt,
      })
      .onConflictDoUpdate({
        target: authIdentities.firebaseUid,
        set: {
          participantId,
          provider: identity.provider,
          providerUid: identity.providerUid,
          email: identity.email,
          emailVerified: identity.emailVerified,
          displayName: identity.displayName,
          passwordHash: identity.passwordHash,
          passwordSalt: identity.passwordSalt,
          linkedProviders: identity.linkedProviders,
          lastSignInAt: identity.lastSignInAt,
        },
      });
  }

  for (const conflict of plan.conflicts) {
    const ids = conflict.firebaseUids
      .map((uid) => participantIdByFirebaseUid.get(uid))
      .filter((id): id is string => id !== undefined);

    await tx
      .insert(participantIdConflicts)
      .values({
        legacyCode: conflict.legacyCode,
        participantIds: ids,
        firebaseUids: conflict.firebaseUids,
      })
      .onConflictDoUpdate({
        target: participantIdConflicts.legacyCode,
        set: { participantIds: ids, firebaseUids: conflict.firebaseUids },
      });
  }
});

const [counts] = await database
  .select({
    participants: sql<number>`(select count(*)::int from participants)`,
    identities: sql<number>`(select count(*)::int from auth_identities)`,
    conflicts: sql<number>`(select count(*)::int from participant_id_conflicts)`,
    testAccounts: sql<number>`(select count(*)::int from participants where is_test_account)`,
    needsResolution: sql<number>`(select count(*)::int from participants where status = 'needs_id_resolution')`,
  })
  .from(sql`(select 1) as _`);

const providerBreakdown = await database
  .select({ provider: authIdentities.provider, count: sql<number>`count(*)::int` })
  .from(authIdentities)
  .groupBy(authIdentities.provider);

console.log('\n--- in database ---');
console.log(counts);
console.log('providers:', Object.fromEntries(providerBreakdown.map((r) => [r.provider, r.count])));

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
writeFileSync(REVIEW_CSV, `${reviewRows.join('\n')}\n`);
console.log(`\nreview file: ${REVIEW_CSV}`);

// Guard rails: the importer must never lose or invent an account.
if (counts!.identities !== authUsers.length) {
  console.error(
    `MISMATCH: ${authUsers.length} auth accounts in export but ${counts!.identities} in database`,
  );
  await closeDatabase();
  process.exit(1);
}

const orphaned = await database
  .select({ code: participants.participantCode })
  .from(participants)
  .leftJoin(authIdentities, eq(authIdentities.participantId, participants.id))
  .where(sql`${authIdentities.id} is null`);

if (orphaned.length > 0) {
  console.error(`MISMATCH: ${orphaned.length} participants without an auth identity`);
  await closeDatabase();
  process.exit(1);
}

console.log('\nimport complete, all accounts reconciled');
await closeDatabase();
