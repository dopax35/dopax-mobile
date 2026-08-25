/**
 * Pure CSV → planned rows for one upload ZIP.
 *
 * Motor SAMPLE rows are summarised into a session; high-rate streams are never
 * loaded here. No Drive or database access.
 */
import { parse } from 'csv-parse/sync';
import { classifyZipEntry, type ZipEntryKind } from './zip-kinds.js';

/**
 * `unknown` is not a synonym for `ok`. It means this asset has no shape we know how
 * to judge — a voice recording, an opaque JSON blob — so the catalogue says so
 * rather than implying it was checked.
 */
export type AssetQualityStatus = 'ok' | 'suspect' | 'unusable' | 'unknown';

export interface PlannedUploadFile {
  pathInZip: string;
  kind: ZipEntryKind;
  rowCount: number;
  bytes: number;
  /** Earliest row timestamp in the file. Null when the source carries none. */
  capturedAt: Date | null;
  qualityStatus: AssetQualityStatus;
  qualityFlags: string[];
}

export interface PlannedTestSession {
  testType: string;
  startedAt: Date;
  endedAt: Date | null;
  durationMs: number | null;
  side: string | null;
  dominantHand: string | null;
  affectedSide: string | null;
  completed: boolean;
  metrics: Record<string, unknown>;
  rawObjectKey: string;
}

export interface PlannedQuestionnaire {
  submittedAt: Date;
  answers: Record<string, unknown>;
}

export interface PlannedMedication {
  takenAt: Date;
  medicationName: string | null;
  dosage: string | null;
}

export interface PlannedActivity {
  startedAt: Date;
  activityType: string | null;
  timeOfDay: string | null;
  source: string | null;
  durationMin: number | null;
  calories: number | null;
  avgHeartRate: number | null;
}

export interface PlannedSleep {
  sleepStart: Date;
  sleepEnd: Date | null;
  source: string | null;
  provider: string | null;
  stageMinutes: Record<string, number>;
}

export interface PlannedHeartRateSummary {
  day: string;
  samples: number;
  bpmMin: number | null;
  bpmMax: number | null;
  bpmAvg: number | null;
}

export interface ZipParsePlan {
  files: PlannedUploadFile[];
  sessions: PlannedTestSession[];
  questionnaires: PlannedQuestionnaire[];
  medications: PlannedMedication[];
  activities: PlannedActivity[];
  sleeps: PlannedSleep[];
  heartRateSummaries: PlannedHeartRateSummary[];
}

function rowsOf(csv: string): Record<string, string>[] {
  const trimmed = csv.replace(/^\uFEFF/, '').trim();
  if (!trimmed) return [];

  return parse(trimmed, {
    columns: true,
    skip_empty_lines: true,
    relax_column_count: true,
    trim: true,
  }) as Record<string, string>[];
}

function msToDate(value: string | undefined): Date | null {
  if (!value) return null;
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) return null;
  const date = new Date(n);
  if (Number.isNaN(date.getTime())) return null;
  // Reject corrupt / ns-as-ms values that Postgres cannot store (e.g. year 58115).
  const year = date.getUTCFullYear();
  if (year < 2015 || year > 2100) return null;
  return date;
}

