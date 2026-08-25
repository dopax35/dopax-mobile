import { createHash } from 'node:crypto';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { eq, inArray, sql } from 'drizzle-orm';
import type { Database } from '../../db/client.js';
import {
  heartRateSummaries,
  medicationLogs,
  physicalActivityLogs,
  questionnaireResponses,
  sleepLogs,
  testSessions,
} from '../../db/schema/results.js';
import { uploadFiles, uploads } from '../../db/schema/uploads.js';
import { downloadDriveFile } from '../../infra/drive/download.js';
import { parseUploadZipFile } from '../drive/parse-upload-zip.js';
import { unambiguousSessionPaths, type ZipParsePlan } from '../drive/zip-parse.js';

export interface UploadToParse {
  id: string;
  participantId: string;
  collectionDate: string;
  legacyDriveFileId: string;
  filename: string;
  bytes: number | null;
  status: string;
}

export async function listUploadsNeedingParse(
  database: Database,
  options?: { limit?: number; maxBytes?: number },
): Promise<UploadToParse[]> {
  const rows = await database
    .select({
      id: uploads.id,
      participantId: uploads.participantId,
      collectionDate: uploads.collectionDate,
      legacyDriveFileId: uploads.legacyDriveFileId,
      filename: uploads.filename,
      bytes: uploads.bytes,
      status: uploads.status,
    })
    .from(uploads)
    .where(inArray(uploads.status, ['stored', 'failed']))
    .orderBy(uploads.bytes);

  const filtered = rows.filter(
    (row): row is UploadToParse & { legacyDriveFileId: string } =>
      typeof row.legacyDriveFileId === 'string' && row.legacyDriveFileId.length > 0,
  );

  const sized =
    options?.maxBytes === undefined
      ? filtered
      : filtered.filter((row) => (row.bytes ?? 0) <= options.maxBytes!);

  return options?.limit === undefined ? sized : sized.slice(0, options.limit);
}

export async function checksumPendingUploads(database: Database): Promise<string> {
  const rows = await database
    .select({
      id: uploads.id,
      status: uploads.status,
      fileId: uploads.legacyDriveFileId,
    })
    .from(uploads)
    .where(sql`${uploads.legacyDriveFileId} is not null`);

  const material = rows
    .map((row) => `${row.id}:${row.status}:${row.fileId}`)
    .sort()
    .join('\n');

  return createHash('sha256').update(material).digest('hex');
}

async function applyPlan(
  database: Database,
  upload: UploadToParse,
  plan: ZipParsePlan,
): Promise<number> {
  let written = 0;

  await database.transaction(async (tx) => {
    await tx.delete(uploadFiles).where(eq(uploadFiles.uploadId, upload.id));

    const linkable = unambiguousSessionPaths(plan.sessions);
    const sessionByPath = new Map<string, string>();

    // Sessions are written before files so a file can point at one.
    for (const session of plan.sessions) {
      const [row] = await tx
        .insert(testSessions)
        .values({
          participantId: upload.participantId,
          uploadId: upload.id,
          testType: session.testType,
          startedAt: session.startedAt,
          endedAt: session.endedAt,
          durationMs: session.durationMs,
          side: session.side,
          dominantHand: session.dominantHand,
          affectedSide: session.affectedSide,
          completed: session.completed,
          metrics: session.metrics,
          rawObjectKey: session.rawObjectKey,
        })
        .onConflictDoUpdate({
          target: [testSessions.participantId, testSessions.testType, testSessions.startedAt],
          set: {
            uploadId: upload.id,
            endedAt: session.endedAt,
            durationMs: session.durationMs,
            side: session.side,
            dominantHand: session.dominantHand,
            affectedSide: session.affectedSide,
            completed: session.completed,
            metrics: session.metrics,
            rawObjectKey: session.rawObjectKey,
          },
        })
        .returning({ id: testSessions.id });

      if (row && linkable.has(session.rawObjectKey)) {
        sessionByPath.set(session.rawObjectKey, row.id);
      }
      written += 1;
    }

    if (plan.files.length > 0) {
      await tx.insert(uploadFiles).values(
        plan.files.map((file) => ({
          uploadId: upload.id,
          pathInZip: file.pathInZip,
          kind: file.kind,
          rowCount: file.rowCount,
          bytes: file.bytes,
          capturedAt: file.capturedAt,
          qualityStatus: file.qualityStatus,
          qualityFlags: file.qualityFlags,
          sessionId: sessionByPath.get(file.pathInZip) ?? null,
        })),
      );
      written += plan.files.length;
    }

    for (const row of plan.questionnaires) {
      await tx
        .insert(questionnaireResponses)
        .values({
          participantId: upload.participantId,
          uploadId: upload.id,
          submittedAt: row.submittedAt,
          answers: row.answers,
        })
        .onConflictDoUpdate({
          target: [questionnaireResponses.participantId, questionnaireResponses.submittedAt],
          set: { uploadId: upload.id, answers: row.answers },
        });
      written += 1;
    }

    for (const row of plan.medications) {
      await tx
        .insert(medicationLogs)
        .values({
          participantId: upload.participantId,
          uploadId: upload.id,
          takenAt: row.takenAt,
          medicationName: row.medicationName,
          dosage: row.dosage,
        })
        .onConflictDoUpdate({
          target: [
            medicationLogs.participantId,
            medicationLogs.takenAt,
            medicationLogs.medicationName,
          ],
          set: { uploadId: upload.id, dosage: row.dosage },
        });
      written += 1;
    }

    for (const row of plan.activities) {
      await tx
        .insert(physicalActivityLogs)
        .values({
          participantId: upload.participantId,
          uploadId: upload.id,
          startedAt: row.startedAt,
          activityType: row.activityType,
          timeOfDay: row.timeOfDay,
          source: row.source,
          durationMin: row.durationMin,
          calories: row.calories,
          avgHeartRate: row.avgHeartRate,
        })
        .onConflictDoUpdate({
          target: [
            physicalActivityLogs.participantId,
            physicalActivityLogs.startedAt,
            physicalActivityLogs.source,
          ],
          set: {
            uploadId: upload.id,
            activityType: row.activityType,
            durationMin: row.durationMin,
            calories: row.calories,
            avgHeartRate: row.avgHeartRate,
          },
        });
      written += 1;
    }

    for (const row of plan.sleeps) {
      await tx
        .insert(sleepLogs)
        .values({
          participantId: upload.participantId,
          uploadId: upload.id,
          sleepStart: row.sleepStart,
          sleepEnd: row.sleepEnd,
          source: row.source,
          provider: row.provider,
          stageMinutes: row.stageMinutes,
        })
        .onConflictDoUpdate({
          target: [sleepLogs.participantId, sleepLogs.sleepStart, sleepLogs.source],
          set: {
            uploadId: upload.id,
            sleepEnd: row.sleepEnd,
            provider: row.provider,
            stageMinutes: row.stageMinutes,
          },
        });
      written += 1;
    }

    for (const row of plan.heartRateSummaries) {
      await tx
        .insert(heartRateSummaries)
        .values({
          participantId: upload.participantId,
          day: row.day,
          samples: row.samples,
          bpmMin: row.bpmMin,
          bpmMax: row.bpmMax,
          bpmAvg: row.bpmAvg,
        })
        .onConflictDoUpdate({
          target: [heartRateSummaries.participantId, heartRateSummaries.day],
          set: {
            samples: row.samples,
            bpmMin: row.bpmMin,
            bpmMax: row.bpmMax,
            bpmAvg: row.bpmAvg,
          },
        });
      written += 1;
    }

    await tx
      .update(uploads)
      .set({ status: 'parsed', parsedAt: new Date(), error: null })
      .where(eq(uploads.id, upload.id));
  });

  return written;
}

