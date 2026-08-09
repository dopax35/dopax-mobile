import type { Database } from '../../db/client.js';
import {
  applyImportPlan,
  providerBreakdown,
  verifyAuthImport,
} from '../import/auth-users-repository.js';
import { loadAuthImportSources, type AuthImportSources } from '../import/auth-users-source.js';
import { planImport } from '../import/auth-users.js';
import type { BootstrapStep } from './runner.js';

export const AUTH_USERS_STEP = 'auth_users';

/**
 * Step 1 of §4.4 — the 43 production accounts.
 *
 * This must run before anything that resolves an upload to a person: a Drive
 * ZIP whose participant code is not yet in the database cannot be attributed,
 * and guessing is the one thing the migration must never do.
 */
export function authUsersStep(database: Database, sourceDir: string): BootstrapStep {
  let sources: AuthImportSources | undefined;
  const load = (): AuthImportSources => (sources ??= loadAuthImportSources(sourceDir));

  return {
    name: AUTH_USERS_STEP,
    description: 'Firebase Auth export → participants, auth_identities, participant_id_conflicts',

    async checksum() {
      return load().checksum;
    },

    async run() {
      const { users, correlations } = load();
      const plan = planImport(users, correlations);
      const inDatabase = await applyImportPlan(database, plan);

      return {
        // Rows this run upserted — one participant and one identity each, plus
        // the conflicts. Deliberately not the table totals, which would report
        // the whole corpus on a replay that changed nothing.
        rowsWritten: plan.participants.length * 2 + plan.conflicts.length,
        detail: {
          inDatabase,
          authAccountsInExport: users.length,
          providers: await providerBreakdown(database),
          conflictedCodes: plan.conflicts.map((conflict) => conflict.legacyCode),
        },
      };
    },

    async verify() {
      await verifyAuthImport(database, load().users.length);
    },
  };
}

/**
 * The ordered pipeline. Steps 2–5 of §4.4 (Firestore profiles, the Drive
 * manifest, the ZIP stream-parse, and reconciliation) register here as they are
 * written; order is a dependency order, not a preference.
 */
export function bootstrapSteps(database: Database, sourceDir: string): BootstrapStep[] {
  return [authUsersStep(database, sourceDir)];
}

/** Steps that must be complete before the backend may accept research data. */
export const REQUIRED_BOOTSTRAP_STEPS: readonly string[] = [AUTH_USERS_STEP];
