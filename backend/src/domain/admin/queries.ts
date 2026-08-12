import { and, asc, count, desc, eq, gte, ilike, inArray, isNull, or, sql } from 'drizzle-orm';
import type { Database } from '../../db/client.js';
import { isUndefinedTable } from '../../db/errors.js';
import { migrationSteps } from '../../db/schema/bootstrap.js';
import { auditLog } from '../../db/schema/compliance.js';
import { events } from '../../db/schema/events.js';
import {
  authIdentities,
  consents,
  participantIdConflicts,
  participantProfiles,
  participants,
} from '../../db/schema/identity.js';
import { dailySummaries, testSessions } from '../../db/schema/results.js';
import {
  driveManifestExceptions,
  reconciliationRuns,
  uploads,
} from '../../db/schema/uploads.js';

/**
 * Every read the admin console makes. Kept out of the routes so the shape of the
 * data is reviewable in one place, and so no route can quietly widen a query to
 * return a column a role is not allowed to see.
 */

export interface Pagination {
  limit: number;
  offset: number;
}

export async function enrolmentOverview(database: Database) {
  const [byStatus, byProvider, testAccounts] = await Promise.all([
    database
      .select({ status: participants.status, count: count() })
      .from(participants)
      .groupBy(participants.status),
    database
      .select({ provider: authIdentities.provider, count: count() })
      .from(authIdentities)
      .groupBy(authIdentities.provider),
    database
      .select({ count: count() })
      .from(participants)
      .where(eq(participants.isTestAccount, true)),
  ]);

  const total = byStatus.reduce((sum, row) => sum + Number(row.count), 0);

  return {
    total,
    testAccounts: Number(testAccounts[0]?.count ?? 0),
    byStatus: Object.fromEntries(byStatus.map((row) => [row.status, Number(row.count)])),
    byProvider: Object.fromEntries(byProvider.map((row) => [row.provider, Number(row.count)])),
  };
}

export async function uploadOverview(database: Database) {
  const [byStatus, bySource, span, participantsWithUploads] = await Promise.all([
    database
      .select({ status: uploads.status, count: count(), bytes: sql<string>`coalesce(sum(${uploads.bytes}), 0)` })
      .from(uploads)
      .groupBy(uploads.status),
    database
      .select({ source: uploads.source, count: count() })
      .from(uploads)
      .groupBy(uploads.source),
    database
      .select({
        earliest: sql<string | null>`min(${uploads.collectionDate})`,
        latest: sql<string | null>`max(${uploads.collectionDate})`,
      })
      .from(uploads),
    database
      .select({ count: sql<string>`count(distinct ${uploads.participantId})` })
      .from(uploads),
  ]);

  return {
    total: byStatus.reduce((sum, row) => sum + Number(row.count), 0),
    bytes: byStatus.reduce((sum, row) => sum + Number(row.bytes), 0),
    byStatus: Object.fromEntries(byStatus.map((row) => [row.status, Number(row.count)])),
    bySource: Object.fromEntries(bySource.map((row) => [row.source, Number(row.count)])),
    participantsWithUploads: Number(participantsWithUploads[0]?.count ?? 0),
    earliestDate: span[0]?.earliest ?? null,
    latestDate: span[0]?.latest ?? null,
  };
}

/**
 * The counts that tell a reader whether the activity panels are empty because
 * nobody is active or because the pipeline has not run yet. Without this the
 * console cannot distinguish "no data" from "no ingestion", which is the most
 * likely misreading during the migration.
 */
export async function activityOverview(database: Database) {
  const [eventRows, sessionRows, summaryRows] = await Promise.all([
    database.select({ count: count() }).from(events),
    database.select({ count: count() }).from(testSessions),
    database.select({ count: count() }).from(dailySummaries),
  ]);

  return {
    events: Number(eventRows[0]?.count ?? 0),
    testSessions: Number(sessionRows[0]?.count ?? 0),
    dailySummaries: Number(summaryRows[0]?.count ?? 0),
  };
}

/**
 * `drive_manifest_exceptions` arrived in migration 0003, so a database that has
 * not been migrated that far would turn the whole overview into a 500. The count
 * degrades to "unavailable" instead, which the console reports as an out-of-date
 * schema — an empty list here would otherwise read as "the corpus is fully
 * accounted for", which is the opposite of the truth.
 */
