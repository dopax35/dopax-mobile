/**
 * Pure CSV → planned rows for one upload ZIP.
 *
 * Motor SAMPLE rows are summarised into a session; high-rate streams are never
 * loaded here. No Drive or database access.
 */
import { parse } from 'csv-parse/sync';
import { classifyZipEntry, type ZipEntryKind } from './zip-kinds.js';

export interface PlannedUploadFile {
  pathInZip: string;
  kind: ZipEntryKind;
  rowCount: number;
  bytes: number;
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
    plan.files.push({
      pathInZip,
      kind,
      rowCount: Math.max(0, csv.trim().split('\n').length - 1),
      bytes,
    });
    return;
  }

  const rows = rowsOf(csv);
  plan.files.push({ pathInZip, kind, rowCount: rows.length, bytes });

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

export function catalogueEntry(
  plan: ZipParsePlan,
  pathInZip: string,
  bytes: number,
  rowCount: number | null = null,
): void {
  const kind = classifyZipEntry(pathInZip);
  if (kind === 'marker') return;
  plan.files.push({
    pathInZip,
    kind,
    rowCount: rowCount ?? 0,
    bytes,
  });
}
