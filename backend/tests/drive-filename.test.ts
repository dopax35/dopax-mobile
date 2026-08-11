import { describe, expect, it } from 'vitest';
import { parseUploadFilename } from '../src/domain/drive/filename.js';

describe('parseUploadFilename', () => {
  it('reads an Android upload', () => {
    expect(parseUploadFilename('PDData_9EEBCD_2026-08-03.zip')).toEqual({
      ok: true,
      value: { legacyUserId: '9EEBCD', collectionDate: '2026-08-03', platform: 'android' },
    });
  });

  it('reads an iOS upload from the _iOS suffix', () => {
    expect(parseUploadFilename('PDData_9EEBCD_2026-08-03_iOS.zip')).toEqual({
      ok: true,
      value: { legacyUserId: '9EEBCD', collectionDate: '2026-08-03', platform: 'ios' },
    });
  });

  it('keeps a participant code that itself contains underscores intact', () => {
    // The iOS format is "pd_" + 8 hex, so a naive split on "_" attributes the
    // whole day to a participant called "pd".
    const parsed = parseUploadFilename('PDData_pd_53a21c75_2026-07-14_iOS.zip');

    expect(parsed).toEqual({
      ok: true,
      value: { legacyUserId: 'pd_53a21c75', collectionDate: '2026-07-14', platform: 'ios' },
    });
  });

  it('handles a 28-character Firebase UID as the code', () => {
    const parsed = parseUploadFilename('PDData_DmZLr8ymaffMcamu5AuDrB1DzB82_2026-06-01.zip');

    expect(parsed.ok && parsed.value.legacyUserId).toBe('DmZLr8ymaffMcamu5AuDrB1DzB82');
  });

  it('rejects a date that does not exist on a calendar', () => {
    expect(parseUploadFilename('PDData_9EEBCD_2026-02-31.zip')).toEqual({
      ok: false,
      reason: 'malformed_date',
    });
  });

  it.each([
    'PDData_9EEBCD_2026-08-03.zip.tmp',
    'PDData_9EEBCD.zip',
    'PDData__2026-08-03.zip',
    'export_9EEBCD_2026-08.xlsx',
    'Screenshot.png',
  ])('rejects %s rather than guessing an owner', (filename) => {
    expect(parseUploadFilename(filename)).toEqual({ ok: false, reason: 'not_an_upload' });
  });
});