export async function dataQualityOverview(database: Database) {
  const [conflicts, needsResolution] = await Promise.all([
    database
      .select({ count: count() })
      .from(participantIdConflicts)
      .where(isNull(participantIdConflicts.resolvedAt)),
    database
      .select({ count: count() })
      .from(participants)
      .where(eq(participants.status, 'needs_id_resolution')),
  ]);

  const base = {
    openConflicts: Number(conflicts[0]?.count ?? 0),
    participantsNeedingIdResolution: Number(needsResolution[0]?.count ?? 0),
  };

  try {
    const exceptions = await database
      .select({ reason: driveManifestExceptions.reason, count: count() })
      .from(driveManifestExceptions)
      .where(isNull(driveManifestExceptions.resolvedAt))
      .groupBy(driveManifestExceptions.reason);

    return {
      ...base,
      exceptionsAvailable: true,
      openExceptions: exceptions.reduce((sum, row) => sum + Number(row.count), 0),
      exceptionsByReason: Object.fromEntries(
        exceptions.map((row) => [row.reason, Number(row.count)]),
      ),
    };
  } catch (error) {
    if (!isUndefinedTable(error)) throw error;

    return {
      ...base,
      exceptionsAvailable: false,
      openExceptions: 0,
      exceptionsByReason: {},
    };
  }
}

export async function recentReconciliationRuns(database: Database, limit = 20) {
  return database
    .select({
      id: reconciliationRuns.id,
      runAt: reconciliationRuns.runAt,
      mode: reconciliationRuns.mode,
      status: reconciliationRuns.status,
      driveObjects: reconciliationRuns.driveObjects,
      driveBytes: reconciliationRuns.driveBytes,
      dbUploads: reconciliationRuns.dbUploads,
      dbParsed: reconciliationRuns.dbParsed,
    })
    .from(reconciliationRuns)
    .orderBy(desc(reconciliationRuns.runAt))
    .limit(limit);
}

export async function bootstrapLedger(database: Database) {
  return database
    .select({
      name: migrationSteps.name,
      status: migrationSteps.status,
      rowsWritten: migrationSteps.rowsWritten,
      attempts: migrationSteps.attempts,
      startedAt: migrationSteps.startedAt,
      completedAt: migrationSteps.completedAt,
      durationMs: migrationSteps.durationMs,
      error: migrationSteps.error,
    })
    .from(migrationSteps)
    .orderBy(asc(migrationSteps.startedAt));
}

export interface ParticipantListFilter extends Pagination {
  search?: string | undefined;
  status?: string | undefined;
  includeTestAccounts: boolean;
}

/**
 * One row per participant with their upload span, in a single query. Doing it
 * per participant would be 43 round trips today and worse later; the lateral
 * join keeps it to one.
 */
export async function listParticipants(database: Database, filter: ParticipantListFilter) {
  const conditions = [];

  if (!filter.includeTestAccounts) conditions.push(eq(participants.isTestAccount, false));
  if (filter.status) conditions.push(eq(participants.status, filter.status));
  if (filter.search) {
    const pattern = `%${filter.search}%`;
    conditions.push(
      or(
        ilike(participants.participantCode, pattern),
        ilike(authIdentities.email, pattern),
        ilike(authIdentities.displayName, pattern),
        sql`exists (
          select 1 from unnest(${participants.legacyFileUserIds}) as legacy(code)
          where legacy.code ilike ${pattern}
        )`,
      ),
    );
  }

  const where = conditions.length > 0 ? and(...conditions) : undefined;

  // Held in a fragment because it is both selected and ordered by. A bare
  // `order by last_upload_date` would reference a select alias that never reaches
  // PostgreSQL, since drizzle does not name raw subqueries in the projection.
  const lastUploadDate = sql<string | null>`(
    select max(${uploads.collectionDate}) from ${uploads}
    where ${uploads.participantId} = ${participants.id}
  )`;

  const rows = await database
    .select({
      id: participants.id,
      participantCode: participants.participantCode,
      status: participants.status,
      cohort: participants.cohort,
      isTestAccount: participants.isTestAccount,
      enrolledAt: participants.enrolledAt,
      legacyFileUserIds: participants.legacyFileUserIds,
      email: authIdentities.email,
      displayName: authIdentities.displayName,
      firebaseUid: authIdentities.firebaseUid,
      provider: authIdentities.provider,
      lastSignInAt: authIdentities.lastSignInAt,
      uploadCount: sql<string>`(
        select count(*) from ${uploads} where ${uploads.participantId} = ${participants.id}
      )`,
      lastUploadDate,
      firstUploadDate: sql<string | null>`(
        select min(${uploads.collectionDate}) from ${uploads}
        where ${uploads.participantId} = ${participants.id}
      )`,
      hasProfile: sql<boolean>`exists (
        select 1 from ${participantProfiles}
        where ${participantProfiles.participantId} = ${participants.id}
      )`,
    })
    .from(participants)
    .leftJoin(authIdentities, eq(authIdentities.participantId, participants.id))
    .where(where)
    .orderBy(sql`${lastUploadDate} desc nulls last`, asc(participants.participantCode))
    .limit(filter.limit)
    .offset(filter.offset);

  const [totals] = await database
    .select({ count: sql<string>`count(distinct ${participants.id})` })
    .from(participants)
    .leftJoin(authIdentities, eq(authIdentities.participantId, participants.id))
    .where(where);

  return {
    total: Number(totals?.count ?? 0),
    rows: rows.map((row) => ({
      ...row,
      uploadCount: Number(row.uploadCount),
    })),
  };
}