function num(value: string | undefined): number | null {
  if (value === undefined || value === '') return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

/**
 * Epoch-millisecond columns used across the collectors. Ordered by how specific
 * they are to the event the row describes, so a medication row is dated by when the
 * dose was taken rather than by when the app wrote the line.
 */
const TIMESTAMP_COLUMNS = [
  'taken_ms',
  'start_time_ms',
  'sleep_start_ms',
  'time_of_day_ms',
  'timestamp_ms',
  'time_ms',
  'ts_ms',
  'epoch_ms',
] as const;

/** Exposed so the streaming scanner can date a file it never fully parses. */
export function parseEpochMs(value: string | undefined): Date | null {
  return msToDate(value);
}

function earliestTimestamp(rows: Record<string, string>[]): Date | null {
  let earliest: Date | null = null;

  for (const row of rows) {
    for (const column of TIMESTAMP_COLUMNS) {
      const at = msToDate(row[column]);
      if (!at) continue;
      if (!earliest || at.getTime() < earliest.getTime()) earliest = at;
      break;
    }
  }

  return earliest;
}

/**
 * Dates a high-rate stream from its header plus first data row, so a multi-hundred-
 * megabyte sensor CSV never has to be held in memory to be catalogued.
 *
 * Naive comma splitting is safe here: stream CSVs are numeric columns written by our
 * own collectors, with no quoted fields.
 */
export function timestampFromStreamHead(header: string, firstRow: string): Date | null {
  const columns = header
    .replace(/^\uFEFF/, '')
    .trim()
    .split(',')
    .map((name) => name.trim());
  const values = firstRow.trim().split(',');

  for (const column of TIMESTAMP_COLUMNS) {
    const index = columns.indexOf(column);
    if (index === -1) continue;
    const at = msToDate(values[index]?.trim());
    if (at) return at;
  }

  return null;
}

/** A file whose rows are tabular, and which therefore ought to have rows and a time. */
function isTabular(kind: ZipEntryKind, pathInZip: string): boolean {
  if (kind === 'stream') return true;
  if (kind === 'voice_audio' || kind === 'json' || kind === 'marker') return false;
  return pathInZip.toLowerCase().endsWith('.csv');
}

/**
 * Whether a researcher can use this asset, as distinct from whether we managed to
 * parse it. `uploads.status` and `uploads.error` already answer the second question.
 *
 * Deliberately conservative: an empty or untimed file is reported, never repaired.
 */
export function assessAssetQuality(input: {
  kind: ZipEntryKind;
  pathInZip: string;
  bytes: number;
  rowCount: number;
  capturedAt: Date | null;
}): { status: AssetQualityStatus; flags: string[] } {
  const flags: string[] = [];
  const tabular = isTabular(input.kind, input.pathInZip);

  if (input.bytes === 0) flags.push('zero_bytes');
  if (tabular && input.rowCount === 0) flags.push('no_rows');
  if (tabular && input.capturedAt === null) flags.push('no_timestamp');

  if (flags.includes('zero_bytes') || flags.includes('no_rows')) {
    return { status: 'unusable', flags };
  }
  if (flags.length > 0) return { status: 'suspect', flags };

  return { status: tabular ? 'ok' : 'unknown', flags };
}

const MOTOR_TYPES: Record<string, string> = {
  finger_tapping: 'finger_tapping',
  fingers_test: 'fingers_test',
  hand_turning: 'hand_turning',
  leg_agility: 'leg_agility',
  spiral_tracing: 'spiral_tracing',
};

function parseMotorSessions(
  kind: string,
  pathInZip: string,
  csv: string,
): PlannedTestSession[] {
  const testType = MOTOR_TYPES[kind];
  if (!testType) return [];

  const rows = rowsOf(csv);
  const sessions: PlannedTestSession[] = [];
  let current: {
    startedAt: Date;
    side: string | null;
    dominantHand: string | null;
    affectedSide: string | null;
    samples: number;
  } | null = null;

  for (const row of rows) {
    const event = (row.event ?? '').toUpperCase();
    const at = msToDate(row.timestamp_ms);
    if (!at) continue;

    if (event === 'START') {
      current = {
        startedAt: at,
        side: row.side || row.hand || null,
        dominantHand: row.dominant_hand || null,
        affectedSide: row.affected_side || null,
        samples: 0,
      };
      continue;
    }

    if (event === 'SAMPLE' && current) {
      current.samples += 1;
      continue;
    }

    if (event === 'END') {
      const started = current?.startedAt ?? at;
      const samples = current?.samples ?? 0;
      sessions.push({
        testType,
        startedAt: started,
        endedAt: at,
        durationMs: Math.max(0, at.getTime() - started.getTime()),
        side: current?.side ?? row.side ?? row.hand ?? null,
        dominantHand: current?.dominantHand ?? row.dominant_hand ?? null,
        affectedSide: current?.affectedSide ?? row.affected_side ?? null,
        completed: true,
        metrics: { sampleCount: samples, elapsedMs: num(row.elapsed_ms) },
        rawObjectKey: pathInZip,
      });
      current = null;
    }
  }

  // Trailing START without END still records an incomplete session.
  if (current) {
    sessions.push({
      testType,
      startedAt: current.startedAt,
      endedAt: null,
      durationMs: null,
      side: current.side,
      dominantHand: current.dominantHand,
      affectedSide: current.affectedSide,
      completed: false,
      metrics: { sampleCount: current.samples },
      rawObjectKey: pathInZip,
    });
  }

  return sessions;
}

function parseTmt(pathInZip: string, csv: string): PlannedTestSession[] {
  return rowsOf(csv).flatMap((row) => {
    const startedAt = msToDate(row.start_time_ms) ?? msToDate(row.timestamp_ms);
    if (!startedAt) return [];
    const endedAt = msToDate(row.timestamp_ms);
    return [
      {
        testType: 'tmt',
        startedAt,
        endedAt,
        durationMs: num(row.total_time_ms),
        side: null,
        dominantHand: null,
        affectedSide: null,
        completed: true,
        metrics: {
          part: row.test_type ?? null,
          wrongTargetErrors: num(row.wrong_target_errors),
          liftOffErrors: num(row.lift_off_errors),
        },
        rawObjectKey: pathInZip,
      },
    ];
  });
}

function parseVoiceTest(pathInZip: string, csv: string): PlannedTestSession[] {
  return rowsOf(csv).flatMap((row) => {
    const startedAt = msToDate(row.timestamp_ms);
    if (!startedAt) return [];
    return [
      {
        testType: 'voice_test',
        startedAt,
        endedAt: null,
        durationMs: num(row.duration_ms),
        side: null,
        dominantHand: null,
        affectedSide: null,
        completed: true,
        metrics: {
          task: row.task ?? null,
          f0MeanHz: num(row.f0_mean_hz),
          jitterPct: num(row.jitter_pct),
          shimmerDb: num(row.shimmer_db),
          hnrDb: num(row.hnr_db),
          ddkRateHz: num(row.ddk_rate_hz),
          decibelDecay: num(row.decibel_decay),
        },
        rawObjectKey: pathInZip,
      },
    ];
  });
}

function parseQuestionnaire(csv: string): PlannedQuestionnaire[] {
  return rowsOf(csv).flatMap((row) => {
    const submittedAt = msToDate(row.timestamp_ms);
    if (!submittedAt) return [];
    const { timestamp_ms: _t, ...answers } = row;
    return [{ submittedAt, answers }];
  });
}

function parseMedication(csv: string): PlannedMedication[] {
  return rowsOf(csv).flatMap((row) => {
    const takenAt = msToDate(row.taken_ms) ?? msToDate(row.timestamp_ms);
    if (!takenAt) return [];
    return [
      {
        takenAt,
        medicationName: row.med_name || null,
        dosage: row.dosage || null,
      },
    ];
  });
}

function parseActivity(csv: string): PlannedActivity[] {
  return rowsOf(csv).flatMap((row) => {
    const startedAt = msToDate(row.time_of_day_ms) ?? msToDate(row.timestamp_ms);
    if (!startedAt) return [];
    return [
      {
        startedAt,
        activityType: row.activity_type || null,
        timeOfDay: row.time_of_day_ms || null,
        source: row.source || null,
        durationMin: num(row.duration_min),
        calories: num(row.calories),
        avgHeartRate: num(row.avg_heart_rate),
      },
    ];
  });
}

function parseSleep(csv: string): PlannedSleep[] {
  return rowsOf(csv).flatMap((row) => {
    const sleepStart = msToDate(row.sleep_start_ms) ?? msToDate(row.timestamp_ms);
    if (!sleepStart) return [];
    return [
      {
        sleepStart,
        sleepEnd: msToDate(row.sleep_end_ms),
        source: row.source || null,
        provider: row.provider || null,
        stageMinutes: {
          timeInBed: num(row.time_in_bed_min) ?? 0,
          totalSleep: num(row.total_sleep_min) ?? 0,
          light: num(row.light_min) ?? 0,
          deep: num(row.deep_min) ?? 0,
          rem: num(row.rem_min) ?? 0,
          awake: num(row.awake_min) ?? 0,
          unspecified: num(row.unspecified_min) ?? 0,
        },
      },
    ];
  });
}

function parseHeartRate(csv: string, collectionDate: string): PlannedHeartRateSummary[] {
  const rows = rowsOf(csv);
  const bpms = rows.map((row) => num(row.bpm)).filter((n): n is number => n !== null);
  if (bpms.length === 0) return [];

  const sum = bpms.reduce((a, b) => a + b, 0);
  return [
    {
      day: collectionDate,
      samples: bpms.length,
      bpmMin: Math.min(...bpms),
      bpmMax: Math.max(...bpms),
      bpmAvg: sum / bpms.length,
    },
  ];
}

/**
 * The ZIP paths that exactly one session claims, and which can therefore be linked
 * to it without guessing.
 *
 * A motor CSV holds several START/END cycles and so produces several sessions from
 * one path. Attributing that file to whichever cycle parsed first would silently
 * mis-file research data, so those paths are excluded and the row keeps a null
 * `session_id`; `test_sessions.raw_object_key` still records the provenance.
 */
export function unambiguousSessionPaths(sessions: PlannedTestSession[]): Set<string> {
  const counts = new Map<string, number>();
  for (const session of sessions) {
    counts.set(session.rawObjectKey, (counts.get(session.rawObjectKey) ?? 0) + 1);
  }

  return new Set([...counts].filter(([, count]) => count === 1).map(([path]) => path));
}

export function emptyZipParsePlan(): ZipParsePlan {
  return {
    files: [],
    sessions: [],
    questionnaires: [],
    medications: [],
    activities: [],
    sleeps: [],
    heartRateSummaries: [],
  };
}

/**
 * Incorporates one ZIP entry's text (CSV) into the plan. Binary / stream
 * entries should call `catalogueEntry` instead.
 */
export function ingestStructuredCsv(
  plan: ZipParsePlan,
  pathInZip: string,
  bytes: number,
  csv: string,
  collectionDate: string,
): void {
  const kind = classifyZipEntry(pathInZip);

  // profile.csv embeds a JSON array in medications_json. Strict CSV parsing
  // rejects those quotes and would abort the whole ZIP; we only need it
  // catalogued here (Firestore is the profile source of truth later).
  if (kind === 'profile') {
    pushFile(plan, {
      pathInZip,
      kind,
      rowCount: Math.max(0, csv.trim().split('\n').length - 1),
      bytes,
      capturedAt: null,
    });
    return;
  }

  const rows = rowsOf(csv);
  pushFile(plan, {
    pathInZip,
    kind,
    rowCount: rows.length,
    bytes,
    capturedAt: earliestTimestamp(rows),
  });

  if (kind in MOTOR_TYPES) {
    plan.sessions.push(...parseMotorSessions(kind, pathInZip, csv));
  } else if (kind === 'tmt') {
    plan.sessions.push(...parseTmt(pathInZip, csv));
  } else if (kind === 'voice_test') {
    plan.sessions.push(...parseVoiceTest(pathInZip, csv));
  } else if (kind === 'questionnaire') {
    plan.questionnaires.push(...parseQuestionnaire(csv));
  } else if (kind === 'medication') {
    plan.medications.push(...parseMedication(csv));
  } else if (kind === 'physical_activity') {
    plan.activities.push(...parseActivity(csv));
  } else if (kind === 'sleep') {
    plan.sleeps.push(...parseSleep(csv));
  } else if (kind === 'heart_rate') {
    plan.heartRateSummaries.push(...parseHeartRate(csv, collectionDate));
  }
}

function pushFile(
  plan: ZipParsePlan,
  file: {
    pathInZip: string;
    kind: ZipEntryKind;
    rowCount: number;
    bytes: number;
    capturedAt: Date | null;
  },
): void {
  const quality = assessAssetQuality(file);
  plan.files.push({
    ...file,
    qualityStatus: quality.status,
    qualityFlags: quality.flags,
  });
}

export function catalogueEntry(
  plan: ZipParsePlan,
  pathInZip: string,
  bytes: number,
  rowCount: number | null = null,
  capturedAt: Date | null = null,
): void {
  const kind = classifyZipEntry(pathInZip);
  if (kind === 'marker') return;
  pushFile(plan, {
    pathInZip,
    kind,
    rowCount: rowCount ?? 0,
    bytes,
    capturedAt,
  });
}
