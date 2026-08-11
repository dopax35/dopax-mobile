import { describe, expect, it } from 'vitest';
import { ingestStructuredCsv, emptyZipParsePlan } from '../src/domain/drive/zip-parse.js';
import { classifyZipEntry } from '../src/domain/drive/zip-kinds.js';

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
      '1000,0,START,,Left,Right,Left',
      '1100,100,SAMPLE,Left,Left,Right,Left',
      '1200,200,SAMPLE,Left,Left,Right,Left',
      '1300,300,END,,Left,Right,Left',
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
      'timestamp_ms,taken_ms,med_name,dosage\n2000,1500,Dopicar,250 mg\n',
      '2026-07-26',
    );
    ingestStructuredCsv(
      plan,
      'd/questionnaire.csv',
      10,
      'timestamp_ms,date,time,q1_text,q2_score\n3000,2026-07-26,10:00,hello,2\n',
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
