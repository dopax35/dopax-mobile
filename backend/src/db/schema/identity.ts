import { sql } from 'drizzle-orm';
import {
  boolean,
  index,
  integer,
  jsonb,
  pgSchema,
  pgTable,
  smallint,
  text,
  timestamp,
  unique,
  uuid,
} from 'drizzle-orm/pg-core';

/**
 * The locked half of the design: the pseudo-ID↔identity map, the consent records
 * that carry a signature, and the table of plaintext email addresses.
 *
 * Separation is enforced by PostgreSQL, not by us. `dopax_research` holds USAGE on
 * `public` only, so a researcher with a direct connection cannot reach anything in
 * here — see migration 0006. `participants` deliberately stays in `public`: the
 * participant code is the study's pseudonym, and every research table joins to it.
 */
export const identity = pgSchema('identity');

/**
 * Participants keep their production identifier verbatim so that historical
 * Google Drive filenames (PDData_{participantCode}_{date}.zip) still resolve.
 * Three ID formats exist in production, and 15 of 43 users have a code that
 * differs from their Firebase UID, so every historical form is recorded in
 * legacyFileUserIds.
 */
export const participants = pgTable(
  'participants',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    participantCode: text('participant_code').notNull().unique(),
    legacyFileUserIds: text('legacy_file_user_ids')
      .array()
      .notNull()
      .default(sql`'{}'::text[]`),
    cohort: text('cohort'),
    status: text('status').notNull().default('active'), // active | withdrawn | archived
    isTestAccount: boolean('is_test_account').notNull().default(false),
    enrolledAt: timestamp('enrolled_at', { withTimezone: true }),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    index('participants_legacy_ids_idx').using('gin', t.legacyFileUserIds),
    index('participants_status_idx').on(t.status),
  ],
);

/**
 * R1 — Firebase remains the identity provider. passwordHash/salt/hashConfig are
 * captured in Phase 0 purely so the credentials are recoverable if the Firebase
 * project is ever lost; the backend never reads them to authenticate anyone.
 */
export const authIdentities = identity.table(
  'auth_identities',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    participantId: uuid('participant_id')
      .notNull()
      .references(() => participants.id, { onDelete: 'cascade' }),
    provider: text('provider').notNull(), // password | google.com | apple.com
    providerUid: text('provider_uid'),
    firebaseUid: text('firebase_uid').unique(),
    email: text('email'),
    emailVerified: boolean('email_verified').notNull().default(false),
    displayName: text('display_name'),
    passwordHash: text('password_hash'),
    passwordSalt: text('password_salt'),
    hashConfig: jsonb('hash_config'),
    // A Firebase account can have several linked providers. The row keeps the
    // primary one in provider/provider_uid; the full set is preserved here.
    linkedProviders: jsonb('linked_providers').notNull().default(sql`'[]'::jsonb`),
    createdAt: timestamp('created_at', { withTimezone: true }),
    lastSignInAt: timestamp('last_sign_in_at', { withTimezone: true }),
  },
  (t) => [
    unique('auth_identities_provider_uid_key').on(t.provider, t.providerUid),
    index('auth_identities_participant_idx').on(t.participantId),
    index('auth_identities_email_idx').on(t.email),
  ],
);

/**
 * Short-lived email sign-in codes. R1 is preserved: a verified code mints a
 * Firebase custom token and the client still signs in through Firebase, so this
 * is an additional way to reach a Firebase session, never a second identity
 * provider.
 *
 * Only the hash is stored. A dump of this table must not let anyone sign in as
 * a participant, and the plaintext code exists solely in the email we sent.
 */
export const emailOtpCodes = identity.table(
  'email_otp_codes',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    email: text('email').notNull(),
    codeHash: text('code_hash').notNull(),
    expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
    // Counted server-side so a stolen code cannot be brute-forced within its
    // validity window even if the caller rotates IPs past the rate limiter.
    attempts: integer('attempts').notNull().default(0),
    consumedAt: timestamp('consumed_at', { withTimezone: true }),
    requestIp: text('request_ip'),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    index('email_otp_codes_email_idx').on(t.email, t.createdAt),
    index('email_otp_codes_expires_idx').on(t.expiresAt),
  ],
);

/**
 * `revision` powers the local-wins merge the iOS client already relies on after
 * the v3.7.29 regression that blanked profiles. A stale revision on write is a
 * 409, never a silent overwrite.
 *
 * `age` is an integer on Android and a string on iOS; it normalises to smallint
 * here and the original value is preserved in `settings`.
 */
export const participantProfiles = pgTable('participant_profiles', {
  participantId: uuid('participant_id')
    .primaryKey()
    .references(() => participants.id, { onDelete: 'cascade' }),
  revision: smallint('revision').notNull().default(1),
  age: smallint('age'),
  gender: text('gender'),
  dominantHand: text('dominant_hand'),
  affectedSide: text('affected_side'),
  medications: jsonb('medications').notNull().default(sql`'[]'::jsonb`),
  signatureName: text('signature_name'),
  settings: jsonb('settings').notNull().default(sql`'{}'::jsonb`),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
  updatedByDevice: uuid('updated_by_device'),
});

export const participantProfileHistory = pgTable(
  'participant_profile_history',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    participantId: uuid('participant_id')
      .notNull()
      .references(() => participants.id, { onDelete: 'cascade' }),
    revision: smallint('revision').notNull(),
    snapshot: jsonb('snapshot').notNull(),
    recordedAt: timestamp('recorded_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index('profile_history_participant_idx').on(t.participantId, t.revision)],
);

/**
 * Production contains at least one participant code shared by two separate auth
 * accounts (`pd_53a21c75`). Such a code must never be added to
 * `participants.legacy_file_user_ids`, because upload resolution would then
 * silently assign one person's research data to the other. It is recorded here
 * instead so ingestion refuses to guess and a human resolves it.
 */
export const participantIdConflicts = pgTable('participant_id_conflicts', {
  id: uuid('id').primaryKey().defaultRandom(),
  legacyCode: text('legacy_code').notNull().unique(),
  participantIds: uuid('participant_ids').array().notNull(),
  firebaseUids: text('firebase_uids').array().notNull(),
  detectedAt: timestamp('detected_at', { withTimezone: true }).notNull().defaultNow(),
  resolvedAt: timestamp('resolved_at', { withTimezone: true }),
  resolutionNote: text('resolution_note'),
});

/**
 * Consent is an append-only audit trail rather than the boolean the app stores
 * today. This is a medical study: we must be able to prove what was consented
 * to, by whom, and when.
 */
export const consents = identity.table(
  'consents',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    participantId: uuid('participant_id')
      .notNull()
      .references(() => participants.id),
    documentVersion: text('document_version').notNull(),
    documentHash: text('document_hash').notNull(),
    signatureName: text('signature_name').notNull(),
    // Base64 PNG of the drawn signature. Nullable because every consent
    // gathered before the drawn-signature screen shipped has a typed name only,
    // and those consents stay valid exactly as they were given.
    signatureImage: text('signature_image'),
    // Which language the participant actually read the form in. A Hebrew
    // signatory who was shown the English text has not consented to the same
    // document, so this belongs in the audit trail.
    documentLocale: text('document_locale'),
    grantedAt: timestamp('granted_at', { withTimezone: true }).notNull(),
    revokedAt: timestamp('revoked_at', { withTimezone: true }),
    platform: text('platform'),
    appVersion: text('app_version'),
  },
  (t) => [index('consents_participant_idx').on(t.participantId, t.grantedAt)],
);
