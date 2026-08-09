import {
  bigserial,
  boolean,
  index,
  jsonb,
  pgTable,
  text,
  timestamp,
  uuid,
} from 'drizzle-orm/pg-core';

export const staffUsers = pgTable(
  'staff_users',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    email: text('email').notNull().unique(),
    displayName: text('display_name'),
    role: text('role').notNull().default('viewer'), // viewer | researcher | admin
    active: boolean('active').notNull().default(true),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
    lastSeenAt: timestamp('last_seen_at', { withTimezone: true }),
  },
  (t) => [index('staff_users_role_idx').on(t.role)],
);

/**
 * Every staff read of participant data is recorded. Required for the study's
 * ethics approval, and the basis for answering "who looked at this participant's
 * data and when".
 */
export const auditLog = pgTable(
  'audit_log',
  {
    id: bigserial('id', { mode: 'bigint' }).primaryKey(),
    actorType: text('actor_type').notNull(), // staff | participant | system
    actorId: text('actor_id'),
    action: text('action').notNull(),
    subject: text('subject'),
    occurredAt: timestamp('occurred_at', { withTimezone: true }).notNull().defaultNow(),
    metadata: jsonb('metadata'),
  },
  (t) => [
    index('audit_log_occurred_idx').on(t.occurredAt),
    index('audit_log_actor_idx').on(t.actorType, t.actorId),
    index('audit_log_subject_idx').on(t.subject),
  ],
);