export async function findParticipant(database: Database, participantId: string) {
  const [participant] = await database
    .select({
      id: participants.id,
      participantCode: participants.participantCode,
      status: participants.status,
      cohort: participants.cohort,
      isTestAccount: participants.isTestAccount,
      legacyFileUserIds: participants.legacyFileUserIds,
      enrolledAt: participants.enrolledAt,
      createdAt: participants.createdAt,
    })
    .from(participants)
    .where(eq(participants.id, participantId));

  return participant;
}

export async function participantIdentities(database: Database, participantId: string) {
  return database
    .select({
      provider: authIdentities.provider,
      email: authIdentities.email,
      emailVerified: authIdentities.emailVerified,
      displayName: authIdentities.displayName,
      firebaseUid: authIdentities.firebaseUid,
      createdAt: authIdentities.createdAt,
      lastSignInAt: authIdentities.lastSignInAt,
    })
    .from(authIdentities)
    .where(eq(authIdentities.participantId, participantId));
}

export async function participantProfile(database: Database, participantId: string) {
  const [profile] = await database
    .select({
      revision: participantProfiles.revision,
      age: participantProfiles.age,
      gender: participantProfiles.gender,
      dominantHand: participantProfiles.dominantHand,
      affectedSide: participantProfiles.affectedSide,
      medications: participantProfiles.medications,
      updatedAt: participantProfiles.updatedAt,
    })
    .from(participantProfiles)
    .where(eq(participantProfiles.participantId, participantId));

  return profile;
}

export async function participantConsents(database: Database, participantId: string) {
  return database
    .select({
      documentVersion: consents.documentVersion,
      signatureName: consents.signatureName,
      grantedAt: consents.grantedAt,
      revokedAt: consents.revokedAt,
      platform: consents.platform,
      appVersion: consents.appVersion,
    })
    .from(consents)
    .where(eq(consents.participantId, participantId))
    .orderBy(desc(consents.grantedAt));
}

export async function participantUploads(database: Database, participantId: string) {
  return database
    .select({
      id: uploads.id,
      collectionDate: uploads.collectionDate,
      platform: uploads.platform,
      status: uploads.status,
      source: uploads.source,
      filename: uploads.filename,
      bytes: uploads.bytes,
      receivedAt: uploads.receivedAt,
      parsedAt: uploads.parsedAt,
      error: uploads.error,
    })
    .from(uploads)
    .where(eq(uploads.participantId, participantId))
    .orderBy(desc(uploads.collectionDate));
}

export async function participantEvents(database: Database, participantId: string, limit = 200) {
  return database
    .select({
      occurredAt: events.occurredAt,
      receivedAt: events.receivedAt,
      eventType: events.eventType,
      appVersion: events.appVersion,
      payload: events.payload,
    })
    .from(events)
    .where(eq(events.participantId, participantId))
    .orderBy(desc(events.occurredAt))
    .limit(limit);
}

export async function participantTestSessions(
  database: Database,
  participantId: string,
  limit = 200,
) {
  return database
    .select({
      testType: testSessions.testType,
      startedAt: testSessions.startedAt,
      durationMs: testSessions.durationMs,
      side: testSessions.side,
      completed: testSessions.completed,
      metrics: testSessions.metrics,
    })
    .from(testSessions)
    .where(eq(testSessions.participantId, participantId))
    .orderBy(desc(testSessions.startedAt))
    .limit(limit);
}

export async function participantDailySummaries(
  database: Database,
  participantId: string,
  limit = 120,
) {
  return database
    .select({ day: dailySummaries.day, metrics: dailySummaries.metrics })
    .from(dailySummaries)
    .where(eq(dailySummaries.participantId, participantId))
    .orderBy(desc(dailySummaries.day))
    .limit(limit);
}

