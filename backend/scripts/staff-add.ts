/**
 * Grants a person access to the staff console.
 *
 *   npm run staff:add -- --email hagai@example.com --role admin --name "Hagai S"
 *   npm run staff:add -- --email viewer@example.com --role viewer
 *   npm run staff:add -- --email leaver@example.com --deactivate
 *
 * There is deliberately no registration endpoint. Anyone in the Firebase project
 * can obtain a valid ID token — including all 43 participants — so the only thing
 * standing between a token and the whole study's data is a row in `staff_users`.
 * Creating that row is an operator action with a shell, not an HTTP request.
 *
 * Idempotent: re-running changes the role of an existing account rather than
 * failing, so it doubles as the way to promote or demote someone.
 */
import 'dotenv/config';
import { closeDatabase, db } from '../src/db/client.js';
import { STAFF_ROLES, isStaffRole } from '../src/auth/admin-token.js';
import { upsertStaff } from '../src/auth/staff.js';
import { recordAudit } from '../src/audit/log.js';

function flag(name: string): string | undefined {
  const index = process.argv.indexOf(`--${name}`);
  return index === -1 ? undefined : process.argv[index + 1];
}

const email = flag('email');
const role = flag('role') ?? 'viewer';
const name = flag('name');
const deactivate = process.argv.includes('--deactivate');

function usage(message: string): never {
  console.error(`${message}\n`);
  console.error('usage: npm run staff:add -- --email <address> [--role <role>] [--name <name>] [--deactivate]');
  console.error(`roles: ${STAFF_ROLES.join(' | ')}`);
  process.exit(2);
}

if (!email?.includes('@')) usage('a valid --email is required');
if (!isStaffRole(role)) usage(`--role must be one of ${STAFF_ROLES.join(', ')}`);

let exitCode = 1;

try {
  const database = db();

  const staff = await upsertStaff(database, {
    email,
    role,
    ...(name ? { displayName: name } : {}),
    active: !deactivate,
  });

  // The staff list is an access-control decision, so changing it is auditable
  // for the same reason reading participant data is.
  await recordAudit(database, {
    actorType: 'system',
    action: deactivate ? 'staff.deactivated' : 'staff.granted',
    subject: staff.id,
    metadata: { email: staff.email, role, via: 'staff:add script' },
  });

  console.log(
    deactivate
      ? `deactivated ${staff.email}`
      : `${staff.email} can now sign in to the admin console as ${role}`,
  );

  exitCode = 0;
} catch (error) {
  console.error('staff:add failed:', error instanceof Error ? error.message : error);
} finally {
  await closeDatabase();
}

process.exit(exitCode);
