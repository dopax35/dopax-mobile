import { describe, expect, it } from 'vitest';
import {
  assessAssetQuality,
  catalogueEntry,
  emptyZipParsePlan,
  ingestStructuredCsv,
  timestampFromStreamHead,
  unambiguousSessionPaths,
  type PlannedTestSession,
} from '../src/domain/drive/zip-parse.js';
import { classifyZipEntry } from '../src/domain/drive/zip-kinds.js';

/**
 * Collectors write epoch milliseconds, and the parser rejects anything outside
 * 2015–2100 as corrupt, so fixtures have to sit in a plausible study window.
 */
const at = (hour: number, minute = 0): string => String(Date.UTC(2026, 6, 26, hour, minute));
const iso = (hour: number, minute = 0): string =>
  new Date(Date.UTC(2026, 6, 26, hour, minute)).toISOString();
/** Sub-second offsets from 09:00, for the sample-rate timings inside one test. */
const after = (offsetMs: number): string => String(Date.UTC(2026, 6, 26, 9) + offsetMs);

describe('classifyZipEntry', () => {
  it('maps motor and stream basenames regardless of folder prefix', () => {
    expect(classifyZipEntry('2026-07-26/finger_tapping.csv')).toBe('finger_tapping');
    expect(classifyZipEntry('2026-07-26/sensors.csv')).toBe('stream');
    expect(classifyZipEntry('2026-07-26/.uploaded')).toBe('marker');
  });
});

describe('ingestStructuredCsv', () => {
  it('collapses START/SAMPLE/END motor rows into one completed session', () => {
    const csv = [
      'timestamp_ms,elapsed_ms,event,button_id,side,dominant_hand,affected_side',
      `${after(0)},0,START,,Left,Right,Left`,
      `${after(100)},100,SAMPLE,Left,Left,Right,Left`,
      `${after(200)},200,SAMPLE,Left,Left,Right,Left`,
      `${after(300)},300,END,,Left,Right,Left`,
      '',
    ].join('\n');

    const plan = emptyZipParsePlan();
    ingestStructuredCsv(plan, '2026-07-26/finger_tapping.csv', csv.length, csv, '2026-07-26');

    expect(plan.sessions).toHaveLength(1);
    expect(plan.sessions[0]).toMatchObject({
      testType: 'finger_tapping',
      completed: true,
      side: 'Left',
      dominantHand: 'Right',
      affectedSide: 'Left',
      metrics: { sampleCount: 2, elapsedMs: 300 },
    });
    expect(plan.sessions[0]!.durationMs).toBe(300);
  });

  it('parses medication and questionnaire rows', () => {
    const plan = emptyZipParsePlan();
    ingestStructuredCsv(
      plan,
      'd/medication.csv',
      10,
      `timestamp_ms,taken_ms,med_name,dosage\n${at(11)},${at(9)},Dopicar,250 mg\n`,
      '2026-07-26',
    );
    ingestStructuredCsv(
      plan,
      'd/questionnaire.csv',
      10,
      `timestamp_ms,date,time,q1_text,q2_score\n${at(10)},2026-07-26,10:00,hello,2\n`,
      '2026-07-26',
    );

    expect(plan.medications[0]).toMatchObject({
      medicationName: 'Dopicar',
      dosage: '250 mg',
    });
    expect(plan.questionnaires[0]?.answers).toMatchObject({ q1_text: 'hello', q2_score: '2' });
  });

  it('aggregates heart-rate samples into a daily summary', () => {
    const plan = emptyZipParsePlan();
    ingestStructuredCsv(
      plan,
      'd/heart_rate.csv',
      10,
      'timestamp_ms,bpm,rr_interval_ms,device_address,device_name\n1,60,,,\n2,80,,,\n',
      '2026-07-26',
    );

    expect(plan.heartRateSummaries).toEqual([
      { day: '2026-07-26', samples: 2, bpmMin: 60, bpmMax: 80, bpmAvg: 70 },
    ]);
  });
});

