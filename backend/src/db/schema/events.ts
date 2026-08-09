import { sql } from 'drizzle-orm';
import {
  bigserial,
  index,
  jsonb,
  pgTable,
  primaryKey,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from 'drizzle-orm/pg-core';
import { participants } from './identity.js';
import { devices } from './uploads.js';

/**
 * The user-action record. Today there is no way to know a participant has
 * stopped using the app until their daily ZIPs simply stop arriving; this table
 * is what makes adherence observable in near real time.
 *
 * Declared here for type-safe queries. The initial migration converts it to a
 * RANGE-partitioned table on occurred_at — which is why occurred_at is part of
 * both the primary key and the dedupe index, as Postgres requires the partition
 * key to appear in every unique constraint.
 *
 * dedupeKey is supplied by the client so that offline retries and R3 dual-write
 * can never produce duplicate rows.
 */
export const events = pgTable(
  'events',
  {
    id: bigserial('id', { mode: 'bigint' }).notNull(),
    participantId: uuid('participant_id')
      .notNull()
      .references(() => participants.id),
    deviceId: uuid('device_id').references(() => devices.id),
    occurredAt: timestamp('occurred_at', { withTimezone: true }).notNull(),
    receivedAt: timestamp('received_at', { withTimezone: true }).notNull().defaultNow(),
    eventType: text('event_type').notNull(),
    sessionId: uuid('session_id'),
    appVersion: text('app_version'),
    payload: jsonb('payload').notNull().default(sql`'{}'::jsonb`),
    dedupeKey: text('dedupe_key').notNull(),
  },
  (t) => [
    primaryKey({ columns: [t.id, t.occurredAt] }),
    uniqueIndex('events_dedupe_idx').on(t.dedupeKey, t.occurredAt),
    index('events_participant_time_idx').on(t.participantId, t.occurredAt.desc()),
    index('events_type_time_idx').on(t.eventType, t.occurredAt.desc()),
    index('events_payload_idx').using('gin', t.payload),
  ],
);

/** Event taxonomy v1 — see MIGRATION_PLAN.md §6.4. */
export const EVENT_TYPES = [
  'app_opened',
  'app_backgrounded',
  'session_started',
  'session_ended',

  'consent_viewed',
  'consent_granted',
  'profile_completed',
  'walkthrough_completed',

  'sign_in_succeeded',
  'sign_in_failed',
  'sign_in_skipped',
  'sign_out',

  'test_started',
  'test_completed',
  'test_abandoned',
  'test_failed',

  'questionnaire_submitted',
  'medication_logged',
  'activity_logged',

  'collection_started',
  'collection_stopped',
  'permission_granted',
  'permission_denied',

  'ble_device_paired',
  'ble_device_disconnected',

  'upload_started',
  'upload_succeeded',
  'upload_failed',
  'profile_synced',

  'crash_reported',
  'background_task_ran',
] as const;

export type EventType = (typeof EVENT_TYPES)[number];