export interface UploadFeedFilter extends Pagination {
  status?: string | undefined;
  since?: string | undefined;
}

export async function uploadFeed(database: Database, filter: UploadFeedFilter) {
  const conditions = [];
  if (filter.status) conditions.push(eq(uploads.status, filter.status));
  if (filter.since) conditions.push(gte(uploads.collectionDate, filter.since));

  return database
    .select({
      id: uploads.id,
      participantId: uploads.participantId,
      participantCode: participants.participantCode,
      collectionDate: uploads.collectionDate,
      platform: uploads.platform,
      status: uploads.status,
      source: uploads.source,
      bytes: uploads.bytes,
      filename: uploads.filename,
      error: uploads.error,
    })
    .from(uploads)
    .innerJoin(participants, eq(participants.id, uploads.participantId))
    .where(conditions.length > 0 ? and(...conditions) : undefined)
    .orderBy(desc(uploads.collectionDate), asc(participants.participantCode))
    .limit(filter.limit)
    .offset(filter.offset);
}

/** Coverage grid: one row per collection date with how many participants uploaded. */
export async function uploadCoverageByDay(database: Database, since?: string) {
  return database
    .select({
      collectionDate: uploads.collectionDate,
      platform: uploads.platform,
      participants: sql<string>`count(distinct ${uploads.participantId})`,
      uploads: count(),
      bytes: sql<string>`coalesce(sum(${uploads.bytes}), 0)`,
    })
    .from(uploads)
    .where(since ? gte(uploads.collectionDate, since) : undefined)
    .groupBy(uploads.collectionDate, uploads.platform)
    .orderBy(desc(uploads.collectionDate));
}

export async function openParticipantIdConflicts(database: Database) {
  const rows = await database
    .select({
      id: participantIdConflicts.id,
      legacyCode: participantIdConflicts.legacyCode,
      participantIds: participantIdConflicts.participantIds,
      firebaseUids: participantIdConflicts.firebaseUids,
      detectedAt: participantIdConflicts.detectedAt,
      resolvedAt: participantIdConflicts.resolvedAt,
      resolutionNote: participantIdConflicts.resolutionNote,
    })
    .from(participantIdConflicts)
    .orderBy(asc(participantIdConflicts.resolvedAt), desc(participantIdConflicts.detectedAt));

  const ids = rows.flatMap((row) => row.participantIds);
  const codes =
    ids.length === 0
      ? []
      : await database
          .select({ id: participants.id, participantCode: participants.participantCode })
          .from(participants)
          .where(inArray(participants.id, ids));

  const byId = new Map(codes.map((row) => [row.id, row.participantCode]));

  return rows.map((row) => ({
    ...row,
    participantCodes: row.participantIds.map((id) => byId.get(id) ?? id),
  }));
}

export async function driveExceptions(database: Database, includeResolved: boolean) {
  return database
    .select({
      id: driveManifestExceptions.id,
      driveFileId: driveManifestExceptions.driveFileId,
      filename: driveManifestExceptions.filename,
      bytes: driveManifestExceptions.bytes,
      reason: driveManifestExceptions.reason,
      detail: driveManifestExceptions.detail,
      firstSeenAt: driveManifestExceptions.firstSeenAt,
      resolvedAt: driveManifestExceptions.resolvedAt,
      resolutionNote: driveManifestExceptions.resolutionNote,
    })
    .from(driveManifestExceptions)
    .where(includeResolved ? undefined : isNull(driveManifestExceptions.resolvedAt))
    .orderBy(desc(driveManifestExceptions.firstSeenAt));
}

export interface AuditFilter extends Pagination {
  subject?: string | undefined;
  actorId?: string | undefined;
}

export async function auditEntries(database: Database, filter: AuditFilter) {
  const conditions = [];
  if (filter.subject) conditions.push(eq(auditLog.subject, filter.subject));
  if (filter.actorId) conditions.push(eq(auditLog.actorId, filter.actorId));

  return database
    .select({
      id: auditLog.id,
      actorType: auditLog.actorType,
      actorId: auditLog.actorId,
      action: auditLog.action,
      subject: auditLog.subject,
      occurredAt: auditLog.occurredAt,
      metadata: auditLog.metadata,
    })
    .from(auditLog)
    .where(conditions.length > 0 ? and(...conditions) : undefined)
    .orderBy(desc(auditLog.occurredAt))
    .limit(filter.limit)
    .offset(filter.offset);
}
