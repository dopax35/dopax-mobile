/** Response shapes served by the backend's /v1/admin routes. */

export interface Overview {
  enrolment: {
    total: number;
    testAccounts: number;
    byStatus: Record<string, number>;
    byProvider: Record<string, number>;
  };
  uploads: {
    total: number;
    bytes: number;
    byStatus: Record<string, number>;
    bySource: Record<string, number>;
    participantsWithUploads: number;
    earliestDate: string | null;
    latestDate: string | null;
  };
  activity: {
    events: number;
    testSessions: number;
    dailySummaries: number;
  };
  dataQuality: {
    openConflicts: number;
    participantsNeedingIdResolution: number;
    /** False when the database predates migration 0003, so the count is unknown. */
    exceptionsAvailable: boolean;
    openExceptions: number;
    exceptionsByReason: Record<string, number>;
  };
  reconciliation: {
    latest: ReconciliationRun | null;
    flip: FlipReadiness;
  };
  pipeline: {
    uploadsAwaitingParse: number;
    activityDependsOnParse: boolean;
    schemaOutOfDate: { missing: string; migration: string } | null;
  };
}

export interface FlipReadiness {
  consecutiveCleanRuns: number;
  required: number;
  ready: boolean;
  blockedBy: string | null;
}

export interface ReconciliationRun {
  id: string;
  runAt: string;
  mode: string;
  status: string;
  driveObjects: number;
  driveBytes: number;
  dbUploads: number;
  dbParsed: number;
}

export interface ParticipantSummary {
  id: string;
  participantCode: string;
  status: string;
  cohort: string | null;
  isTestAccount: boolean;
  enrolledAt: string | null;
  legacyFileUserIds: string[];
  provider: string | null;
  lastSignInAt: string | null;
  uploadCount: number;
  lastUploadDate: string | null;
  firstUploadDate: string | null;
  hasProfile: boolean;
  /** Present only for the admin role. */
  email?: string;
  displayName?: string | null;
  firebaseUid?: string | null;
}

export interface ParticipantList {
  total: number;
  limit: number;
  offset: number;
  identityVisible: boolean;
  participants: ParticipantSummary[];
}

export interface Adherence {
  window: { from: string; to: string };
  expectedDays: number;
  daysWithUpload: number;
  coverage: number | null;
  lastUploadDate: string | null;
  currentGapDays: number;
  gaps: { from: string; to: string; days: number }[];
  platforms: string[];
}

export interface Upload {
  id: string;
  collectionDate: string;
  platform: string;
  status: string;
  source: string;
  filename: string;
  bytes: number | null;
  receivedAt: string | null;
  parsedAt: string | null;
  error: string | null;
}

export interface ParticipantDetail {
  participant: ParticipantSummary & { createdAt: string | null };
  identities: {
    provider: string;
    email?: string | null;
    emailVerified?: boolean;
    displayName?: string | null;
    firebaseUid?: string | null;
    createdAt: string | null;
    lastSignInAt: string | null;
  }[];
  profile: {
    revision: number;
    age: number | null;
    gender: string | null;
    dominantHand: string | null;
    affectedSide: string | null;
    medications: unknown;
    updatedAt: string;
  } | null;
  consents: {
    documentVersion: string;
    signatureName: string;
    grantedAt: string;
    revokedAt: string | null;
    platform: string | null;
    appVersion: string | null;
  }[];
  adherence: Adherence;
  uploads: Upload[];
  events: {
    occurredAt: string;
    receivedAt: string;
    eventType: string;
    appVersion: string | null;
    payload: Record<string, unknown>;
  }[];
  testSessions: {
    testType: string;
    startedAt: string;
    durationMs: number | null;
    side: string | null;
    completed: boolean;
    metrics: Record<string, unknown>;
  }[];
  dailySummaries: { day: string; metrics: Record<string, unknown> }[];
}

export interface UploadFeedItem extends Omit<Upload, 'receivedAt' | 'parsedAt'> {
  participantId: string;
  participantCode: string;
}

export interface CoverageDay {
  collectionDate: string;
  platform: string;
  participants: number;
  uploads: number;
  bytes: number;
}

export interface BootstrapStep {
  name: string;
  status: string;
  rowsWritten: number | null;
  attempts: number;
  startedAt: string;
  completedAt: string | null;
  durationMs: number | null;
  error: string | null;
}

export interface DataQuality {
  conflicts: {
    id: string;
    legacyCode: string;
    participantIds: string[];
    participantCodes: string[];
    firebaseUids: string[];
    detectedAt: string;
    resolvedAt: string | null;
    resolutionNote: string | null;
  }[];
  exceptions: {
    id: string;
    driveFileId: string;
    filename: string;
    bytes: number | null;
    reason: string;
    detail: Record<string, unknown>;
    firstSeenAt: string;
    resolvedAt: string | null;
    resolutionNote: string | null;
  }[];
  /** Set when the database predates migration 0003. */
  schemaOutOfDate?: {
    missing: string;
    migration: string;
    detail: string;
  };
}

export interface AuditEntry {
  id: string;
  actorType: string;
  actorId: string | null;
  action: string;
  subject: string | null;
  occurredAt: string;
  metadata: Record<string, unknown> | null;
}

export interface ParticipantProgressItem {
  participantId: string;
  participantCode: string;
  legacyFileUserIds: string[];
  status: string;
  isTestAccount: boolean;
  email?: string | null;
  displayName?: string | null;
  firebaseUid?: string | null;
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
  identityVisible: boolean;
  participants: ParticipantProgressItem[];
}

