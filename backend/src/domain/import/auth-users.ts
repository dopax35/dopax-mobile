/**
 * Turns the Firebase Auth export plus the uid → participant-code correlation
 * CSV into a plan that can be applied to PostgreSQL.
 *
 * Deliberately pure: no database, no filesystem. The judgement calls here
 * (which accounts are test data, how to handle a duplicated participant code)
 * are the parts most worth unit-testing, and the parts a reviewer needs to be
 * able to read without running anything.
 */

export interface FirebaseProviderInfo {
  providerId: string;
  rawId?: string;
  email?: string;
  displayName?: string;
  photoUrl?: string;
}

export interface FirebaseAuthUser {
  localId: string;
  email?: string;
  emailVerified?: boolean;
  passwordHash?: string;
  salt?: string;
  displayName?: string;
  photoUrl?: string;
  createdAt?: string;
  lastSignedInAt?: string;
  providerUserInfo?: FirebaseProviderInfo[];
}

export interface CorrelationRow {
  uid: string;
  file_user_id: string;
  email?: string;
  name?: string;
  platform?: string;
}

export interface PlannedIdentity {
  firebaseUid: string;
  provider: string;
  providerUid: string;
  email: string | null;
  emailVerified: boolean;
  displayName: string | null;
  passwordHash: string | null;
  passwordSalt: string | null;
  linkedProviders: FirebaseProviderInfo[];
  createdAt: Date | null;
  lastSignInAt: Date | null;
}

export interface PlannedParticipant {
  participantCode: string;
  legacyFileUserIds: string[];
  status: 'active' | 'needs_id_resolution';
  isTestAccount: boolean;
  suspectedTestAccount: boolean;
  enrolledAt: Date | null;
  identity: PlannedIdentity;
}

export interface PlannedConflict {
  legacyCode: string;
  firebaseUids: string[];
}

export interface ImportPlan {
  participants: PlannedParticipant[];
  conflicts: PlannedConflict[];
}

/**
 * Conservative on purpose. A false positive quietly removes a real participant
 * from the study, which is far worse than leaving a test account unflagged, so
 * anything less than obvious is surfaced as `suspectedTestAccount` for a human
 * instead of being flagged outright.
 */
const TEST_EMAIL_PATTERNS: RegExp[] = [
  /@example\.com$/i,
  /^(new)?test/i,
  /explore/i,
];

const TEST_DISPLAY_NAMES = new Set(['test user', 'john doe']);

/** Seeded QA accounts in production follow `firstlast.NNNNN@gmail.com`. */
const SUSPECTED_TEST_EMAIL = /^[a-z]+\.\d{4,6}@gmail\.com$/i;

export function isTestAccount(user: FirebaseAuthUser): boolean {
  const email = user.email?.trim() ?? '';
  const displayName = user.displayName?.trim().toLowerCase() ?? '';

  if (email && TEST_EMAIL_PATTERNS.some((pattern) => pattern.test(email))) return true;
  if (displayName && TEST_DISPLAY_NAMES.has(displayName)) return true;

  return false;
}

export function isSuspectedTestAccount(user: FirebaseAuthUser): boolean {
  if (isTestAccount(user)) return false;
  return SUSPECTED_TEST_EMAIL.test(user.email?.trim() ?? '');
}

export function resolvePrimaryProvider(user: FirebaseAuthUser): {
  provider: string;
  providerUid: string;
} {
  const primary = user.providerUserInfo?.[0];
  if (primary) {
    return { provider: primary.providerId, providerUid: primary.rawId ?? user.localId };
  }
  return { provider: 'password', providerUid: user.localId };
}

function epochMsToDate(value: string | undefined): Date | null {
  if (!value) return null;
  const ms = Number(value);
  return Number.isFinite(ms) && ms > 0 ? new Date(ms) : null;
}

export function planImport(
  users: FirebaseAuthUser[],
  correlations: CorrelationRow[],
): ImportPlan {
  const codeByUid = new Map<string, string>();
  for (const row of correlations) {
    const code = row.file_user_id?.trim();
    if (row.uid && code) codeByUid.set(row.uid, code);
  }

  // A participant code claimed by more than one auth account cannot be used to
  // route uploads. Find those before building the plan.
  const uidsByCode = new Map<string, string[]>();
  for (const [uid, code] of codeByUid) {
    uidsByCode.set(code, [...(uidsByCode.get(code) ?? []), uid]);
  }

  const contestedCodes = new Map<string, string[]>();
  for (const [code, uids] of uidsByCode) {
    if (uids.length > 1) contestedCodes.set(code, uids.sort());
  }

  const participants: PlannedParticipant[] = [];

  for (const user of users) {
    const mappedCode = codeByUid.get(user.localId);
    const contested = mappedCode !== undefined && contestedCodes.has(mappedCode);

    // When the code is contested we fall back to the Firebase UID, which is
    // unique by construction, and leave the ambiguous code out of the lookup
    // array entirely so no upload can be misattributed.
    const participantCode = contested || !mappedCode ? user.localId : mappedCode;

    const legacyFileUserIds = new Set<string>([user.localId]);
    if (mappedCode && !contested) legacyFileUserIds.add(mappedCode);

    const { provider, providerUid } = resolvePrimaryProvider(user);

    participants.push({
      participantCode,
      legacyFileUserIds: [...legacyFileUserIds].sort(),
      status: contested ? 'needs_id_resolution' : 'active',
      isTestAccount: isTestAccount(user),
      suspectedTestAccount: isSuspectedTestAccount(user),
      enrolledAt: epochMsToDate(user.createdAt),
      identity: {
        firebaseUid: user.localId,
        provider,
        providerUid,
        email: user.email?.trim() || null,
        emailVerified: user.emailVerified ?? false,
        displayName: user.displayName?.trim() || null,
        passwordHash: user.passwordHash ?? null,
        passwordSalt: user.salt ?? null,
        linkedProviders: user.providerUserInfo ?? [],
        createdAt: epochMsToDate(user.createdAt),
        lastSignInAt: epochMsToDate(user.lastSignedInAt),
      },
    });
  }

  const conflicts: PlannedConflict[] = [...contestedCodes.entries()].map(
    ([legacyCode, firebaseUids]) => ({ legacyCode, firebaseUids }),
  );

  return { participants, conflicts };
}
