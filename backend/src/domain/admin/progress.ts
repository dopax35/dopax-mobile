import { desc, eq, inArray } from 'drizzle-orm';
import type { Database } from '../../db/client.js';
import { authIdentities, participants } from '../../db/schema/identity.js';
import { medicationLogs, testSessions } from '../../db/schema/results.js';
import { uploads } from '../../db/schema/uploads.js';

export interface ParticipantProgressItem {
  participantId: string;
  participantCode: string;
  legacyFileUserIds: string[];
  status: string;
  isTestAccount: boolean;
  email: string | null;
  displayName: string | null;
  firebaseUid: string | null;
  platform: string;
  uploadCount: number;
  totalBytes: number;
  latestUploadDate: string | null;
  complianceStatus: 'proper_usage' | 'improper_usage';
  complianceReason: string;
  hasSensorData: boolean;
  hasActivityData: boolean;
  integrityStatus: 'healthy' | 'missing_sensor_data' | 'missing_activity_data' | 'no_uploads';
  integrityAlerts: string[];
  medicationStatus: 'logged' | 'none_reported';
  activeTestDates: { date: string; testTypes: string[]; totalCompleted: number }[];
  dailyLoads: { collectionDate: string; bytes: number; filename: string; passed: boolean }[];
  medicationReports: { date: string; medicationName: string | null; dosage: string | null }[];
}

export interface ProgressSummary {
  totalRegistered: number;
  compliantCount: number;
  nonCompliantCount: number;
  activeTestUserCount: number;
  integrityAlertCount: number;
  medicationReportCount: number;
  participants: ParticipantProgressItem[];
}

const TEN_MB = 10 * 1024 * 1024;