export async function parseOneUpload(
  database: Database,
  upload: UploadToParse,
): Promise<{ rowsWritten: number; plan: ZipParsePlan }> {
  const dir = mkdtempSync(join(tmpdir(), 'dopax-zip-'));
  const zipPath = join(dir, `${upload.id}.zip`);

  try {
    await database
      .update(uploads)
      .set({ status: 'parsing', error: null })
      .where(eq(uploads.id, upload.id));

    await downloadDriveFile(upload.legacyDriveFileId, zipPath);
    const plan = await parseUploadZipFile(zipPath, upload.collectionDate);
    const rowsWritten = await applyPlan(database, upload, plan);
    return { rowsWritten, plan };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await database
      .update(uploads)
      .set({ status: 'failed', error: message.slice(0, 2000) })
      .where(eq(uploads.id, upload.id));
    throw error;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

export async function parsePendingUploads(
  database: Database,
  options?: {
    limit?: number;
    maxBytes?: number;
    onProgress?: (info: {
      index: number;
      total: number;
      upload: UploadToParse;
      rowsWritten: number;
    }) => void;
  },
): Promise<{ parsed: number; failed: number; rowsWritten: number }> {
  const pending = await listUploadsNeedingParse(database, options);
  let parsed = 0;
  let failed = 0;
  let rowsWritten = 0;

  for (const [index, upload] of pending.entries()) {
    try {
      const result = await parseOneUpload(database, upload);
      parsed += 1;
      rowsWritten += result.rowsWritten;
      options?.onProgress?.({
        index: index + 1,
        total: pending.length,
        upload,
        rowsWritten: result.rowsWritten,
      });
    } catch {
      failed += 1;
      options?.onProgress?.({
        index: index + 1,
        total: pending.length,
        upload,
        rowsWritten: 0,
      });
    }
  }

  return { parsed, failed, rowsWritten };
}

export async function verifyZipParse(database: Database): Promise<void> {
  const [row] = await database
    .select({
      stored: sql<number>`(select count(*)::int from uploads where status = 'stored')`,
      parsing: sql<number>`(select count(*)::int from uploads where status = 'parsing')`,
      failed: sql<number>`(select count(*)::int from uploads where status = 'failed')`,
      parsed: sql<number>`(select count(*)::int from uploads where status = 'parsed')`,
    })
    .from(sql`(select 1) as _`);

  // A run may intentionally leave large ZIPs for a later pass (maxBytes). Only
  // fail when something is stuck mid-parse.
  if ((row?.parsing ?? 0) > 0) {
    throw new Error(`${row!.parsing} uploads stuck in status=parsing`);
  }

  void row?.stored;
  void row?.failed;
  void row?.parsed;
}
