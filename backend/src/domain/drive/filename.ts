/**
 * The legacy upload filename is the only link between a Drive object and a
 * participant. Android writes `PDData_{userId}_{yyyy-MM-dd}.zip` and iOS appends
 * `_iOS`; both are reproduced here from the clients rather than inferred from
 * the corpus, so a filename this parser rejects is genuinely unrecognised.
 *
 * Pure on purpose: misattributing one participant-day to the wrong person is
 * the worst outcome this migration can produce, so the rule that decides it
 * should be readable and testable without a Drive credential.
 */

export type Platform = 'android' | 'ios';

export interface ParsedUploadFilename {
  legacyUserId: string;
  /** ISO calendar date, exactly as it appears in the filename. */
  collectionDate: string;
  platform: Platform;
}

export type FilenameRejection = 'not_an_upload' | 'malformed_date';

export type FilenameParse =
  | { ok: true; value: ParsedUploadFilename }
  | { ok: false; reason: FilenameRejection };

/**
 * The user id is greedy because it may itself contain underscores — three ID
 * formats exist in production and `pd_53a21c75` is one of them. The date is
 * fixed-width, so the greedy group backtracks to exactly the right boundary.
 */
const UPLOAD_FILENAME = /^PDData_(.+)_(\d{4}-\d{2}-\d{2})(_iOS)?\.zip$/;

/** Rejects 2026-02-31 and friends, which a `\d{2}` pattern happily accepts. */
function isRealCalendarDate(value: string): boolean {
  const [year, month, day] = value.split('-').map(Number) as [number, number, number];
  const date = new Date(Date.UTC(year, month - 1, day));

  return (
    date.getUTCFullYear() === year &&
    date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day
  );
}

export function parseUploadFilename(filename: string): FilenameParse {
  const match = UPLOAD_FILENAME.exec(filename.trim());
  if (!match) return { ok: false, reason: 'not_an_upload' };

  const [, legacyUserId, collectionDate, iosSuffix] = match as unknown as [
    string,
    string,
    string,
    string | undefined,
  ];

  if (!isRealCalendarDate(collectionDate)) return { ok: false, reason: 'malformed_date' };

  return {
    ok: true,
    value: {
      legacyUserId,
      collectionDate,
      platform: iosSuffix ? 'ios' : 'android',
    },
  };
}