export async function getActiveUserProgressSummary(
  database: Database,
  includeTestAccounts = false,
): Promise<ProgressSummary> {
  const pRows = await database
    .select({
      id: participants.id,
      participantCode: participants.participantCode,
      legacyFileUserIds: participants.legacyFileUserIds,
      status: participants.status,
      isTestAccount: participants.isTestAccount,
      email: authIdentities.email,
      displayName: authIdentities.displayName,
      firebaseUid: authIdentities.firebaseUid,
      provider: authIdentities.provider,
    })
    .from(participants)
    .leftJoin(authIdentities, eq(authIdentities.participantId, participants.id))
    .where(includeTestAccounts ? undefined : eq(participants.isTestAccount, false));

  const participantIds = pRows.map((p) => p.id);

  if (participantIds.length === 0) {
    return {
      totalRegistered: 0,
      compliantCount: 0,
      nonCompliantCount: 0,
      activeTestUserCount: 0,
      integrityAlertCount: 0,
      medicationReportCount: 0,
      participants: [],
    };
  }

  // Query uploads, active test sessions, and medication logs
  const [allUploads, allSessions, allMeds] = await Promise.all([
    database
      .select({
        id: uploads.id,
        participantId: uploads.participantId,
        collectionDate: uploads.collectionDate,
        platform: uploads.platform,
        bytes: uploads.bytes,
        filename: uploads.filename,
        status: uploads.status,
      })
      .from(uploads)
      .where(inArray(uploads.participantId, participantIds))
      .orderBy(desc(uploads.collectionDate)),

    database
      .select({
        participantId: testSessions.participantId,
        testType: testSessions.testType,
        startedAt: testSessions.startedAt,
        completed: testSessions.completed,
      })
      .from(testSessions)
      .where(inArray(testSessions.participantId, participantIds))
      .orderBy(desc(testSessions.startedAt)),

    database
      .select({
        participantId: medicationLogs.participantId,
        takenAt: medicationLogs.takenAt,
        medicationName: medicationLogs.medicationName,
        dosage: medicationLogs.dosage,
      })
      .from(medicationLogs)
      .where(inArray(medicationLogs.participantId, participantIds))
      .orderBy(desc(medicationLogs.takenAt)),
  ]);

  // Group uploads by participantId
  const uploadsByP = new Map<string, typeof allUploads>();
  for (const u of allUploads) {
    const list = uploadsByP.get(u.participantId) ?? [];
    list.push(u);
    uploadsByP.set(u.participantId, list);
  }

  // Group sessions by participantId
  const sessionsByP = new Map<string, typeof allSessions>();
  for (const s of allSessions) {
    const list = sessionsByP.get(s.participantId) ?? [];
    list.push(s);
    sessionsByP.set(s.participantId, list);
  }

  // Group medications by participantId
  const medsByP = new Map<string, typeof allMeds>();
  for (const m of allMeds) {
    const list = medsByP.get(m.participantId) ?? [];
    list.push(m);
    medsByP.set(m.participantId, list);
  }

  let compliantCount = 0;
  let nonCompliantCount = 0;
  let activeTestUserCount = 0;
  let integrityAlertCount = 0;
  let medicationReportCount = 0;

  const resultItems: ParticipantProgressItem[] = pRows.map((p) => {
    const pUploads = uploadsByP.get(p.id) ?? [];
    const pSessions = sessionsByP.get(p.id) ?? [];
    const pMeds = medsByP.get(p.id) ?? [];

    const inferredPlatform = (pUploads[0]?.platform ?? 'android').toLowerCase();
    const totalBytes = pUploads.reduce((sum, u) => sum + (u.bytes ?? 0), 0);
    const latestUploadDate = pUploads[0]?.collectionDate ?? null;

    // Daily loads
    const dailyLoads = pUploads.map((u) => {
      const bytes = u.bytes ?? 0;
      const passed =
        inferredPlatform === 'ios' || inferredPlatform === 'iphone' ? bytes > 0 : bytes > TEN_MB;
      return {
        collectionDate: u.collectionDate,
        bytes,
        filename: u.filename,
        passed,
      };
    });

    // Determine overall compliance
    let complianceStatus: 'proper_usage' | 'improper_usage' = 'improper_usage';
    let complianceReason = 'No Uploads Recorded';

    if (pUploads.length > 0) {
      if (inferredPlatform === 'ios' || inferredPlatform === 'iphone') {
        complianceStatus = 'proper_usage';
        complianceReason = 'File Present (iPhone)';
      } else {
        const maxDailyBytes = Math.max(...pUploads.map((u) => u.bytes ?? 0), 0);
        if (maxDailyBytes > TEN_MB) {
          complianceStatus = 'proper_usage';
          complianceReason = `Daily Load > 10MB (${(maxDailyBytes / (1024 * 1024)).toFixed(1)}MB)`;
        } else {
          complianceStatus = 'improper_usage';
          complianceReason = `Daily Load Under 10MB (${(maxDailyBytes / (1024 * 1024)).toFixed(1)}MB)`;
        }
      }
    }

    if (complianceStatus === 'proper_usage') compliantCount++;
    else nonCompliantCount++;

    // Data Integrity
    const hasSensorData = pUploads.length > 0;
    const hasActivityData = pSessions.length > 0 || pUploads.length > 0;
    const integrityAlerts: string[] = [];

    if (pUploads.length === 0) integrityAlerts.push('No Data Uploaded');
    if (!hasSensorData) integrityAlerts.push('Missing Sensor Data');
    if (!hasActivityData) integrityAlerts.push('Missing Activity Data');

    let integrityStatus: 'healthy' | 'missing_sensor_data' | 'missing_activity_data' | 'no_uploads' =
      'healthy';

    if (pUploads.length === 0) integrityStatus = 'no_uploads';
    else if (!hasSensorData) integrityStatus = 'missing_sensor_data';
    else if (!hasActivityData) integrityStatus = 'missing_activity_data';

    if (integrityAlerts.length > 0) integrityAlertCount++;

    // Active test dates matrix
    if (pSessions.length > 0) activeTestUserCount++;

    const sessionDatesMap = new Map<string, Set<string>>();
    for (const s of pSessions) {
      const dateStr = s.startedAt.toISOString().slice(0, 10);
      const set = sessionDatesMap.get(dateStr) ?? new Set<string>();
      set.add(s.testType);
      sessionDatesMap.set(dateStr, set);
    }

    const activeTestDates = Array.from(sessionDatesMap.entries()).map(([date, testSet]) => ({
      date,
      testTypes: Array.from(testSet),
      totalCompleted: testSet.size,
    }));

    // Medication reporting
    if (pMeds.length > 0) medicationReportCount++;

    const medicationReports = pMeds.map((m) => ({
      date: m.takenAt.toISOString().slice(0, 10),
      medicationName: m.medicationName,
      dosage: m.dosage,
    }));

    return {
      participantId: p.id,
      participantCode: p.participantCode,
      legacyFileUserIds: p.legacyFileUserIds,
      status: p.status,
      isTestAccount: p.isTestAccount,
      email: p.email,
      displayName: p.displayName,
      firebaseUid: p.firebaseUid,
      platform: inferredPlatform,
      uploadCount: pUploads.length,
      totalBytes,
      latestUploadDate,
      complianceStatus,
      complianceReason,
      hasSensorData,
      hasActivityData,
      integrityStatus,
      integrityAlerts,
      medicationStatus: pMeds.length > 0 ? 'logged' : 'none_reported',
      activeTestDates,
      dailyLoads,
      medicationReports,
    };
  });

  return {
    totalRegistered: pRows.length,
    compliantCount,
    nonCompliantCount,
    activeTestUserCount,
    integrityAlertCount,
    medicationReportCount,
    participants: resultItems,
  };
}
