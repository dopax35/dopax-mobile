import { describe, expect, it } from 'vitest';
import {
  assessFlipReadiness,
  CLEAN_RUNS_REQUIRED_FOR_FLIP,
  canSeeClinicalDetail,
  canSeeIdentity,
  redactParticipant,
  summariseAdherence,
} from '../src/domain/admin/view.js';

const participant = {
  id: 'p1',
  participantCode: '9EEBCD',
  status: 'active',
  isTestAccount: false,
  cohort: null,
  enrolledAt: null,
  provider: 'password',
  email: 'someone@example.com',
  displayName: 'Some One',
  firebaseUid: 'DmZLr8ymaffMcamu5AuDrB1DzB82',
  legacyFileUserIds: ['9EEBCD'],
};

describe('role visibility', () => {
  it('gives identifying fields to admins only', () => {
    expect(canSeeIdentity('admin')).toBe(true);
    expect(canSeeIdentity('researcher')).toBe(false);
    expect(canSeeIdentity('viewer')).toBe(false);
  });

  it('gives clinical detail to researchers but not viewers', () => {
    expect(canSeeClinicalDetail('researcher')).toBe(true);
    expect(canSeeClinicalDetail('viewer')).toBe(false);
  });

  it('keeps the participant code, which is the study pseudonym', () => {
    const redacted = redactParticipant(participant, 'researcher');
    expect(redacted).toMatchObject({ participantCode: '9EEBCD', status: 'active' });
  });

  it('removes identity keys entirely rather than nulling them', () => {
    const redacted = redactParticipant(participant, 'researcher') as Record<string, unknown>;

    expect('email' in redacted).toBe(false);
    expect('displayName' in redacted).toBe(false);
    expect('firebaseUid' in redacted).toBe(false);
  });

  it('leaves an admin view untouched', () => {
    expect(redactParticipant(participant, 'admin')).toEqual(participant);
  });
});

describe('adherence', () => {
  const window = { from: '2026-07-01', to: '2026-07-10' };

  it('reports no coverage rather than 0% when a participant never uploaded', () => {
    const summary = summariseAdherence([], window);

    expect(summary.coverage).toBeNull();
    expect(summary.lastUploadDate).toBeNull();
    expect(summary.gaps).toEqual([]);
  });

  /**
   * Measured from the first upload, not the window start: counting the days
   * before anyone ever uploaded would report every late joiner as non-adherent.
   */
  it('measures from the first upload, not the start of the window', () => {
    const summary = summariseAdherence(
      [
        { collectionDate: '2026-07-09', platform: 'android', status: 'parsed' },
        { collectionDate: '2026-07-10', platform: 'android', status: 'parsed' },
      ],
      window,
    );

    expect(summary.expectedDays).toBe(2);
    expect(summary.coverage).toBe(1);
  });

  it('finds the gap between two upload runs', () => {
    const summary = summariseAdherence(
      [
        { collectionDate: '2026-07-01', platform: 'ios', status: 'parsed' },
        { collectionDate: '2026-07-05', platform: 'ios', status: 'parsed' },
      ],
      window,
    );

    expect(summary.daysWithUpload).toBe(2);
    expect(summary.expectedDays).toBe(10);
    expect(summary.gaps).toEqual([
      { from: '2026-07-06', to: '2026-07-10', days: 5 },
      { from: '2026-07-02', to: '2026-07-04', days: 3 },
    ]);
  });

  it('counts a trailing gap as the current one, which is what "stopped using the app" looks like', () => {
    const summary = summariseAdherence(
      [{ collectionDate: '2026-07-01', platform: 'ios', status: 'parsed' }],
      window,
    );

    expect(summary.currentGapDays).toBe(9);
    expect(summary.lastUploadDate).toBe('2026-07-01');
  });

  it('does not report a current gap for a participant who uploaded on the last day', () => {
    const summary = summariseAdherence(
      [
        { collectionDate: '2026-07-01', platform: 'ios', status: 'parsed' },
        { collectionDate: '2026-07-10', platform: 'ios', status: 'parsed' },
      ],
      window,
    );

    expect(summary.currentGapDays).toBe(0);
  });

  it('counts a participant-day once even when both platforms uploaded it', () => {
    const summary = summariseAdherence(
      [
        { collectionDate: '2026-07-01', platform: 'ios', status: 'parsed' },
        { collectionDate: '2026-07-01', platform: 'android', status: 'parsed' },
      ],
      { from: '2026-07-01', to: '2026-07-01' },
    );

    expect(summary.daysWithUpload).toBe(1);
    expect(summary.platforms).toEqual(['android', 'ios']);
  });

  it('ignores uploads outside the window', () => {
    const summary = summariseAdherence(
      [{ collectionDate: '2026-06-01', platform: 'ios', status: 'parsed' }],
      window,
    );

    expect(summary.daysWithUpload).toBe(0);
  });
});

describe('BOTH_ARCH flip readiness (R3)', () => {
  function runs(statuses: string[]) {
    return statuses.map((status, index) => ({
      status,
      runAt: new Date(Date.UTC(2026, 7, 1 + index)),
    }));
  }

  it('needs fourteen consecutive clean runs', () => {
    const assessment = assessFlipReadiness(runs(Array(14).fill('clean')));

    expect(assessment.required).toBe(CLEAN_RUNS_REQUIRED_FOR_FLIP);
    expect(assessment.consecutiveCleanRuns).toBe(14);
    expect(assessment.ready).toBe(true);
  });

  it('counts back from the newest run and stops at the first that is not clean', () => {
    // Newest first: clean, clean, discrepancies, then more clean ones that do
    // not count because the streak is broken.
    const assessment = assessFlipReadiness(
      runs(['clean', 'clean', 'clean', 'discrepancies', 'clean', 'clean']),
    );

    expect(assessment.consecutiveCleanRuns).toBe(2);
    expect(assessment.ready).toBe(false);
    expect(assessment.blockedBy).toBe('discrepancies');
  });

  it('is not ready when nothing has ever reconciled', () => {
    const assessment = assessFlipReadiness([]);

    expect(assessment.ready).toBe(false);
    expect(assessment.blockedBy).toMatch(/no reconciliation runs/);
  });

  it('is not ready on the current production state of four runs with discrepancies', () => {
    const assessment = assessFlipReadiness(runs(Array(4).fill('discrepancies')));

    expect(assessment.consecutiveCleanRuns).toBe(0);
    expect(assessment.ready).toBe(false);
  });
});