describe('asset capture time', () => {
  it('dates a file by its earliest row rather than its first', () => {
    const csv = ['timestamp_ms,bpm', `${at(11)},70`, `${at(9)},65`, ''].join('\n');
    const plan = emptyZipParsePlan();

    ingestStructuredCsv(plan, 'd/heart_rate.csv', csv.length, csv, '2026-07-26');

    expect(plan.files[0]!.capturedAt?.toISOString()).toBe(iso(9));
  });

  it('dates a dose by when it was taken, not when the row was written', () => {
    const csv = ['timestamp_ms,taken_ms,med_name,dosage', `${at(11)},${at(9)},Dopicar,250 mg`, ''].join(
      '\n',
    );
    const plan = emptyZipParsePlan();

    ingestStructuredCsv(plan, 'd/medication.csv', csv.length, csv, '2026-07-26');

    expect(plan.files[0]!.capturedAt?.toISOString()).toBe(iso(9));
  });

  it('leaves capture time null rather than inventing one', () => {
    const csv = 'label,value\nfoo,1\n';
    const plan = emptyZipParsePlan();

    ingestStructuredCsv(plan, 'd/questionnaire.csv', csv.length, csv, '2026-07-26');

    expect(plan.files[0]!.capturedAt).toBeNull();
  });

  it('finds a stream timestamp column wherever it sits in the header', () => {
    expect(timestampFromStreamHead('x,y,timestamp_ms', `1,2,${at(8)}`)?.toISOString()).toBe(iso(8));
    expect(timestampFromStreamHead('timestamp_ms,x', `${at(8, 30)},1`)?.toISOString()).toBe(
      iso(8, 30),
    );
  });

  it('returns null for a stream with no timestamp column', () => {
    expect(timestampFromStreamHead('x,y', '1,2')).toBeNull();
  });
});

describe('assessAssetQuality', () => {
  const tabular = { kind: 'stream' as const, pathInZip: 'd/sensors.csv' };

  it('calls a header-only csv unusable', () => {
    const csv = 'timestamp_ms,bpm\n';
    const plan = emptyZipParsePlan();

    ingestStructuredCsv(plan, 'd/heart_rate.csv', csv.length, csv, '2026-07-26');

    expect(plan.files[0]!.qualityStatus).toBe('unusable');
    expect(plan.files[0]!.qualityFlags).toContain('no_rows');
  });

  it('calls an empty file unusable', () => {
    expect(assessAssetQuality({ ...tabular, bytes: 0, rowCount: 0, capturedAt: null })).toMatchObject(
      { status: 'unusable' },
    );
  });

  it('calls an undated but populated stream suspect rather than unusable', () => {
    const result = assessAssetQuality({ ...tabular, bytes: 1024, rowCount: 500, capturedAt: null });

    expect(result.status).toBe('suspect');
    expect(result.flags).toEqual(['no_timestamp']);
  });

  it('passes a dated, populated stream', () => {
    const result = assessAssetQuality({
      ...tabular,
      bytes: 1024,
      rowCount: 500,
      capturedAt: new Date(iso(9)),
    });

    expect(result).toEqual({ status: 'ok', flags: [] });
  });

  it('does not judge a voice recording by row count', () => {
    const plan = emptyZipParsePlan();

    catalogueEntry(plan, 'd/voice_2026-07-26.m4a', 48_000);

    // 'unknown' is the honest answer for a binary we never inspected — not 'ok'.
    expect(plan.files[0]!.qualityStatus).toBe('unknown');
    expect(plan.files[0]!.qualityFlags).toEqual([]);
  });
});

describe('unambiguousSessionPaths', () => {
  const session = (rawObjectKey: string): PlannedTestSession => ({
    testType: 'finger_tapping',
    startedAt: new Date(iso(9)),
    endedAt: null,
    durationMs: null,
    side: null,
    dominantHand: null,
    affectedSide: null,
    completed: true,
    metrics: {},
    rawObjectKey,
  });

  it('links a path that exactly one session claims', () => {
    expect(unambiguousSessionPaths([session('d/voice_test.csv')])).toEqual(
      new Set(['d/voice_test.csv']),
    );
  });

  it('refuses to pick between several sessions in one file', () => {
    const paths = unambiguousSessionPaths([
      session('d/finger_tapping.csv'),
      session('d/finger_tapping.csv'),
      session('d/tmt_results.csv'),
    ]);

    expect(paths.has('d/finger_tapping.csv')).toBe(false);
    expect(paths.has('d/tmt_results.csv')).toBe(true);
  });
});
