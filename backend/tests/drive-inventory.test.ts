import { describe, expect, it } from 'vitest';
import {
  planDriveManifestImport,
  summariseExceptions,
  type ParticipantLookup,
} from '../src/domain/drive/inventory.js';
import type { DriveObject } from '../src/domain/drive/manifest.js';

const HEX_PARTICIPANT = '11111111-1111-4111-8111-111111111111';
const UID_PARTICIPANT = '22222222-2222-4222-8222-222222222222';

const lookup: ParticipantLookup = {
  participantIdByLegacyId: new Map([
    ['9EEBCD', HEX_PARTICIPANT],
    ['CejjAPR9H3NFgcqeNXeNvGxCHQC3', HEX_PARTICIPANT],
    ['DmZLr8ymaffMcamu5AuDrB1DzB82', UID_PARTICIPANT],
  ]),
  contestedCodes: new Set(['pd_53a21c75']),
};

function object(overrides: Partial<DriveObject> & { name: string }): DriveObject {
  return {
    fileId: `file-${overrides.name}`,
    bytes: 1_000,
    md5: 'abc',
    mimeType: 'application/zip',
    createdTime: '2026-08-03T10:00:00.000Z',
    modifiedTime: '2026-08-03T10:00:00.000Z',
    parentPath: '',
    ...overrides,
  };
}

describe('planDriveManifestImport', () => {
  it('attributes an upload through any of the participant’s historical id forms', () => {
    const plan = planDriveManifestImport(
      [
        object({ name: 'PDData_9EEBCD_2026-08-03.zip' }),
        object({ name: 'PDData_CejjAPR9H3NFgcqeNXeNvGxCHQC3_2026-08-04.zip' }),
      ],
      lookup,
    );

    expect(plan.exceptions).toEqual([]);
    expect(plan.uploads.map((upload) => upload.participantId)).toEqual([
      HEX_PARTICIPANT,
      HEX_PARTICIPANT,
    ]);
  });

  it('records the contested code as an exception instead of routing it', () => {
    const plan = planDriveManifestImport(
      [object({ name: 'PDData_pd_53a21c75_2026-07-14_iOS.zip' })],
      lookup,
    );

    expect(plan.uploads).toEqual([]);
    expect(plan.exceptions[0]).toMatchObject({
      reason: 'contested_participant_code',
      detail: { legacyUserId: 'pd_53a21c75', collectionDate: '2026-07-14' },
    });
  });

  it('records an unknown participant rather than inventing one', () => {
    const plan = planDriveManifestImport([object({ name: 'PDData_ZZZZZZ_2026-08-03.zip' })], lookup);

    expect(plan.uploads).toEqual([]);
    expect(plan.exceptions[0]).toMatchObject({ reason: 'unknown_participant' });
  });

  it('separates the same day on the two platforms', () => {
    const plan = planDriveManifestImport(
      [
        object({ name: 'PDData_9EEBCD_2026-08-03.zip' }),
        object({ name: 'PDData_9EEBCD_2026-08-03_iOS.zip' }),
      ],
      lookup,
    );

    expect(plan.uploads).toHaveLength(2);
    expect(plan.exceptions).toEqual([]);
  });

  it('keeps the largest of two objects for one participant-day and records the other', () => {
    const plan = planDriveManifestImport(
      [
        object({ name: 'PDData_9EEBCD_2026-08-03.zip', fileId: 'small', bytes: 10 }),
        object({ name: 'PDData_9EEBCD_2026-08-03.zip', fileId: 'large', bytes: 900 }),
      ],
      lookup,
    );

    expect(plan.uploads).toHaveLength(1);
    expect(plan.uploads[0]!.driveFileId).toBe('large');
    expect(plan.exceptions[0]).toMatchObject({
      driveFileId: 'small',
      reason: 'duplicate_participant_day',
      detail: { chosenDriveFileId: 'large' },
    });
  });

  it('breaks a byte-for-byte tie deterministically', () => {
    const objects = [
      object({ name: 'PDData_9EEBCD_2026-08-03.zip', fileId: 'bbb', createdTime: null }),
      object({ name: 'PDData_9EEBCD_2026-08-03.zip', fileId: 'aaa', createdTime: null }),
    ];

    const forwards = planDriveManifestImport(objects, lookup);
    const backwards = planDriveManifestImport([...objects].reverse(), lookup);

    expect(forwards.uploads[0]!.driveFileId).toBe('aaa');
    expect(backwards.uploads[0]!.driveFileId).toBe('aaa');
  });

  it('accounts for every object, so nothing is silently dropped', () => {
    const objects = [
      object({ name: 'PDData_9EEBCD_2026-08-03.zip' }),
      object({ name: 'PDData_pd_53a21c75_2026-07-14_iOS.zip' }),
      object({ name: 'PDData_ZZZZZZ_2026-08-03.zip' }),
      object({ name: 'PDData_9EEBCD_2026-02-31.zip' }),
      object({ name: 'weekly_export.xlsx', bytes: 24 }),
    ];

    const plan = planDriveManifestImport(objects, lookup);

    expect(plan.uploads.length + plan.exceptions.length).toBe(objects.length);
    expect(plan.objectsSeen).toBe(objects.length);
    expect(plan.bytesSeen).toBe(4 * 1_000 + 24);
    expect(summariseExceptions(plan.exceptions)).toEqual({
      not_an_upload: 1,
      malformed_date: 1,
      unknown_participant: 1,
      contested_participant_code: 1,
      duplicate_participant_day: 0,
    });
  });
});
