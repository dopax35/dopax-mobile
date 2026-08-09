import { sql } from 'drizzle-orm';
import {
  boolean,
  index,
  jsonb,
  pgTable,
  smallint,
  text,
  timestamp,
  unique,
  uuid,
} from 'drizzle-orm/pg-core';

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
export const authIdentities = pgTable(
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
 * Consent is an append-only audit trail rather than the boolean the app stores
 * today. This is a medical study: we must be able to prove what was consented
 * to, by whom, and when.
 */
export const consents = pgTable(
  'consents',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    participantId: uuid('participant_id')
      .notNull()
      .references(() => participants.id),
    documentVersion: text('document_version').notNull(),
    documentHash: text('document_hash').notNull(),
    signatureName: text('signature_name').notNull(),
    grantedAt: timestamp('granted_at', { withTimezone: true }).notNull(),
    revokedAt: timestamp('revoked_at', { withTimezone: true }),
    platform: text('platform'),
    appVersion: text('app_version'),
  },
  (t) => [index('consents_participant_idx').on(t.participantId, t.grantedAt)],
);
