import { sql } from 'drizzle-orm';
import {
  boolean,
  date,
  doublePrecision,
  index,
  integer,
  jsonb,
  pgTable,
  primaryKey,
  text,
  timestamp,
  unique,
  uuid,
} from 'drizzle-orm/pg-core';
import { participants } from './identity.js';
import { devices, uploads } from './uploads.js';

/** One row per motor or cognitive test a participant actually performed. */
export const testSessions = pgTable(
  'test_sessions',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    participantId: uuid('participant_id')
      .notNull()
      .references(() => participants.id),
    deviceId: uuid('device_id').references(() => devices.id),
    uploadId: uuid('upload_id').references(() => uploads.id),
    testType: text('test_type').notNull(),
    startedAt: timestamp('started_at', { withTimezone: true }).notNull(),
    endedAt: timestamp('ended_at', { withTimezone: true }),
    durationMs: integer('duration_ms'),
    side: text('side'),
    dominantHand: text('dominant_hand'),
    affectedSide: text('affected_side'),
    completed: boolean('completed').notNull().default(false),
    metrics: jsonb('metrics').notNull().default(sql`'{}'::jsonb`),
    rawObjectKey: text('raw_object_key'),
  },
  (t) => [
    unique('test_sessions_natural_key').on(t.participantId, t.testType, t.startedAt),
    index('test_sessions_participant_time_idx').on(t.participantId, t.startedAt.desc()),
    index('test_sessions_type_idx').on(t.testType),
  ],
);

export const TEST_TYPES = [
  'finger_tapping',
  'fingers_test',
  'hand_turning',
  'leg_agility',
  'spiral_tracing',
  'tmt',
  'facial_movement',
  'voice_test',
  'voice_sample',
] as const;

export type TestType = (typeof TEST_TYPES)[number];

/** Flattened metrics for trend queries; `metrics` jsonb keeps the full payload. */
export const testMetrics = pgTable(
  'test_metrics',
  {
    sessionId: uuid('session_id')
      .notNull()
      .references(() => testSessions.id, { onDelete: 'cascade' }),
    metricKey: text('metric_key').notNull(),
    metricValue: doublePrecision('metric_value'),
  },
  (t) => [
    primaryKey({ columns: [t.sessionId, t.metricKey] }),
    index('test_metrics_key_idx').on(t.metricKey),
  ],
);

export const questionnaireResponses = pgTable(
  'questionnaire_responses',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    participantId: uuid('participant_id')
      .notNull()
      .references(() => participants.id),
    uploadId: uuid('upload_id').references(() => uploads.id),
    submittedAt: timestamp('submitted_at', { withTimezone: true }).notNull(),
    answers: jsonb('answers').notNull().default(sql`'{}'::jsonb`),
  },
  (t) => [
    unique('questionnaire_natural_key').on(t.participantId, t.submittedAt),
    index('questionnaire_participant_idx').on(t.participantId, t.submittedAt.desc()),
  ],
);

export const medicationLogs = pgTable(
  'medication_logs',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    participantId: uuid('participant_id')
      .notNull()
      .references(() => participants.id),
    uploadId: uuid('upload_id').references(() => uploads.id),
    takenAt: timestamp('taken_at', { withTimezone: true }).notNull(),
    medicationName: text('medication_name'),
    dosage: text('dosage'),
  },
  (t) => [
    unique('medication_logs_natural_key').on(t.participantId, t.takenAt, t.medicationName),
    index('medication_logs_participant_idx').on(t.participantId, t.takenAt.desc()),
  ],
);

export const physicalActivityLogs = pgTable(
  'physical_activity_logs',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    participantId: uuid('participant_id')
      .notNull()
      .references(() => participants.id),
    uploadId: uuid('upload_id').references(() => uploads.id),
    startedAt: timestamp('started_at', { withTimezone: true }).notNull(),
    activityType: text('activity_type'),
    timeOfDay: text('time_of_day'),
    source: text('source'), // manual | healthkit | health_connect | strava
    externalId: text('external_id'),
    durationMin: doublePrecision('duration_min'),
    calories: doublePrecision('calories'),
    avgHeartRate: doublePrecision('avg_heart_rate'),
  },
  (t) => [
    unique('physical_activity_natural_key').on(t.participantId, t.startedAt, t.source),
    index('physical_activity_participant_idx').on(t.participantId, t.startedAt.desc()),
  ],
);

export const sleepLogs = pgTable(
  'sleep_logs',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    participantId: uuid('participant_id')
      .notNull()
      .references(() => participants.id),
    uploadId: uuid('upload_id').references(() => uploads.id),
    sleepStart: timestamp('sleep_start', { withTimezone: true }).notNull(),
    sleepEnd: timestamp('sleep_end', { withTimezone: true }),
    source: text('source'),
    provider: text('provider'),
    stageMinutes: jsonb('stage_minutes').notNull().default(sql`'{}'::jsonb`),
  },
  (t) => [
    unique('sleep_logs_natural_key').on(t.participantId, t.sleepStart, t.source),
    index('sleep_logs_participant_idx').on(t.participantId, t.sleepStart.desc()),
  ],
);

export const heartRateSummaries = pgTable(
  'heart_rate_summaries',
  {
    participantId: uuid('participant_id')
      .notNull()
      .references(() => participants.id),
    day: date('day').notNull(),
    samples: integer('samples').notNull().default(0),
    bpmMin: doublePrecision('bpm_min'),
    bpmMax: doublePrecision('bpm_max'),
    bpmAvg: doublePrecision('bpm_avg'),
    rrSdnnMs: doublePrecision('rr_sdnn_ms'),
  },
  (t) => [primaryKey({ columns: [t.participantId, t.day] })],
);

/**
 * Replaces the Firestore `dashboardMetrics` map, which already silently fails
 * to sync for long-running participants once the document exceeds Firestore's
 * 1 MiB cap. There is no equivalent limit here.
 */
export const dailySummaries = pgTable(
  'daily_summaries',
  {
    participantId: uuid('participant_id')
      .notNull()
      .references(() => participants.id),
    day: date('day').notNull(),
    metrics: jsonb('metrics').notNull().default(sql`'{}'::jsonb`),
    computedAt: timestamp('computed_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    primaryKey({ columns: [t.participantId, t.day] }),
    index('daily_summaries_day_idx').on(t.day),
  ],
);
